-- Build 16 — Apple App Store Guideline 1.2 (UGC) compliance.
-- EULA / Community Guidelines acceptance. Apple requires users to
-- affirmatively accept the guidelines before publishing user-generated
-- content. We gate the first time the user attempts to publish ANY take
-- (quick take or creator take) on this timestamp being non-null.
--
-- Nullable on purpose — existing users from Build ≤15 keep playing
-- consuming the app without interruption; they'll only see the modal
-- the first time they try to publish.

alter table public.profiles
  add column if not exists community_guidelines_accepted_at timestamptz;

comment on column public.profiles.community_guidelines_accepted_at is
  'Build 16 — UGC acceptance timestamp. NULL until user taps Accept on the Community Guidelines sheet before publishing their first take.';
