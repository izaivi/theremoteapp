"""
Flixscope — content ingest (TMDB-only)

Pipeline:
  1. TMDB (backbone) → catálogo + metadata + watch providers por país
  2. Supabase upsert → content + content_availability (service_role)

Por qué TMDB-only:
  - Watchmode fue retirado en Build 11 — la app construye search URLs por
    plataforma en runtime (netflix.com/search?q=TITLE) en lugar de deep links.
  - RapidAPI (streaming-availability) fue retirado en Fase 4.2 — TMDB
    cubre los mismos países (US/MX/ES/SE) con suficiente fidelidad y nos
    quita una dependencia + un costo.
  - OMDb (IMDb / Rotten Tomatoes / Metacritic) corre APARTE en
    `omdb_backfill.py` por batches (~1000/día), porque la rate limit de
    OMDb gratis es lenta y no queremos bloquear el ingest.

Sobre upsert: `ContentRow.to_dict()` filtra los `None` antes de mandar el
payload, así que re-correr este script NO sobrescribe scores OMDb que ya
estén poblados (vienen como `None` en `ContentRow` y quedan fuera del
payload). El UPSERT solo toca columnas que el script realmente puebla.

Uso:
    python ingest.py                              # full run (PLATFORMS × COUNTRIES)
    python ingest.py --limit 10                   # smoke test
    python ingest.py --platforms netflix,max      # subset
    python ingest.py --genre-sweep                # broad catalog (genre × decade)
    python ingest.py --tmdb-ids 78,348            # inject specific IDs
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
from tenacity import retry, stop_after_attempt, wait_exponential, RetryError

# ---------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------

load_dotenv()

TMDB_TOKEN = os.environ["TMDB_TOKEN"]
SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_ROLE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

COUNTRIES = [c.strip() for c in os.environ.get("INGEST_COUNTRIES", "US,MX,ES,SE").split(",")]
LANGS = [l.strip() for l in os.environ.get("INGEST_LANGS", "en,es,sv").split(",")]
PAGES_PER_PROVIDER = int(os.environ.get("INGEST_PAGES_PER_PROVIDER", "3"))

# Plataformas soportadas en Fase 1 (id en DB ↔ tmdb_provider_id).
PLATFORMS = [
    # (db_id, slug, tmdb_provider_id)
    (1, "netflix",      8),
    (2, "max",          1899),
    (3, "disney",       337),
    (4, "prime",        119),
    (5, "appletv",      350),
    (6, "mubi",         11),
    (7, "crunchyroll",  283),
]

# Mapeo país → idioma principal para /details (sinopsis).
LANG_BY_COUNTRY = {"US": "en-US", "MX": "es-MX", "ES": "es-ES", "SE": "sv-SE"}

# TMDB genre IDs — used by --genre-sweep to discover titles without platform filter.
TMDB_GENRES_MOVIE = {
    28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy",
    80: "Crime", 99: "Documentary", 18: "Drama", 10751: "Family",
    14: "Fantasy", 36: "History", 27: "Horror", 10402: "Music",
    9648: "Mystery", 10749: "Romance", 878: "Sci-Fi",
    53: "Thriller", 10752: "War", 37: "Western",
}
TMDB_GENRES_TV = {
    10759: "Action & Adventure", 16: "Animation", 35: "Comedy",
    80: "Crime", 99: "Documentary", 18: "Drama", 10751: "Family",
    10762: "Kids", 9648: "Mystery", 10763: "News", 10764: "Reality",
    10765: "Sci-Fi & Fantasy", 10766: "Soap", 10767: "Talk",
    10768: "War & Politics", 37: "Western",
}

# Year-decade buckets for genre sweep — maximises unique discoveries.
GENRE_SWEEP_DECADES = [
    (2020, 2026),
    (2010, 2019),
    (2000, 2009),
    (1980, 1999),
]

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
    # ISO 639-1 from TMDB (`ja`, `en`, `ko`, …). Used to filter anime
    # (`ja` + Animation) and other language-specific clusters.
    original_language: str | None = None
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
    director: str | None = None
    cast_list: list[str] = field(default_factory=list)
    # OMDb-sourced scores. Populated by the separate `omdb_backfill.py`
    # script — this ingest leaves them as None, and `to_dict()` filters
    # None out so the UPSERT never overwrites existing OMDb data.
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


def tmdb_discover_genre(genre_id: int, page: int, media_type: str = "movie",
                        year_gte: int | None = None, year_lte: int | None = None) -> list[dict]:
    """Discover by genre WITHOUT platform filter — for broad catalog sweeps."""
    url = f"{TMDB_BASE}/discover/{media_type}"
    params: dict = {
        "language": "en-US",
        "sort_by": "popularity.desc",
        "with_genres": genre_id,
        "vote_count.gte": 50,        # skip ultra-obscure titles
        "page": page,
    }
    date_field = "primary_release_date" if media_type == "movie" else "first_air_date"
    if year_gte:
        params[f"{date_field}.gte"] = f"{year_gte}-01-01"
    if year_lte:
        params[f"{date_field}.lte"] = f"{year_lte}-12-31"
    data = http_get(url, headers=TMDB_HEADERS, params=params)
    return data.get("results", [])


def tmdb_details(tmdb_id: int, media_type: str, lang: str) -> dict:
    url = f"{TMDB_BASE}/{media_type}/{tmdb_id}"
    params = {"language": lang, "append_to_response": "external_ids"}
    return http_get(url, headers=TMDB_HEADERS, params=params)


def tmdb_credits(tmdb_id: int, media_type: str) -> tuple[str | None, list[str]]:
    """Fetch director + top-billed cast from TMDB credits endpoint."""
    url = f"{TMDB_BASE}/{media_type}/{tmdb_id}/credits"
    try:
        data = http_get(url, headers=TMDB_HEADERS)
    except requests.HTTPError as e:
        log.warning("TMDB credits failed for %s/%s: %s", media_type, tmdb_id, e)
        return None, []

    # Director: first person with job == "Director" in crew
    director = None
    for person in data.get("crew", []):
        if person.get("job") == "Director":
            director = person.get("name")
            break
    # For TV: use "created by" from details if no director found
    if not director and media_type == "tv":
        for person in data.get("crew", []):
            if person.get("job") in ("Executive Producer", "Creator"):
                director = person.get("name")
                break

    # Cast: top 6 billed actors
    cast = [
        person["name"]
        for person in (data.get("cast", []) or [])[:6]
        if person.get("name")
    ]

    return director, cast


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
        original_language=det_en.get("original_language"),
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

    # Director & cast from credits endpoint.
    director, cast = tmdb_credits(tmdb_id, media_type)
    row.director = director
    row.cast_list = cast

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
                    source="tmdb",
                ))
    return rows


# ---------------------------------------------------------------------
# OMDb / RapidAPI
# ---------------------------------------------------------------------
# OMDb enrichment lives in `omdb_backfill.py` (separate batched job, ~1000/day
# due to free-tier rate limits). RapidAPI streaming-availability was retired
# in Fase 4.2 — TMDB watch providers covers US/MX/ES/SE adequately and avoids
# the extra cost + dependency. The columns are still in `ContentRow` so OMDb
# backfill can update them; they just stay None during regular ingest.


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

def run(
    limit: int | None,
    platforms_filter: set[str] | None,
    tmdb_ids: list[tuple[int, str]] | None = None,
    genre_sweep: bool = False,
    genre_sweep_pages: int = 5,
) -> None:
    sb = supabase_client()

    discovered: set[tuple[int, str]] = set()  # (tmdb_id, media_type)

    # Manual injection — bypass discover entirely.
    if tmdb_ids:
        discovered = set(tmdb_ids)
        log.info("Manual inject: %d titles", len(discovered))
    else:
        # ── Phase 1: platform × country discover (existing) ──────────
        for db_id, slug, tmdb_pid in PLATFORMS:
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

        log.info("Phase 1 (platform×country): %d unique titles", len(discovered))

        # ── Phase 2: genre × decade sweep (broad catalog) ────────────
        if genre_sweep:
            before = len(discovered)
            for genre_map, media_type in [(TMDB_GENRES_MOVIE, "movie"), (TMDB_GENRES_TV, "tv")]:
                for genre_id, genre_name in genre_map.items():
                    for year_gte, year_lte in GENRE_SWEEP_DECADES:
                        for page in range(1, genre_sweep_pages + 1):
                            try:
                                results = tmdb_discover_genre(
                                    genre_id, page, media_type,
                                    year_gte=year_gte, year_lte=year_lte,
                                )
                            except (requests.HTTPError, RetryError, Exception) as e:
                                log.warning("Genre sweep %s/%s %d-%d p%d: %s",
                                            genre_name, media_type, year_gte, year_lte, page, e)
                                time.sleep(1)  # back off a bit after error
                                break  # skip remaining pages for this combo

                            if not results:
                                break  # no more pages

                            for r in results:
                                discovered.add((r["id"], media_type))

                            if limit and len(discovered) >= limit:
                                break
                            time.sleep(0.2)  # cortesía
                        if limit and len(discovered) >= limit:
                            break
                    if limit and len(discovered) >= limit:
                        break
                    log.info("Genre sweep: %s/%s done → %d total",
                             genre_name, media_type, len(discovered))
                if limit and len(discovered) >= limit:
                    break

            log.info("Phase 2 (genre sweep): +%d new → %d total",
                     len(discovered) - before, len(discovered))

        if limit:
            discovered = set(list(discovered)[:limit])

    log.info("Discovered %d unique titles", len(discovered))

    content_rows: list[ContentRow] = []
    avail_rows: list[AvailabilityRow] = []

    total = len(discovered)
    errors = 0
    for idx, (tmdb_id, media_type) in enumerate(discovered, 1):
        try:
            row = build_content_from_tmdb(tmdb_id, media_type)
        except (RetryError, Exception) as e:
            log.warning("TMDB details failed for %s/%d: %s", media_type, tmdb_id, e)
            errors += 1
            time.sleep(0.5)
            continue
        if row is None:
            continue

        content_rows.append(row)

        try:
            avail_rows.extend(tmdb_availability_rows(tmdb_id, media_type))
        except (RetryError, Exception) as e:
            log.warning("TMDB providers failed for %d: %s", tmdb_id, e)

        if idx % 200 == 0:
            log.info("Enrichment progress: %d/%d (errors: %d)", idx, total, errors)

        time.sleep(0.15)

    # Deduplicate by tmdb_id (same title can appear as movie + tv).
    seen_ids: dict[int, ContentRow] = {}
    for r in content_rows:
        seen_ids[r.tmdb_id] = r  # last write wins
    content_rows = list(seen_ids.values())

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
    p = argparse.ArgumentParser(
        description="TMDB-only content ingest. OMDb scores are populated separately by omdb_backfill.py.",
    )
    p.add_argument("--limit", type=int, default=None, help="Máximo de títulos a procesar (testing)")
    p.add_argument("--platforms", type=str, default=None, help="Comma-separated slugs (netflix,max,...)")
    p.add_argument("--genre-sweep", action="store_true",
                   help="Discover titles by genre×decade (no platform filter). "
                        "Reaches 5k+ unique titles.")
    p.add_argument("--genre-sweep-pages", type=int, default=5,
                   help="Pages per genre×decade×media_type combo (default 5 → ~100 titles each)")
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
        run(
            limit=args.limit,
            platforms_filter=platforms_filter,
            tmdb_ids=tmdb_ids,
            genre_sweep=args.genre_sweep,
            genre_sweep_pages=args.genre_sweep_pages,
        )
    except KeyboardInterrupt:
        log.warning("Interrupted")
        sys.exit(130)


if __name__ == "__main__":
    main()
