-- =============================================================
-- Fase 1.2 — Creators system (real, Supabase-backed)
-- Run in Supabase SQL Editor (Dashboard → SQL).
-- =============================================================

-- 1. Creators table
CREATE TABLE IF NOT EXISTS creators (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  alias       text NOT NULL UNIQUE,
  bio         text NOT NULL DEFAULT '',
  specialty   text NOT NULL DEFAULT '',
  is_curated  boolean NOT NULL DEFAULT false,
  avatar_url  text,
  followers_count integer NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- 2. Creator takes table
CREATE TABLE IF NOT EXISTS creator_takes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id  uuid NOT NULL REFERENCES creators(id) ON DELETE CASCADE,
  content_id  bigint NOT NULL REFERENCES content(tmdb_id) ON DELETE CASCADE,
  verdict     text NOT NULL CHECK (verdict IN ('worth_it', 'skip_it', 'quick_take')),
  body        text NOT NULL,
  rating      smallint CHECK (rating IS NULL OR (rating >= 1 AND rating <= 5)),
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- 3. Indexes
CREATE INDEX idx_creator_takes_creator ON creator_takes(creator_id);
CREATE INDEX idx_creator_takes_content ON creator_takes(content_id);
CREATE INDEX idx_creators_alias ON creators(alias);

-- 4. RLS
ALTER TABLE creators ENABLE ROW LEVEL SECURITY;
ALTER TABLE creator_takes ENABLE ROW LEVEL SECURITY;

-- Everyone can read creators and takes
CREATE POLICY "creators_read" ON creators FOR SELECT TO authenticated, anon USING (true);
CREATE POLICY "takes_read" ON creator_takes FOR SELECT TO authenticated, anon USING (true);

-- Only the creator themselves can insert/update their own takes
CREATE POLICY "takes_insert_own" ON creator_takes FOR INSERT TO authenticated
  WITH CHECK (
    creator_id IN (SELECT id FROM creators WHERE user_id = auth.uid())
  );

CREATE POLICY "takes_update_own" ON creator_takes FOR UPDATE TO authenticated
  USING (creator_id IN (SELECT id FROM creators WHERE user_id = auth.uid()));

-- =============================================================
-- 5. Seed @izaivi — REPLACE the UUID below with Vivi's auth.users id
-- =============================================================
-- INSERT INTO creators (user_id, alias, bio, specialty, is_curated)
-- VALUES (
--   'PASTE-VIVI-UUID-HERE',
--   '@izaivi',
--   'Founder of Flixscope. I watch everything so you don''t have to. Anime, K-drama, prestige TV, true crime, and comfort rewatches.',
--   'Everything',
--   true
-- );
