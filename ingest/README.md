# The Remote — Ingest

Script batch de ingesta de contenido para The Remote. Corre server-side (iMac secundaria vía N8N cron) y llena las tablas `content` y `content_availability` en Supabase. Los clientes Flutter **nunca** llaman a TMDB/OMDb/Watchmode/RapidAPI — solo leen de Supabase.

## Arquitectura

```
TMDB (backbone) ─┐
OMDb (scores)    ├─→ ingest.py ─→ Supabase (service_role) ─→ Flutter app
Watchmode (US/MX/SE) │
RapidAPI (fallback ES) ┘
```

- **TMDB**: catálogo + metadata + watch providers. Gratis, sin límite práctico.
- **OMDb**: IMDb / Rotten Tomatoes / Metacritic scores. 1,000 req/día gratis.
- **Watchmode**: deep links + precios. Free tier 1,000 req/mes, 3 países (US, MX, SE).
- **RapidAPI streaming-availability**: fallback para ES (Watchmode no cubre en free tier).

Países Fase 1: **US, MX, ES, SE**. Idiomas de sinopsis: **en, es, sv**.

## Setup

```bash
cd ingest
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # editar con las keys reales
```

## Uso

```bash
# Full run (todas las plataformas, todos los países)
python ingest.py

# Test rápido con pocos títulos
python ingest.py --limit 10

# Solo algunas plataformas
python ingest.py --platforms netflix,max
```

## Qué hace

1. **Discover**: para cada (plataforma × país × página) pide a TMDB el top de películas y series por popularidad en ese proveedor.
2. **Details**: para cada título único, pide `/details` en EN, ES y SV para construir la sinopsis trilingüe + metadata base.
3. **OMDb enrichment**: con el `imdb_id` del título, pide scores (IMDb / RT / Metacritic).
4. **Watch providers**: pide `/watch/providers` a TMDB y guarda las disponibilidades por país/plataforma/monetization en `content_availability` (source='tmdb').
5. **Watchmode**: para US/MX/SE, enriquece con deep links + precios (source='watchmode').
6. **RapidAPI**: para ES, intenta enriquecer con `streaming-availability` (source='rapidapi').
7. **Upsert**: primero `content` (en chunks de 200), luego `content_availability` (dedup por PK compuesta).

## Cron con N8N (iMac secundaria)

1. N8N → nuevo workflow → trigger `Cron` → 1x al día a las 08:00.
2. Node `Execute Command`:
   ```bash
   cd /Users/vivi/the-remote-flutter/ingest && \
   /Users/vivi/the-remote-flutter/ingest/.venv/bin/python ingest.py >> /Users/vivi/the-remote-flutter/ingest/logs/ingest.log 2>&1
   ```
3. Activar workflow.

Los logs quedan en `ingest/logs/ingest.log` para debug. Rotarlos cuando crezcan (`logrotate` o manual).

## Rate limits a vigilar

- **OMDb**: 1,000/día. Con ~500 títulos ingestados estás en 500/día → seguro.
- **Watchmode**: 1,000/mes. Cada título = 2 calls (search + sources) → ~500 títulos/mes max. Si es muy justo, limitar la frecuencia del cron (2x por semana en vez de diario) o reducir `INGEST_PAGES_PER_PROVIDER`.
- **RapidAPI**: depende del plan del endpoint; el free suele ser 100/día. Solo se usa para ES.
- **TMDB**: sin límite práctico para este volumen.

## Seguridad

- `.env` está en `.gitignore`. **Nunca** commitear keys.
- `SUPABASE_SERVICE_ROLE_KEY` bypassea RLS — tratarla como password de root de la DB.
- Si sospechas leak, rotar inmediatamente en Supabase Dashboard → Settings → API.

## Troubleshooting

- **`requests.exceptions.HTTPError: 401` en TMDB**: token inválido o mal copiado (debe empezar con `eyJ`).
- **`relation "public.content" does not exist`**: correr primero la migration `docs/supabase/migrations/2026-04-09_fase1_content_ingest.sql`.
- **Watchmode devuelve 0 sources para todo**: título sin matches en su DB. Normal para contenido nicho; el ingest sigue con TMDB.
- **Rows nuevas no aparecen en la app**: los clientes Flutter todavía leen mocks en Fase 1. La integración de repositorios con las tablas reales es trabajo posterior a este ingest.
