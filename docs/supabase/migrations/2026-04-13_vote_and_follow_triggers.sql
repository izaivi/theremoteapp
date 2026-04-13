-- =============================================================
-- Vote counter triggers + Follower counter triggers
-- Fixes: vote counts stay at 0 (RLS blocks direct UPDATE),
--        follower_count never increments.
-- Run in Supabase SQL Editor (Dashboard → SQL).
-- =============================================================

-- =============================================================
-- 1. QUICK TAKE VOTE COUNTERS
--    Trigger on quick_take_votes INSERT/DELETE/UPDATE to keep
--    quick_takes.thumbs_up / thumbs_down in sync automatically.
-- =============================================================

CREATE OR REPLACE FUNCTION update_quick_take_vote_counts()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER          -- bypasses RLS so counters always update
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.vote = 1 THEN
      UPDATE quick_takes SET thumbs_up = thumbs_up + 1 WHERE id = NEW.quick_take_id;
    ELSE
      UPDATE quick_takes SET thumbs_down = thumbs_down + 1 WHERE id = NEW.quick_take_id;
    END IF;
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.vote = 1 THEN
      UPDATE quick_takes SET thumbs_up = GREATEST(thumbs_up - 1, 0) WHERE id = OLD.quick_take_id;
    ELSE
      UPDATE quick_takes SET thumbs_down = GREATEST(thumbs_down - 1, 0) WHERE id = OLD.quick_take_id;
    END IF;
    RETURN OLD;

  ELSIF TG_OP = 'UPDATE' THEN
    -- Vote direction changed (e.g. thumbs_up → thumbs_down)
    IF OLD.vote = 1 THEN
      UPDATE quick_takes SET thumbs_up = GREATEST(thumbs_up - 1, 0) WHERE id = OLD.quick_take_id;
    ELSE
      UPDATE quick_takes SET thumbs_down = GREATEST(thumbs_down - 1, 0) WHERE id = OLD.quick_take_id;
    END IF;
    IF NEW.vote = 1 THEN
      UPDATE quick_takes SET thumbs_up = thumbs_up + 1 WHERE id = NEW.quick_take_id;
    ELSE
      UPDATE quick_takes SET thumbs_down = thumbs_down + 1 WHERE id = NEW.quick_take_id;
    END IF;
    RETURN NEW;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_quick_take_vote_counts ON quick_take_votes;
CREATE TRIGGER trg_quick_take_vote_counts
  AFTER INSERT OR UPDATE OR DELETE ON quick_take_votes
  FOR EACH ROW EXECUTE FUNCTION update_quick_take_vote_counts();


-- =============================================================
-- 2. FOLLOWER COUNT TRIGGER
--    Trigger on user_follows INSERT/DELETE to keep
--    creators.followers_count in sync automatically.
-- =============================================================

-- Ensure user_follows table exists (may already be there)
CREATE TABLE IF NOT EXISTS user_follows (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  creator_id  uuid NOT NULL REFERENCES creators(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, creator_id)
);

CREATE INDEX IF NOT EXISTS idx_user_follows_creator ON user_follows(creator_id);
CREATE INDEX IF NOT EXISTS idx_user_follows_user    ON user_follows(user_id);

-- RLS for user_follows
ALTER TABLE user_follows ENABLE ROW LEVEL SECURITY;

-- Read: everyone can see follows
CREATE POLICY IF NOT EXISTS "follows_read" ON user_follows
  FOR SELECT TO authenticated, anon USING (true);

-- Insert: only your own follows
CREATE POLICY IF NOT EXISTS "follows_insert" ON user_follows
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

-- Delete: only your own follows
CREATE POLICY IF NOT EXISTS "follows_delete" ON user_follows
  FOR DELETE TO authenticated USING (user_id = auth.uid());


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


-- =============================================================
-- 3. Fix current follower counts from existing data
-- =============================================================
UPDATE creators c
SET followers_count = (
  SELECT COUNT(*) FROM user_follows uf WHERE uf.creator_id = c.id
);

-- =============================================================
-- 4. Fix current vote counts from existing data
-- =============================================================
UPDATE quick_takes qt
SET
  thumbs_up = COALESCE((
    SELECT COUNT(*) FROM quick_take_votes v
    WHERE v.quick_take_id = qt.id AND v.vote = 1
  ), 0),
  thumbs_down = COALESCE((
    SELECT COUNT(*) FROM quick_take_votes v
    WHERE v.quick_take_id = qt.id AND v.vote = -1
  ), 0);
