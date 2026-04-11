-- =============================================================
-- Add edit_count to creator_takes (max 2 edits per take)
-- Run in Supabase SQL Editor (Dashboard → SQL).
-- =============================================================

-- 1. Add edit_count column with CHECK constraint
ALTER TABLE creator_takes
  ADD COLUMN IF NOT EXISTS edit_count smallint NOT NULL DEFAULT 0
  CHECK (edit_count >= 0 AND edit_count <= 2);

-- 2. Allow creators to update their own takes (body + verdict)
--    only if edit_count < 2. The policy already exists for basic
--    update; the app-side enforces the limit.

-- 3. Cleanup: delete the TEST take on The Boys
DELETE FROM creator_takes WHERE body ILIKE '%test%';
