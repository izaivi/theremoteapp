"""
Flixscope — anime ingest (TMDB-only, doble sweep)

Dos fuentes complementarias:

  Phase 1 — Animation + Japonés
    with_genres = 16
    with_original_language = ja
    → Cubre el canon: anime japonés clásico (Studio Ghibli, Shonen Jump,
      slice-of-life, etc.). El AND de TMDB garantiza que peliculas
      japonesas live-action (Kurosawa, Drive My Car, Ringu) NO entran.

  Phase 2 — Catálogo de Crunchyroll
    with_watch_providers = 283 (Crunchyroll)
    with_watch_monetization_types = flatrate
    + watch_region = COUNTRIES (US/MX/ES/SE)
    → Captura lo que Phase 1 deja fuera:
      - Anime co-producido con `original_language!='ja'` (a veces 'en').
      - Donghua chino, aeni coreano que se consume como anime.
      - Anime occidental estilo Castlevania / Arcane.
    Riesgo: algún K-drama suelto en Crunchyroll puede colarse, pero su
    catálogo es 95%+ anime y de cualquier forma esos títulos no dañan
    el catálogo (van a la fila de content como cualquier otra cosa).

Ambas fases se unen, deduplican por tmdb_id, y pasan por el mismo
pipeline (`build_content_from_tmdb` + upserts). UPSERT idempotente:
re-correr no duplica filas y no toca scores OMDb (esos los puebla
`omdb_backfill.py` aparte).

Filtros:
  - `vote_count.gte=20` (Phase 1) — quita OVAs ultra-obscuros sin reseñas.
  - `popularity > 5.0` post-fetch — segunda red contra ruido.

Uso:
    python ingest_anime.py                       # Phase 1 + Phase 2 completo
    python ingest_anime.py --pages 5             # Phase 1 más corto (~200 títulos)
    python ingest_anime.py --crunchyroll-pages 2 # Phase 2 más corto
    python ingest_anime.py --skip-crunchyroll    # solo Phase 1 (estricto Animation+ja)
    python ingest_anime.py --skip-genre-lang     # solo Phase 2
    python ingest_anime.py --limit 50            # smoke test (combina ambas)
    python ingest_anime.py --media tv            # solo series

OMDb scores se rellenan después con `omdb_backfill.py` como siempre.
"""

from __future__ import annotations

import argparse
import logging
import sys
import time

import requests
from tenacity import RetryError

# Reuse pipeline from main ingest — single source of truth.
from ingest import (
    AvailabilityRow,
    ContentRow,
    COUNTRIES,
    TMDB_BASE,
    TMDB_HEADERS,
    build_content_from_tmdb,
    http_get,
    supabase_client,
    tmdb_availability_rows,
    upsert_availability,
    upsert_content,
)

log = logging.getLogger("ingest_anime")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)

# Anime = TMDB Animation genre (id 16) + original_language japanese.
ANIME_GENRE_ID = 16
ANIME_LANG = "ja"
CRUNCHYROLL_PROVIDER_ID = 283
MIN_POPULARITY = 5.0
MIN_VOTE_COUNT = 20


def tmdb_discover_anime(page: int, media_type: str) -> list[dict]:
    """Phase 1: Animation genre + Japanese original language (AND)."""
    url = f"{TMDB_BASE}/discover/{media_type}"
    params = {
        "language": "en-US",
        "sort_by": "popularity.desc",
        "with_genres": ANIME_GENRE_ID,
        "with_original_language": ANIME_LANG,
        "vote_count.gte": MIN_VOTE_COUNT,
        "page": page,
    }
    data = http_get(url, headers=TMDB_HEADERS, params=params)
    return data.get("results", [])


def tmdb_discover_crunchyroll(country: str, page: int, media_type: str) -> list[dict]:
    """Phase 2: titles available on Crunchyroll (flatrate) in `country`."""
    url = f"{TMDB_BASE}/discover/{media_type}"
    params = {
        "language": "en-US",
        "sort_by": "popularity.desc",
        "watch_region": country,
        "with_watch_providers": CRUNCHYROLL_PROVIDER_ID,
        "with_watch_monetization_types": "flatrate",
        "page": page,
    }
    data = http_get(url, headers=TMDB_HEADERS, params=params)
    return data.get("results", [])


def discover_phase1_genre_lang(
    pages: int,
    media_types: list[str],
) -> set[tuple[int, str]]:
    discovered: set[tuple[int, str]] = set()
    for media_type in media_types:
        for page in range(1, pages + 1):
            try:
                results = tmdb_discover_anime(page, media_type)
            except (requests.HTTPError, RetryError, Exception) as e:
                log.warning("Phase1 %s p%d: %s", media_type, page, e)
                time.sleep(1)
                break

            if not results:
                log.info("Phase1: no more results for %s at page %d", media_type, page)
                break

            kept = 0
            for r in results:
                pop = r.get("popularity", 0) or 0
                if pop < MIN_POPULARITY:
                    continue
                discovered.add((r["id"], media_type))
                kept += 1

            log.info("Phase1 (Animation+ja) %s p%d: +%d (kept) / %d (raw) → %d total",
                     media_type, page, kept, len(results), len(discovered))
            time.sleep(0.2)
    return discovered


