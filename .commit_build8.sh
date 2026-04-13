#!/bin/bash
# NOTE: reusable — overwrite the commit message for each build.
set -e
cd "$(dirname "$0")"
rm -f .git/HEAD.lock .git/index.lock
rm -f .git/objects/*/tmp_obj_*

git commit -m "feat: Build 8 — Auth-first onboarding + Quick Takes counter fix + RevenueCat bundle ID

Onboarding flow reordered: Splash → Auth → Quiz → Home (was Splash → Quiz → Auth → Home).
Auth gating added in app_router with currentUserProvider + authStateChangesProvider listener.
Auth screen close button conditional on session existence to prevent escape from mandatory auth.

Quick Takes: vote counter trigger applied via separate SQL (original migration rolled back due
to type mismatch in user_follows section). SECURITY DEFINER function bypasses RLS for cross-user
counter updates. Existing votes recalculated.

RevenueCat bundle ID corrected from com.punkytiger.flixscope (never existed) to
com.punkytigerlabs.theremote — credentials issue resolved on dashboard. Simulator IAP still
errors due to StoreKit cache; validation goes via TestFlight on real device.

Bitácora updated.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"

git push origin main
