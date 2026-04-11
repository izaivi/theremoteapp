-- =============================================================
-- Add DELETE policy for creator_takes (was missing!)
-- Also verify UPDATE policy exists.
-- Run in Supabase SQL Editor (Dashboard → SQL).
-- =============================================================

-- 1. DELETE policy — creators can delete their own takes
CREATE POLICY IF NOT EXISTS "takes_delete_own" ON creator_takes FOR DELETE TO authenticated
  USING (creator_id IN (SELECT id FROM creators WHERE user_id = auth.uid()));

-- 2. Verify user_id is set for @izaivi (Apple account)
-- This query should return 1 row. If it returns 0, the creator profile
-- isn't linked and isOwnProfile detection won't work.
SELECT id, alias, user_id FROM creators WHERE alias = '@izaivi';
