"""
OMDb backfill — enriquece SOLO títulos que aún no tienen scores.

Consulta Supabase por filas donde imdb_id existe pero imdb_score es NULL
(es decir, "omdb" no está en data_sources), y les pega a OMDb en batches
de hasta 1,000/día (free tier).

Uso:
    python omdb_backfill.py                # procesa hasta 1,000
    python omdb_backfill.py --limit 500    # procesa hasta 500
    python omdb_backfill.py --dry-run      # solo muestra cuántos faltan
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
import time

import requests
from dotenv import load_dotenv
from supabase import Client, create_client

# ---------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------

load_dotenv()

OMDB_API_KEY = os.environ["OMDB_API_KEY"]
SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_ROLE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

OMDB_DAILY_LIMIT = 1_000
CHUNK_SIZE = 50  # rows per Supabase update batch

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("omdb_backfill")

# ---------------------------------------------------------------------
# Supabase helpers
# ---------------------------------------------------------------------

def get_pending_rows(sb: Client, limit: int) -> list[dict]:
    """
    Devuelve títulos que tienen imdb_id pero aún no han sido consultados a OMDb.
    Usamos data_sources (NOT contains 'omdb') en vez de imdb_score IS NULL,
    porque OMDb a veces devuelve sin scores o con Response=False; en esos casos
    ya marcamos data_sources=['omdb'] para no reintentar y desperdiciar quota.
    """
    resp = (
        sb.table("content")
        .select("tmdb_id, imdb_id, data_sources")
        .not_.is_("imdb_id", "null")            # tiene IMDB ID
        .not_.contains("data_sources", ["omdb"]) # no hemos consultado OMDb aún
        .limit(limit)
        .execute()
    )
    return resp.data or []


def update_scores(sb: Client, updates: list[dict]) -> None:
    """
    Update existing content rows with new scores + data_sources.

    We use UPDATE (not upsert) because every row in `updates` is guaranteed
    to already exist — we literally just SELECTed them from the content
    table. Upsert with on_conflict was failing with NOT NULL violations on
    media_type because PostgreSQL evaluates NOT NULL during the INSERT
    phase, before the ON CONFLICT DO UPDATE clause kicks in. Since we
    don't include media_type/title/etc. in the payload (scores-only),
    the INSERT attempt always fails even though we intend to update.
    """
    if not updates:
        return
    for u in updates:
        tmdb_id = u.get("tmdb_id")
        if tmdb_id is None:
            continue
        payload = {k: v for k, v in u.items() if k != "tmdb_id"}
        sb.table("content").update(payload).eq("tmdb_id", tmdb_id).execute()

# ---------------------------------------------------------------------
# OMDb
# ---------------------------------------------------------------------

def fetch_omdb(imdb_id: str) -> dict | None:
    """Llama a OMDb y devuelve el dict de scores, o None si falla."""
    try:
        r = requests.get(
            "https://www.omdbapi.com/",
            params={"i": imdb_id, "apikey": OMDB_API_KEY},
            timeout=10,
        )
        r.raise_for_status()
        data = r.json()
    except (requests.RequestException, ValueError) as e:
        log.warning("OMDb error for %s: %s", imdb_id, e)
        return None

    if data.get("Response") != "True":
        return None
    return data


def parse_scores(data: dict) -> dict:
    """Extrae imdb_score, rt_score, metacritic_score del response de OMDb."""
    scores: dict = {}

    imdb = data.get("imdbRating")
    if imdb and imdb != "N/A":
        try:
            scores["imdb_score"] = float(imdb)
        except ValueError:
            pass

    for r in data.get("Ratings", []) or []:
        src = r.get("Source", "")
        val = r.get("Value", "")
        if src == "Rotten Tomatoes" and val.endswith("%"):
            try:
                scores["rt_score"] = int(val.rstrip("%"))
            except ValueError:
                pass
        elif src == "Metacritic" and "/" in val:
            try:
                scores["metacritic_score"] = int(val.split("/")[0])
            except ValueError:
                pass

    return scores

# ---------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------

def count_pending(sb: Client) -> int:
    """
    Real count of pending rows, bypassing the Supabase REST 1,000-row cap.
    Uses HEAD + count=exact — no data transfer, just the total.
    """
    resp = (
        sb.table("content")
        .select("tmdb_id", count="exact", head=True)
        .not_.is_("imdb_id", "null")
        .not_.contains("data_sources", ["omdb"])
        .execute()
    )
    return resp.count or 0


def run(limit: int, dry_run: bool = False) -> None:
    sb = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

    if dry_run:
        total = count_pending(sb)
        log.info("Títulos pendientes de OMDb (total real): %d", total)
        log.info("A este ritmo (%d/día), tomaría ~%d días limpiar el backlog.",
                 OMDB_DAILY_LIMIT,
                 (total + OMDB_DAILY_LIMIT - 1) // OMDB_DAILY_LIMIT)
        log.info("--dry-run activo, no se hacen llamadas a OMDb.")
        return

    pending = get_pending_rows(sb, limit)
    total_pending = len(pending)

    log.info("Títulos a procesar ahora: %d (limit solicitado: %d)", total_pending, limit)

    if total_pending == 0:
        log.info("¡Todo el catálogo ya tiene scores de OMDb!")
        return

    enriched = 0
    skipped = 0
    failed = 0
    batch: list[dict] = []

    for i, row in enumerate(pending):
        tmdb_id = row["tmdb_id"]
        imdb_id = row["imdb_id"]
        data_sources = row.get("data_sources") or []

        data = fetch_omdb(imdb_id)
        if data is None:
            failed += 1
            # Aún así marcamos "omdb" en data_sources para no reintentar
            # títulos que OMDb no conoce (evita loops infinitos)
            if "omdb" not in data_sources:
                data_sources.append("omdb")
                batch.append({
                    "tmdb_id": tmdb_id,
                    "data_sources": data_sources,
                })
            continue

        scores = parse_scores(data)
        if "omdb" not in data_sources:
            data_sources.append("omdb")

        update = {"tmdb_id": tmdb_id, "data_sources": data_sources, **scores}
        batch.append(update)

        if scores:
            enriched += 1
        else:
            skipped += 1

        # Flush batch cada CHUNK_SIZE
        if len(batch) >= CHUNK_SIZE:
            update_scores(sb, batch)
            log.info("  → upserted %d rows (%d/%d)", len(batch), i + 1, total_pending)
            batch = []

        # Rate limit: OMDb free = 1,000/day, pero no hay rate/sec doc.
        # Ser conservador: ~3 req/sec
        time.sleep(0.35)

    # Flush remaining
    if batch:
        update_scores(sb, batch)

    log.info(
        "Done! enriched=%d  no_scores=%d  failed=%d  total=%d",
        enriched, skipped, failed, total_pending,
    )


if __name__ == "__main__":
    p = argparse.ArgumentParser(description="OMDb backfill for titles missing scores")
    p.add_argument("--limit", type=int, default=OMDB_DAILY_LIMIT,
                    help=f"Max titles to process (default: {OMDB_DAILY_LIMIT})")
    p.add_argument("--dry-run", action="store_true",
                    help="Solo muestra cuántos faltan, sin llamar a OMDb")
    args = p.parse_args()
    run(limit=args.limit, dry_run=args.dry_run)
