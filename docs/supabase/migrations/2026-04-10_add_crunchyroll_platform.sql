-- =============================================================
-- Fase 1.1 — Add Crunchyroll as 7th platform
-- Run in Supabase SQL Editor (Dashboard → SQL).
-- =============================================================

-- Crunchyroll — anime/animation streaming. Watchmode ID = 283.
INSERT INTO platforms (name, slug, watchmode_id, tmdb_provider_id)
VALUES ('Crunchyroll', 'crunchyroll', 283, 283)
ON CONFLICT (slug) DO NOTHING;

-- Verify
SELECT id, name, slug, watchmode_id FROM platforms ORDER BY id;
