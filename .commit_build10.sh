#!/bin/bash
set -e
cd "$(dirname "$0")"
rm -f .git/HEAD.lock .git/index.lock
rm -f .git/objects/*/tmp_obj_*

git add -A
git commit -m "fix: Build 10 — Cold start loop, session leak, long quiz→vault, follow counter

Five post-Build-8 bugs found via TestFlight.

- Cold start login loop (bug #5): Splash CTA always went to /auth even
  when Supabase had restored a session. Router now redirects signed-in
  users to /home (or /onboarding if quiz incomplete) when they land on
  /splash.

- Long Quiz loved ❤️ never reached the Vault (bug #2): completeLongQuiz
  stored lovedIds in QuizAnswers but didn't surface them anywhere the
  user could see. Now also adds each lovedId to vault as 'loved' and
  sets rating to 5★ — idempotent.

- Session leak across sign-out/sign-in (bugs #6, #8): quickTakesByContent
  and quickTakesTodayCount are FutureProvider.family — they cached 'my
  vote' state from the previous user. main.dart auth listener now calls
  ref.invalidate on both families on signedIn AND signedOut.

- Follow counter stuck (bug #3): new migration 2026-04-13_follow_counter_fix.sql.
  Migrates user_follows.creator_id text -> uuid (TRUNCATE first since
  follows are cheap pre-launch), adds FK, creates trg_follower_count
  SECURITY DEFINER trigger to bump creators.followers_count on INSERT/
  DELETE, backfills current counts. User runs this once via SQL Editor.

- OMDb backfill: fixed NOT NULL violation (upsert -> individual UPDATEs)
  and wrong pending-rows filter (imdb_score IS NULL -> data_sources
  NOT CONTAINS 'omdb') to avoid re-querying titles OMDb doesn't know.

- iOS build bumped 8 -> 10.

Pending (not in this build):
- Premium IAP on TestFlight needs exact error to diagnose.
- Remoty anime intent.
- SharedPreferences user-scoped keys (deeper refactor).

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"

git push origin main
