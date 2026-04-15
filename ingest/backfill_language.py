"""
Flixscope — original_language backfill (TMDB-only)

Por qué:
  La columna `content.original_language` se agregó en Fase 4.2 para poder
  filtrar anime (Animation + ja), K-drama (ko), Bollywood (hi), etc.
  Las ~6,700 filas que ya estaban en el catálogo no la tienen. Este
  script las rellena llamando TMDB `/movie|/tv/{id}` y haciendo UPDATE
  sólo de esa columna (no toca scores ni nada más).

Tamaño esperado:
  - ~6,700 filas pendientes
  - ~3 requests/seg con sleep cortés
  - ~35-45 min total (single-threaded, sin paralelismo para no enojar a TMDB)

Uso:
    python backfill_language.py                # full backfill
    python backfill_language.py --limit 100    # smoke test
    python backfill_language.py --batch 200    # chunk size para SELECT (default 500)

No depende de OMDb ni RapidAPI. Idempotente: re-correr sólo afecta filas
que sigan con `original_language IS NULL`.
"""

from __future__ import annotations

import argparse
import logging
import sys
import time

import requests
from tenacity import RetryError

from ingest import (
    TMDB_BASE,
    TMDB_HEADERS,
    http_get,
    supabase_client,
)

log = logging.getLogger("backfill_language")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)


def fetch_pending(sb, batch: int) -> list[dict]:
    """Pull a batch of rows missing original_language.
    `content` PK is `tmdb_id` (no surrogate `id`). Always fetch the first
    N with NULL — after we update them, the next call returns the next N.
    """
    res = (
        sb.table("content")
        .select("tmdb_id, media_type, title")
        .is_("original_language", "null")
        .order("tmdb_id")
        .limit(batch)
        .execute()
    )
    return res.data or []


def fetch_lang_from_tmdb(tmdb_id: int, media_type: str) -> str | None:
    """Hit TMDB details and return the original_language code (or None)."""
    url = f"{TMDB_BASE}/{media_type}/{tmdb_id}"
    try:
        data = http_get(url, headers=TMDB_HEADERS, params={"language": "en-US"})
    except (requests.HTTPError, RetryError, Exception) as e:
        log.warning("TMDB %s/%s failed: %s", media_type, tmdb_id, e)
        return None
    return data.get("original_language")


def update_language(sb, tmdb_id: int, lang: str) -> None:
    sb.table("content").update({"original_language": lang}).eq("tmdb_id", tmdb_id).execute()


def mark_unknown(sb, tmdb_id: int) -> None:
    """TMDB didn't return a language code — stamp 'xx' sentinel so we
    don't keep retrying the same row on re-runs."""
    sb.table("content").update({"original_language": "xx"}).eq("tmdb_id", tmdb_id).execute()


def run(limit: int | None, batch: int) -> None:
    sb = supabase_client()

    processed = 0
    updated = 0
    stamped_unknown = 0
    errors = 0

    while True:
        rows = fetch_pending(sb, batch=batch)
        if not rows:
            log.info("No more pending rows.")
            break

        log.info("Fetched batch of %d", len(rows))

        batch_touched = 0
        for row in rows:
            if limit and processed >= limit:
                break

            tmdb_id = row["tmdb_id"]
            media_type = row["media_type"]
            title = row.get("title", "?")

            lang = fetch_lang_from_tmdb(tmdb_id, media_type)
            processed += 1

            if not lang:
                # Stamp 'xx' para que la próxima iteración no lo vuelva a
                # seleccionar — evita loop infinito sobre tmdb_ids muertos.
                try:
                    mark_unknown(sb, tmdb_id)
                    stamped_unknown += 1
                    batch_touched += 1
                except Exception as e:  # noqa: BLE001
                    log.warning("mark_unknown failed for tmdb_id=%s (%s): %s", tmdb_id, title, e)
                    errors += 1
                time.sleep(0.3)
                continue

            try:
                update_language(sb, tmdb_id, lang)
                updated += 1
                batch_touched += 1
            except Exception as e:  # noqa: BLE001
                log.warning("Update failed for tmdb_id=%s (%s): %s", tmdb_id, title, e)
                errors += 1

            if processed % 100 == 0:
                log.info("Progress: processed=%d updated=%d unknown=%d errors=%d",
                         processed, updated, stamped_unknown, errors)

            time.sleep(0.25)  # ~4 req/s — TMDB-friendly

        if limit and processed >= limit:
            break

        # Guardrail: si un batch no tocó ninguna fila (ej. todas fallaron
        # sin poder stampear 'xx'), cortamos para no loopear infinito.
        if batch_touched == 0:
            log.warning("Batch didn't advance any row — aborting to avoid infinite loop.")
            break

    log.info("Done. processed=%d updated=%d unknown=%d errors=%d",
             processed, updated, stamped_unknown, errors)


def main() -> None:
    p = argparse.ArgumentParser(
        description="Backfill content.original_language using TMDB. "
                    "Idempotente: solo toca filas con original_language IS NULL.",
    )
    p.add_argument("--limit", type=int, default=None, help="Tope de filas a procesar (smoke test)")
    p.add_argument("--batch", type=int, default=500, help="Tamaño del SELECT por iteración (default 500)")
    args = p.parse_args()

    try:
        run(limit=args.limit, batch=args.batch)
    except KeyboardInterrupt:
        log.warning("Interrupted")
        sys.exit(130)


if __name__ == "__main__":
    main()
