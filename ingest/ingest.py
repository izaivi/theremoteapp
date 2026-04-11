"""
The Remote — Fase 1 content ingest

Pipeline:
  1. TMDB (backbone)        → catálogo + metadata + watch providers por país
  2. OMDb (enrichment)      → IMDb / Rotten Tomatoes / Metacritic scores
  3. Watchmode (enrichment) → deep links + precios (US, MX, SE)
  4. RapidAPI (fallback)    → availability para ES (streaming-availability)
  5. Supabase upsert        → content + content_availability (service_role)

Uso:
    python ingest.py                # full run (todas las plataformas/países)
    python ingest.py --limit 10     # dry-ish run con pocos títulos por provider
    python ingest.py --platforms netflix,max
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
import time
from dataclasses import dataclass, field
from typing import Any

import requests
from dotenv import load_dotenv
from supabase import Client, create_client
from tenacity import retry, stop_after_attempt, wait_exponential

# ---------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------

load_dotenv()

TMDB_TOKEN = os.environ["TMDB_TOKEN"]
OMDB_API_KEY = os.environ["OMDB_API_KEY"]
WATCHMODE_API_KEY = os.environ["WATCHMODE_API_KEY"]
RAPIDAPI_KEY = os.environ["RAPIDAPI_KEY"]
SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_ROLE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

COUNTRIES = [c.strip() for c in os.environ.get("INGEST_COUNTRIES", "US,MX,ES,SE").split(",")]
LANGS = [l.strip() for l in os.environ.get("INGEST_LANGS", "en,es,sv").split(",")]
PAGES_PER_PROVIDER = int(os.environ.get("INGEST_PAGES_PER_PROVIDER", "3"))

# Países que Watchmode puede enriquecer (free tier = 3 países).
WATCHMODE_COUNTRIES = {"US", "MX", "SE"}
# Países que caen a RapidAPI como fallback.
RAPIDAPI_COUNTRIES = {"ES"}

# Plataformas soportadas en Fase 1 (id en DB ↔ tmdb_provider_id ↔ watchmode source id).
PLATFORMS = [
    # (db_id, slug, tmdb_provider_id, watchmode_source_id)
    (1, "netflix",      8,    203),
    (2, "max",          1899, 387),
    (3, "disney",       337,  372),
    (4, "prime",        119,  26),
    (5, "appletv",      350,  371),
    (6, "mubi",         11,   47),
    (7, "crunchyroll",  283,  283),
]

# Mapeo país → idioma principal para /details (sinopsis).
LANG_BY_COUNTRY = {"US": "en-US", "MX": "es-MX", "ES": "es-ES", "SE": "sv-SE"}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("ingest")

# ---------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------

TMDB_BASE = "https://api.themoviedb.org/3"
TMDB_HEADERS = {
    "Authorization": f"Bearer {TMDB_TOKEN}",
    "accept": "application/json",
}


@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=1, max=10))
def http_get(url: str, **kwargs) -> dict:
    r = requests.get(url, timeout=20, **kwargs)
    r.raise_for_status()
    return r.json()


# ---------------------------------------------------------------------
# Data shapes
# ---------------------------------------------------------------------

@dataclass
class ContentRow:
    tmdb_id: int
    media_type: str
    title: str
    original_title: str | None = None
    release_year: int | None = None
    runtime_minutes: int | None = None
    genres: list[int] = field(default_factory=list)
    classification: str | None = None
    poster_path: str | None = None
    backdrop_path: str | None = None
    synopsis_en: str | None = None
    synopsis_es: str | None = None
    synopsis_sv: str | None = None
    imdb_id: str | None = None
    imdb_score: float | None = None
    rt_score: int | None = None
    metacritic_score: int | None = None
    tmdb_popularity: float | None = None
    tmdb_vote_average: float | None = None
    tmdb_vote_count: int | None = None
    data_sources: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {k: v for k, v in self.__dict__.items() if v is not None or k in ("genres", "data_sources")}


@dataclass
class AvailabilityRow:
    content_id: int
    country_code: str
    platform_id: int
    monetization_type: str
    price_amount: float | None = None
    price_currency: str | None = None
    deep_link: str | None = None
    source: str = "tmdb"

    def to_dict(self) -> dict[str, Any]:
        return {k: v for k, v in self.__dict__.items() if v is not None}


# ---------------------------------------------------------------------
# TMDB
# ---------------------------------------------------------------------

def tmdb_discover(provider_id: int, country: str, page: int, media_type: str = "movie") -> list[dict]:
    url = f"{TMDB_BASE}/discover/{media_type}"
    params = {
        "language": LANG_BY_COUNTRY.get(country, "en-US"),
        "watch_region": country,
        "with_watch_providers": provider_id,
        "with_watch_monetization_types": "flatrate",
        "sort_by": "popularity.desc",
        "page": page,
    }
    data = http_get(url, headers=TMDB_HEADERS, params=params)
    return data.get("results", [])


def tmdb_details(tmdb_id: int, media_type: str, lang: str) -> dict:
    url = f"{TMDB_BASE}/{media_type}/{tmdb_id}"
    params = {"language": lang, "append_to_response": "external_ids"}
    return http_get(url, headers=TMDB_HEADERS, params=params)


def tmdb_watch_providers(tmdb_id: int, media_type: str) -> dict:
    url = f"{TMDB_BASE}/{media_type}/{tmdb_id}/watch/providers"
    return http_get(url, headers=TMDB_HEADERS)


def build_content_from_tmdb(tmdb_id: int, media_type: str) -> ContentRow | None:
    try:
        det_en = tmdb_details(tmdb_id, media_type, "en-US")
    except requests.HTTPError as e:
        log.warning("TMDB details failed for %s/%s: %s", media_type, tmdb_id, e)
        return None

    title = det_en.get("title") or det_en.get("name") or ""
    original_title = det_en.get("original_title") or det_en.get("original_name")

    release_date = det_en.get("release_date") or det_en.get("first_air_date") or ""
    release_year = int(release_date[:4]) if release_date[:4].isdigit() else None

    runtime = det_en.get("runtime")
    if runtime is None and det_en.get("episode_run_time"):
        runtime = det_en["episode_run_time"][0] if det_en["episode_run_time"] else None

    genres = [g["id"] for g in det_en.get("genres", []) if "id" in g]
    imdb_id = (det_en.get("external_ids") or {}).get("imdb_id") or det_en.get("imdb_id")

    row = ContentRow(
        tmdb_id=tmdb_id,
        media_type=media_type,
        title=title,
        original_title=original_title,
        release_year=release_year,
        runtime_minutes=runtime,
        genres=genres,
        poster_path=det_en.get("poster_path"),
        backdrop_path=det_en.get("backdrop_path"),
        synopsis_en=det_en.get("overview") or None,
        imdb_id=imdb_id,
        tmdb_popularity=det_en.get("popularity"),
        tmdb_vote_average=det_en.get("vote_average"),
        tmdb_vote_count=det_en.get("vote_count"),
        data_sources=["tmdb"],
    )

    # Sinopsis en ES y SV (mejor esfuerzo).
    try:
        det_es = tmdb_details(tmdb_id, media_type, "es-ES")
        row.synopsis_es = det_es.get("overview") or None
    except requests.HTTPError:
        pass
    try:
        det_sv = tmdb_details(tmdb_id, media_type, "sv-SE")
        row.synopsis_sv = det_sv.get("overview") or None
    except requests.HTTPError:
        pass

    return row


def tmdb_availability_rows(tmdb_id: int, media_type: str) -> list[AvailabilityRow]:
    try:
        data = tmdb_watch_providers(tmdb_id, media_type)
    except requests.HTTPError as e:
        log.warning("TMDB providers failed for %s/%s: %s", media_type, tmdb_id, e)
        return []

    results = data.get("results", {})
    rows: list[AvailabilityRow] = []
    tmdb_provider_to_db_id = {p[2]: p[0] for p in PLATFORMS}

    for country in COUNTRIES:
        block = results.get(country)
        if not block:
            continue
        for monetization in ("flatrate", "free", "ads", "rent", "buy"):
            for entry in block.get(monetization, []) or []:
                provider_id = entry.get("provider_id")
                db_id = tmdb_provider_to_db_id.get(provider_id)
                if db_id is None:
                    continue
                rows.append(AvailabilityRow(
                    content_id=tmdb_id,
                    country_code=country,
                    platform_id=db_id,
                    monetization_type=monetization,
                    deep_link=block.get("link"),
                    source="tmdb",
                ))
    return rows


# ---------------------------------------------------------------------
# OMDb — scores
# ---------------------------------------------------------------------

def omdb_enrich(row: ContentRow) -> None:
    if not row.imdb_id:
        return
    try:
        data = http_get(
            "https://www.omdbapi.com/",
            params={"i": row.imdb_id, "apikey": OMDB_API_KEY},
        )
    except requests.HTTPError as e:
        log.warning("OMDb failed for %s: %s", row.imdb_id, e)
        return

    if data.get("Response") != "True":
        return

    try:
        imdb = data.get("imdbRating")
        if imdb and imdb != "N/A":
            row.imdb_score = float(imdb)
    except ValueError:
        pass

    for r in data.get("Ratings", []) or []:
        src = r.get("Source", "")
        val = r.get("Value", "")
        if src == "Rotten Tomatoes" and val.endswith("%"):
            try:
                row.rt_score = int(val.rstrip("%"))
            except ValueError:
                pass
        elif src == "Metacritic" and "/" in val:
            try:
                row.metacritic_score = int(val.split("/")[0])
            except ValueError:
                pass

    if "omdb" not in row.data_sources:
        row.data_sources.append("omdb")


# ---------------------------------------------------------------------
# Watchmode — deep links para US/MX/SE
# ---------------------------------------------------------------------

def watchmode_enrich(tmdb_id: int, media_type: str) -> list[AvailabilityRow]:
    tmdb_ref = f"{'movie' if media_type == 'movie' else 'tv'}-{tmdb_id}"
    try:
        search = http_get(
            "https://api.watchmode.com/v1/search/",
            params={
                "apiKey": WATCHMODE_API_KEY,
                "search_field": "tmdb_movie_id" if media_type == "movie" else "tmdb_tv_id",
                "search_value": tmdb_id,
            },
        )
    except requests.HTTPError as e:
        log.warning("Watchmode search failed for %s: %s", tmdb_ref, e)
        return []

    hits = search.get("title_results") or []
    if not hits:
        return []
    wm_id = hits[0].get("id")
    if not wm_id:
        return []

    try:
        sources = http_get(
            f"https://api.watchmode.com/v1/title/{wm_id}/sources/",
            params={"apiKey": WATCHMODE_API_KEY},
        )
    except requests.HTTPError as e:
        log.warning("Watchmode sources failed for %s: %s", wm_id, e)
        return []

    wm_source_to_db_id = {p[3]: p[0] for p in PLATFORMS}
    rows: list[AvailabilityRow] = []
    for src in sources or []:
        country = src.get("region")
        if country not in WATCHMODE_COUNTRIES or country not in COUNTRIES:
            continue
        db_id = wm_source_to_db_id.get(src.get("source_id"))
        if db_id is None:
            continue
        monetization = (src.get("type") or "flatrate").lower()
        if monetization == "sub":
            monetization = "flatrate"
        if monetization not in ("flatrate", "free", "ads", "rent", "buy"):
            continue
        rows.append(AvailabilityRow(
            content_id=tmdb_id,
            country_code=country,
            platform_id=db_id,
            monetization_type=monetization,
            price_amount=src.get("price"),
            price_currency=src.get("format") if src.get("price") else None,
            deep_link=src.get("web_url"),
            source="watchmode",
        ))
    return rows


# ---------------------------------------------------------------------
# RapidAPI — streaming-availability para ES (fallback)
# ---------------------------------------------------------------------

def rapidapi_enrich_es(imdb_id: str | None, tmdb_id: int) -> list[AvailabilityRow]:
    if not imdb_id:
        return []
    try:
        data = http_get(
            "https://streaming-availability.p.rapidapi.com/shows/search/filters",
            headers={
                "x-rapidapi-key": RAPIDAPI_KEY,
                "x-rapidapi-host": "streaming-availability.p.rapidapi.com",
            },
            params={"country": "es", "imdb_id": imdb_id},
        )
    except requests.HTTPError as e:
        log.warning("RapidAPI ES failed for %s: %s", imdb_id, e)
        return []

    # El endpoint tiene un shape complejo; hacemos best-effort parseo de streamingOptions.es.
    shows = data.get("shows") or []
    if not shows:
        return []
    show = shows[0]
    opts = (show.get("streamingOptions") or {}).get("es") or []

    slug_to_db_id = {p[1]: p[0] for p in PLATFORMS}
    service_alias = {
        "netflix": "netflix", "max": "max", "hbo": "max",
        "disney": "disney", "disneyplus": "disney",
        "prime": "prime", "amazonprime": "prime",
        "apple": "appletv", "appletv": "appletv", "appletvplus": "appletv",
        "mubi": "mubi",
    }

    rows: list[AvailabilityRow] = []
    for o in opts:
        svc = ((o.get("service") or {}).get("id") or "").lower()
        slug = service_alias.get(svc)
        db_id = slug_to_db_id.get(slug) if slug else None
        if db_id is None:
            continue
        monetization = (o.get("type") or "subscription").lower()
        if monetization == "subscription":
            monetization = "flatrate"
        if monetization not in ("flatrate", "free", "ads", "rent", "buy"):
            continue
        price = (o.get("price") or {})
        rows.append(AvailabilityRow(
            content_id=tmdb_id,
            country_code="ES",
            platform_id=db_id,
            monetization_type=monetization,
            price_amount=price.get("amount"),
            price_currency=price.get("currency"),
            deep_link=o.get("link"),
            source="rapidapi",
        ))
    return rows


# ---------------------------------------------------------------------
# Supabase
# ---------------------------------------------------------------------

def supabase_client() -> Client:
    return create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)


def upsert_content(sb: Client, rows: list[ContentRow]) -> None:
    if not rows:
        return
    payload = [r.to_dict() for r in rows]
    sb.table("content").upsert(payload, on_conflict="tmdb_id").execute()
    log.info("Upserted %d content rows", len(payload))


def upsert_availability(sb: Client, rows: list[AvailabilityRow]) -> None:
    if not rows:
        return
    payload = [r.to_dict() for r in rows]
    # Dedup en memoria por PK compuesta.
    seen: dict[tuple, dict] = {}
    for r in payload:
        key = (r["content_id"], r["country_code"], r["platform_id"], r["monetization_type"])
        seen[key] = r
    deduped = list(seen.values())
    sb.table("content_availability").upsert(
        deduped,
        on_conflict="content_id,country_code,platform_id,monetization_type",
    ).execute()
    log.info("Upserted %d availability rows", len(deduped))


# ---------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------

def run(limit: int | None, platforms_filter: set[str] | None, skip_watchmode: bool = False, skip_rapidapi: bool = False, skip_omdb: bool = False, tmdb_ids: list[tuple[int, str]] | None = None) -> None:
    sb = supabase_client()

    discovered: set[tuple[int, str]] = set()  # (tmdb_id, media_type)

    # Manual injection — bypass discover entirely.
    if tmdb_ids:
        discovered = set(tmdb_ids)
        log.info("Manual inject: %d titles", len(discovered))
    else:
        for db_id, slug, tmdb_pid, _wm_id in PLATFORMS:
            if platforms_filter and slug not in platforms_filter:
                continue
            for country in COUNTRIES:
                for page in range(1, PAGES_PER_PROVIDER + 1):
                    try:
                        movies = tmdb_discover(tmdb_pid, country, page, "movie")
                        tv = tmdb_discover(tmdb_pid, country, page, "tv")
                    except requests.HTTPError as e:
                        log.warning("TMDB discover failed %s/%s p%d: %s", slug, country, page, e)
                        continue

                    for m in movies:
                        discovered.add((m["id"], "movie"))
                    for t in tv:
                        discovered.add((t["id"], "tv"))

                    if limit and len(discovered) >= limit:
                        break
                    time.sleep(0.25)  # cortesía con TMDB
                if limit and len(discovered) >= limit:
                    break

        if limit:
            discovered = set(list(discovered)[:limit])

    log.info("Discovered %d unique titles", len(discovered))

    content_rows: list[ContentRow] = []
    avail_rows: list[AvailabilityRow] = []

    for tmdb_id, media_type in discovered:
        row = build_content_from_tmdb(tmdb_id, media_type)
        if row is None:
            continue

        if not skip_omdb:
            try:
                omdb_enrich(row)
            except Exception as e:
                log.warning("OMDb failed for %d: %s", tmdb_id, e)
        content_rows.append(row)

        avail_rows.extend(tmdb_availability_rows(tmdb_id, media_type))

        if not skip_watchmode and any(c in WATCHMODE_COUNTRIES for c in COUNTRIES):
            try:
                avail_rows.extend(watchmode_enrich(tmdb_id, media_type))
            except Exception as e:
                log.warning("Watchmode failed for %d: %s", tmdb_id, e)

        if not skip_rapidapi and "ES" in COUNTRIES:
            try:
                avail_rows.extend(rapidapi_enrich_es(row.imdb_id, tmdb_id))
            except Exception as e:
                log.warning("RapidAPI failed for %d: %s", tmdb_id, e)

        time.sleep(0.15)

    # Upsert content primero (FK desde availability).
    # Batch en chunks para no blowout payload.
    CHUNK = 200
    for i in range(0, len(content_rows), CHUNK):
        upsert_content(sb, content_rows[i:i + CHUNK])
    for i in range(0, len(avail_rows), CHUNK):
        upsert_availability(sb, avail_rows[i:i + CHUNK])

    log.info("Done. content=%d availability=%d", len(content_rows), len(avail_rows))


def _parse_tmdb_ids(raw: str) -> list[tuple[int, str]]:
    """Parse 'movie:78,tv:1399,movie:348' into [(78,'movie'),(1399,'tv'),...]
    If no prefix given, default to 'movie'."""
    result: list[tuple[int, str]] = []
    for token in raw.split(","):
        token = token.strip()
        if not token:
            continue
        if ":" in token:
            kind, num = token.split(":", 1)
            result.append((int(num.strip()), kind.strip()))
        else:
            result.append((int(token), "movie"))
    return result


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--limit", type=int, default=None, help="Máximo de títulos a procesar (testing)")
    p.add_argument("--platforms", type=str, default=None, help="Comma-separated slugs (netflix,max,...)")
    p.add_argument("--skip-watchmode", action="store_true", help="Skip Watchmode enrichment (para runs frecuentes sin quemar free tier)")
    p.add_argument("--skip-rapidapi", action="store_true", help="Skip RapidAPI enrichment for ES availability")
    p.add_argument("--skip-omdb", action="store_true", help="Skip OMDb enrichment (IMDb/RT/Metacritic scores)")
    p.add_argument("--tmdb-ids", type=str, default=None,
                   help="Inject specific TMDB IDs (skip discover). "
                        "Format: 'movie:78,tv:1399,movie:348' or just '78,348' (defaults to movie)")
    args = p.parse_args()

    platforms_filter = None
    if args.platforms:
        platforms_filter = {s.strip() for s in args.platforms.split(",") if s.strip()}

    tmdb_ids = None
    if args.tmdb_ids:
        tmdb_ids = _parse_tmdb_ids(args.tmdb_ids)

    try:
        run(limit=args.limit, platforms_filter=platforms_filter,
            skip_watchmode=args.skip_watchmode, skip_rapidapi=args.skip_rapidapi,
            skip_omdb=args.skip_omdb, tmdb_ids=tmdb_ids)
    except KeyboardInterrupt:
        log.warning("Interrupted")
        sys.exit(130)


if __name__ == "__main__":
    main()
