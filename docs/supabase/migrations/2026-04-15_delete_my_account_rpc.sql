-- Build 16 — Apple App Store Guideline 5.1.1(v) compliance.
-- Users must be able to initiate permanent account deletion from within
-- the app. Every user-owned table already cascades from auth.users on
-- delete, so a single DELETE on auth.users wipes profile, creators,
-- takes, votes, follows, blocks, reports, ratings, vault, quiz, etc.
--
-- Client cannot call auth.admin APIs directly — service role is required.
-- Exposing this as a SECURITY DEFINER RPC keeps the privileged delete
-- server-side while still scoping it to the authenticated caller.
--
-- NOTE: Sign in with Apple refresh-token revocation (also required by
-- 5.1.1(v) when Apple SSO is used) is a follow-up task. It needs an
-- edge function with Apple service credentials to call Apple's
-- /auth/revoke endpoint. Tracked as Build 17 work.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  -- Cascade does the rest (profiles, creators, creator_takes, quick_takes,
  -- quick_take_votes, user_follows, user_blocks (both directions),
  -- content_reports, user_ratings, user_vault, user_loved_quiz, plus
  -- auth.identities / sessions / etc).
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

comment on function public.delete_my_account() is
  'Build 16 — Apple UGC compliance. Permanently deletes the calling user and all their data via ON DELETE CASCADE. Authenticated users only.';
