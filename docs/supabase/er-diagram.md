# The Remote — Entity Relationship Diagram (Fase 0)

Scope: user-owned data only. Content catalog (titles, creators) lives in mock
data until Fase 1. Every table has RLS enabled; a user can only touch their
own rows.

```mermaid
erDiagram
    auth_users ||--|| profiles : "1:1 on signup"
    auth_users ||--o{ user_ratings : "owns"
    auth_users ||--o{ user_vault : "owns"
    auth_users ||--o{ user_follows : "owns"
    auth_users ||--o{ user_loved_quiz : "owns"

    auth_users {
        uuid id PK
        text email
        bool is_anonymous
        timestamptz created_at
    }

    profiles {
        uuid id PK_FK "= auth.users.id"
        text alias UK "3-24 chars, [a-zA-Z0-9_]"
        text avatar_key "null | default:N | file:/path"
        text country "ISO 3166-1 alpha-2"
        text ui_language "en | es | null"
        text content_language
        text tier "free | pro"
        text quiz_completion "none | fast | long"
        bool is_guest
        timestamptz created_at
        timestamptz updated_at
    }

    user_ratings {
        uuid user_id PK_FK
        text content_id PK "mock ID → TMDB ID in Fase 1"
        smallint stars "1-5"
        timestamptz created_at
        timestamptz updated_at
    }

    user_vault {
        uuid user_id PK_FK
        text content_id PK
        text bucket "watchlist | not_for_me"
        timestamptz created_at
    }

    user_follows {
        uuid user_id PK_FK
        text creator_id PK
        timestamptz created_at
    }

    user_loved_quiz {
        uuid user_id PK_FK
        text content_id PK "from Long Quiz double-tap"
        timestamptz created_at
    }
```

## Design notes

**Why `(user_id, content_id)` composite PKs instead of surrogate `id` bigints?**
These tables are *sets* from the user's point of view — a user either has
rated a title or hasn't, and there's exactly one rating per (user, title).
Composite PK enforces that invariant at the DB level without needing a
unique constraint on top of a surrogate, and gives us free index coverage
for the hot lookup (`where user_id = $1`).

**Why `content_id text` and not a foreign key to a content table?**
Fase 0 ships before the catalog exists on Supabase. The catalog lives in
`MockContent` on the client. When Fase 1 lands TMDB ingest, we'll add a
`content` table, add a `content_id_tmdb bigint` column to these tables,
backfill via a mock→TMDB mapping, then either drop `content_id text` or
keep both during a transition window. The extra migration is cheaper than
blocking Fase 0 on catalog work.

**Why no `loved` bucket in `user_vault`?**
Per the 2026-04-08 semantic split: **Loved = 5-star ratings** (derived via
a view or client join). Storing it as a separate bucket would create two
sources of truth that could drift. The only "loved" signal we persist is
`user_loved_quiz` — that's a different beast (historic taste from the
onboarding quiz, not a current rating).

**Why is `profiles.alias` unique but nullable?**
Guest users (anonymous auth) don't have an alias yet. When they upgrade to
a real account or set one from Settings, we enforce uniqueness. The CHECK
constraint (`char_length between 3 and 24`) only applies when non-null.

**What about the avatar PHOTO uploads (`file:/...`)?**
For Fase 0, uploaded photos stay **local to the device**. The `avatar_key`
column syncs the *choice* (initials / default:N / file:/some/path), but if
a user picks "default:3" on their phone and logs in on another device, the
default avatar appears. Uploaded photos don't follow them until we wire
Supabase Storage in a later phase — that requires an upload pipeline,
signed URLs, and image optimization that isn't in scope right now.

## Auth providers (Fase 0)

- **Apple Sign In** (required by App Store since we'll also ship Google)
- **Google Sign In**
- **Magic Link** (email, no password) — avoids the reset-password flow entirely
- **Anonymous** (guest mode) — lets users try the app without committing,
  and upgrade to a real account later without losing their vault/ratings
  (Supabase has a built-in `linkIdentity` flow for this exact case)

## Row-Level Security

Every user table has RLS enabled and 3-4 policies (select/insert/update/delete)
that all use the same predicate: `auth.uid() = user_id` (or `= id` for
profiles). This means:

- A logged-out client **cannot** read or write anything.
- A logged-in user can only see their own rows, ever.
- The `service_role` key bypasses RLS but must **never** ship in the Flutter
  client — it's reserved for server-side scripts (ingest jobs, admin tools).
```
