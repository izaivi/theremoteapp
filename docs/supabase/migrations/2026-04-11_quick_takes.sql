-- =============================================================
-- Quick Takes — user reactions (separate from Creator Takes)
-- Free users: 1 per day. Premium: unlimited.
-- Run in Supabase SQL Editor (Dashboard → SQL).
-- =============================================================

-- 1. Quick takes table
CREATE TABLE IF NOT EXISTS quick_takes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content_id  bigint NOT NULL,
  body        text NOT NULL CHECK (char_length(body) <= 250),
  thumbs_up   int NOT NULL DEFAULT 0,
  thumbs_down int NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_quick_takes_content ON quick_takes(content_id);
CREATE INDEX idx_quick_takes_user    ON quick_takes(user_id);

-- 2. Votes table (one vote per user per quick take)
CREATE TABLE IF NOT EXISTS quick_take_votes (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quick_take_id  uuid NOT NULL REFERENCES quick_takes(id) ON DELETE CASCADE,
  user_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  vote           smallint NOT NULL CHECK (vote IN (1, -1)),
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE(quick_take_id, user_id)
);

CREATE INDEX idx_quick_take_votes_take ON quick_take_votes(quick_take_id);

-- 3. RLS
ALTER TABLE quick_takes ENABLE ROW LEVEL SECURITY;
ALTER TABLE quick_take_votes ENABLE ROW LEVEL SECURITY;

-- Everyone can read quick takes and votes
CREATE POLICY "qt_read" ON quick_takes FOR SELECT TO authenticated, anon USING (true);
CREATE POLICY "qtv_read" ON quick_take_votes FOR SELECT TO authenticated, anon USING (true);

-- Authenticated users can insert their own quick takes
CREATE POLICY "qt_insert" ON quick_takes FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Users can update only their own quick takes
CREATE POLICY "qt_update" ON quick_takes FOR UPDATE TO authenticated
  USING (user_id = auth.uid());

-- Users can delete only their own quick takes
CREATE POLICY "qt_delete" ON quick_takes FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- Authenticated users can insert their own votes
CREATE POLICY "qtv_insert" ON quick_take_votes FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Users can update their own votes (change thumb direction)
CREATE POLICY "qtv_update" ON quick_take_votes FOR UPDATE TO authenticated
  USING (user_id = auth.uid());

-- Users can delete their own votes (un-vote)
CREATE POLICY "qtv_delete" ON quick_take_votes FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- 4. Clean up: remove any 'quick_take' verdict creator takes
--    (these were the old conflated ones)
DELETE FROM creator_takes WHERE verdict = 'quick_take';
