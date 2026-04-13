-- =============================================================
-- Follow counter fix — standalone SQL to run in Supabase SQL Editor.
-- Handles the user_follows.creator_id text → uuid migration that
-- blocked the previous attempt, then creates the counter trigger,
-- then backfills followers_count from existing rows.
-- Safe to re-run (idempotent).
-- =============================================================

-- 1. Migrate user_follows.creator_id from text to uuid (if needed).
--    We TRUNCATE before the ALTER because any rows with invalid uuid
--    text would block the type change. Follows are cheap to rebuild
--    (users just re-follow creators) and this is still pre-launch.
DO $$
DECLARE
  col_type text;
BEGIN
  SELECT data_type INTO col_type
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'user_follows'
    AND column_name = 'creator_id';

  IF col_type = 'text' THEN
    RAISE NOTICE 'Migrating user_follows.creator_id text -> uuid';
    TRUNCATE user_follows;
    ALTER TABLE user_follows
      ALTER COLUMN creator_id TYPE uuid USING creator_id::uuid;
    ALTER TABLE user_follows
      ADD CONSTRAINT user_follows_creator_id_fkey
      FOREIGN KEY (creator_id) REFERENCES creators(id) ON DELETE CASCADE;
  ELSE
    RAISE NOTICE 'user_follows.creator_id already %, skipping migration', col_type;
  END IF;
END $$;

-- 2. Follower counter trigger function (SECURITY DEFINER bypasses RLS).
CREATE OR REPLACE FUNCTION update_follower_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE creators SET followers_count = followers_count + 1
    WHERE id = NEW.creator_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE creators SET followers_count = GREATEST(followers_count - 1, 0)
    WHERE id = OLD.creator_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_follower_count ON user_follows;
CREATE TRIGGER trg_follower_count
  AFTER INSERT OR DELETE ON user_follows
  FOR EACH ROW EXECUTE FUNCTION update_follower_count();

-- 3. Backfill current followers_count from existing rows.
UPDATE creators c
SET followers_count = (
  SELECT COUNT(*) FROM user_follows uf WHERE uf.creator_id = c.id
);
