-- =============================================================
-- RECOVERY: restore handle_new_user trigger + backfill profiles
--
-- Diagnostic on 2026-04-13: trigger `on_auth_user_created` was
-- missing from auth.users. Symptoms: new sign-ins (Apple, Google,
-- Guest) created auth.users rows but NOT matching profiles rows,
-- making the app appear "logged out" even after successful auth.
-- Vivi's own profile was also missing after a manual NULL cleanup
-- on the profiles table.
--
-- This SQL is idempotent — safe to run multiple times.
-- =============================================================

-- 1. Recreate the trigger function. Same body as schema.sql lines 161-171.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, is_guest)
  VALUES (
    NEW.id,
    COALESCE(NEW.is_anonymous, false)
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END $$;

-- 2. Recreate the trigger. Drop first in case a partial version exists.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 3. Backfill profiles for every existing auth.users row that's missing one.
--    This will recreate Vivi's profile (and any other deleted ones) without
--    overwriting the profiles that survived.
INSERT INTO public.profiles (id, is_guest)
SELECT u.id, COALESCE(u.is_anonymous, false)
FROM auth.users u
LEFT JOIN public.profiles p ON p.id = u.id
WHERE p.id IS NULL;

-- 4. Sanity check — count how many we just backfilled vs how many auth users exist.
DO $$
DECLARE
  n_auth int;
  n_profiles int;
BEGIN
  SELECT COUNT(*) INTO n_auth FROM auth.users;
  SELECT COUNT(*) INTO n_profiles FROM public.profiles;
  RAISE NOTICE 'auth.users count: %', n_auth;
  RAISE NOTICE 'profiles count:   %', n_profiles;
  IF n_auth = n_profiles THEN
    RAISE NOTICE 'OK: every auth user now has a profile row.';
  ELSE
    RAISE WARNING 'Mismatch: % auth users vs % profiles.', n_auth, n_profiles;
  END IF;
END $$;