def discover_phase2_crunchyroll(
    pages: int,
    media_types: list[str],
    countries: list[str],
) -> set[tuple[int, str]]:
    discovered: set[tuple[int, str]] = set()
    for media_type in media_types:
        for country in countries:
            for page in range(1, pages + 1):
                try:
                    results = tmdb_discover_crunchyroll(country, page, media_type)
                except (requests.HTTPError, RetryError, Exception) as e:
                    log.warning("Phase2 Crunchyroll %s/%s p%d: %s",
                                media_type, country, page, e)
                    time.sleep(1)
                    break

                if not results:
                    break

                kept = 0
                for r in results:
                    pop = r.get("popularity", 0) or 0
                    if pop < MIN_POPULARITY:
                        continue
                    discovered.add((r["id"], media_type))
                    kept += 1

                log.info("Phase2 (Crunchyroll) %s/%s p%d: +%d (kept) / %d (raw) → %d total",
                         media_type, country, page, kept, len(results), len(discovered))
                time.sleep(0.2)
    return discovered


def run(
    pages: int,
    media_types: list[str],
    limit: int | None,
    skip_genre_lang: bool = False,
    skip_crunchyroll: bool = False,
    crunchyroll_pages: int = 3,
    countries: list[str] | None = None,
) -> None:
    sb = supabase_client()
    countries = countries or COUNTRIES

    discovered: set[tuple[int, str]] = set()

    if not skip_genre_lang:
        log.info("=== Phase 1: Animation + Japanese ===")
        phase1 = discover_phase1_genre_lang(pages=pages, media_types=media_types)
        log.info("Phase 1 result: %d unique titles", len(phase1))
        discovered |= phase1
    else:
        log.info("Skipping Phase 1 (--skip-genre-lang)")

    if not skip_crunchyroll:
        log.info("=== Phase 2: Crunchyroll catalog ===")
        before = len(discovered)
        phase2 = discover_phase2_crunchyroll(
            pages=crunchyroll_pages,
            media_types=media_types,
            countries=countries,
        )
        log.info("Phase 2 result: %d unique titles (raw)", len(phase2))
        discovered |= phase2
        log.info("Phase 2 contributed %d new titles after dedup", len(discovered) - before)
    else:
        log.info("Skipping Phase 2 (--skip-crunchyroll)")

    if limit:
        discovered = set(list(discovered)[:limit])

    log.info("Discovered %d unique anime titles", len(discovered))

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

        if idx % 100 == 0:
            log.info("Enrichment progress: %d/%d (errors: %d)", idx, total, errors)

        time.sleep(0.15)

    # Dedup: same TMDB id can technically appear once per media_type,
    # but our key is just tmdb_id in DB.
    seen_ids: dict[int, ContentRow] = {}
    for r in content_rows:
        seen_ids[r.tmdb_id] = r
    content_rows = list(seen_ids.values())

    CHUNK = 200
    for i in range(0, len(content_rows), CHUNK):
        upsert_content(sb, content_rows[i:i + CHUNK])
    for i in range(0, len(avail_rows), CHUNK):
        upsert_availability(sb, avail_rows[i:i + CHUNK])

    log.info("Done. anime content=%d availability=%d errors=%d",
             len(content_rows), len(avail_rows), errors)


def main() -> None:
    p = argparse.ArgumentParser(
        description="TMDB anime sweep (Phase 1: Animation+ja, Phase 2: Crunchyroll provider). "
                    "Reuses ingest.py pipeline. OMDb scores stay None — backfill aparte.",
    )
    p.add_argument("--pages", type=int, default=15,
                   help="Phase 1: páginas por media_type (default 15 → ~300 titles c/u)")
    p.add_argument("--crunchyroll-pages", type=int, default=3,
                   help="Phase 2: páginas por country×media_type (default 3 → ~60 titles c/u)")
    p.add_argument("--media", type=str, default="movie,tv",
                   help="Media types: 'movie', 'tv', o 'movie,tv' (default ambos)")
    p.add_argument("--countries", type=str, default=None,
                   help="Phase 2: comma-separated country codes (default: usa COUNTRIES de ingest.py)")
    p.add_argument("--skip-genre-lang", action="store_true",
                   help="Saltar Phase 1 (Animation+ja)")
    p.add_argument("--skip-crunchyroll", action="store_true",
                   help="Saltar Phase 2 (Crunchyroll provider)")
    p.add_argument("--limit", type=int, default=None,
                   help="Tope de títulos a procesar (smoke test, aplica al combinado)")
    args = p.parse_args()

    media_types = [m.strip() for m in args.media.split(",") if m.strip() in ("movie", "tv")]
    if not media_types:
        log.error("--media debe incluir 'movie' y/o 'tv'")
        sys.exit(2)

    if args.skip_genre_lang and args.skip_crunchyroll:
        log.error("No puedes saltar AMBAS phases — no quedaría nada que descubrir.")
        sys.exit(2)

    countries = None
    if args.countries:
        countries = [c.strip().upper() for c in args.countries.split(",") if c.strip()]

    try:
        run(
            pages=args.pages,
            media_types=media_types,
            limit=args.limit,
            skip_genre_lang=args.skip_genre_lang,
            skip_crunchyroll=args.skip_crunchyroll,
            crunchyroll_pages=args.crunchyroll_pages,
            countries=countries,
        )
    except KeyboardInterrupt:
        log.warning("Interrupted")
        sys.exit(130)


if __name__ == "__main__":
    main()
