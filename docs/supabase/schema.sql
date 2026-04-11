-- ============================================================================
-- The Remote — Supabase Schema (Fase 0)
-- ============================================================================
-- Scope: user-owned data only. Content catalog (titles, creators) lives in
-- mock data until Fase 1 (TMDB ingest). When that lands, we'll map the
-- mock IDs to TMDB IDs via a migration.
--
-- Design principles:
--   1. Every user table has `user_id uuid references auth.users(id)`.
--   2. Row-Level Security enabled on every table from day 1.
--   3. Policy: a user can only SELECT/INSERT/UPDATE/DELETE their own rows.
--   4. Content IDs are stored as TEXT for now (mock IDs like "dune-part-two").
--      When Fase 1 ships, we'll add a `content_id_tmdb bigint` column and
--      backfill via a deterministic mapping.
--   5. Timestamps use `timestamptz` with server defaults — never trust client.
--   6. Soft foreign keys to auth.users ON DELETE CASCADE so deleting an
--      account wipes all their data automatically (GDPR-friendly).
--
-- Run order: execute this file top to bottom in the Supabase SQL Editor.
-- Safe to re-run: uses IF NOT EXISTS / CREATE OR REPLACE where possible.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. PROFILES — public-facing user info (mirrors local UserProfile)
-- ---------------------------------------------------------------------------
-- The `alias` is the cinéfilo-style handle (@viviroja). Unique, 3–24 chars.
-- The `avatar_key` stores the same 3-encoding string the Flutter app uses:
--   null                → initials
--   "default:1..5"      → bundled asset
--   "file:/abs/path"    → local upload (NOT synced to Supabase; deferred to
--                         Supabase Storage in a later phase — too heavy for
--                         Fase 0. For now, if a user logs in on a second
--                         device, their uploaded photo doesn't follow them;
--                         only the pick of default or initials does.)

create table if not exists public.profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  alias             text unique,
  avatar_key        text,
  country           text,                     -- ISO 3166-1 alpha-2 (e.g. 'MX')
  ui_language       text,                     -- 'en' | 'es' | null=auto
  content_language  text,
  tier              text not null default 'free', -- 'free' | 'pro'
  quiz_completion   text not null default 'none', -- 'none' | 'fast' | 'long'
  is_guest          boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint alias_length check (char_length(alias) between 3 and 24),
  constraint alias_format check (alias ~ '^[a-zA-Z0-9_]+$' or alias is null)
);

comment on table public.profiles is 'User profile — 1:1 with auth.users. Created via trigger on signup.';

-- Auto-bump updated_at on any write.
create or replace function public.tg_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.tg_touch_updated_at();


-- ---------------------------------------------------------------------------
-- 2. USER_RATINGS — 1-5 star ratings (precise taste signal)
-- ---------------------------------------------------------------------------
-- Kept separate from the vault on purpose: rating is a precise scalar that
-- feeds the engine's taste model, while vault buckets are coarse actions.
-- Mirrors the Flutter `RatingsRepository`.

create table if not exists public.user_ratings (
  user_id     uuid not null references auth.users(id) on delete cascade,
  content_id  text not null,
  stars       smallint not null check (stars between 1 and 5),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (user_id, content_id)
);

comment on table public.user_ratings is '1-5 star ratings. Primary taste signal for the engine.';

drop trigger if exists user_ratings_touch_updated_at on public.user_ratings;
create trigger user_ratings_touch_updated_at
  before update on public.user_ratings
  for each row execute function public.tg_touch_updated_at();

create index if not exists idx_user_ratings_user on public.user_ratings(user_id);
create index if not exists idx_user_ratings_content on public.user_ratings(content_id);


-- ---------------------------------------------------------------------------
-- 3. USER_VAULT — watchlist + notForMe (coarse bucket actions)
-- ---------------------------------------------------------------------------
-- Note: "loved" is NOT a bucket here. Loved = 5-star ratings (derived), per
-- the 2026-04-08 semantic split. Buckets are mutually exclusive via a
-- CHECK constraint so a title can't be in watchlist AND notForMe at once.

create table if not exists public.user_vault (
  user_id     uuid not null references auth.users(id) on delete cascade,
  content_id  text not null,
  bucket      text not null check (bucket in ('watchlist', 'not_for_me')),
  created_at  timestamptz not null default now(),
  primary key (user_id, content_id)
);

comment on table public.user_vault is 'Coarse action buckets (watchlist / not_for_me). Mutually exclusive per title.';

create index if not exists idx_user_vault_user_bucket
  on public.user_vault(user_id, bucket);


-- ---------------------------------------------------------------------------
-- 4. USER_FOLLOWS — followed creators
-- ---------------------------------------------------------------------------

create table if not exists public.user_follows (
  user_id     uuid not null references auth.users(id) on delete cascade,
  creator_id  text not null,
  created_at  timestamptz not null default now(),
  primary key (user_id, creator_id)
);

comment on table public.user_follows is 'Creators this user follows.';

create index if not exists idx_user_follows_user on public.user_follows(user_id);
create index if not exists idx_user_follows_creator on public.user_follows(creator_id);


-- ---------------------------------------------------------------------------
-- 5. USER_LOVED_QUIZ — titles flagged as "loved" during the Long Quiz
-- ---------------------------------------------------------------------------
-- Fixes the old conflation where `lovedRecentIds` was merged into
-- `watchedIds` inside `UserProfile.withLongQuiz()`. Now we store them
-- separately so the Loved tab and the engine can distinguish
-- "I loved this in the past" from "I rated this 5 stars recently".

create table if not exists public.user_loved_quiz (
  user_id     uuid not null references auth.users(id) on delete cascade,
  content_id  text not null,
  created_at  timestamptz not null default now(),
  primary key (user_id, content_id)
);

comment on table public.user_loved_quiz is 'Titles the user marked as "loved" during the Long Quiz (double-tap).';

create index if not exists idx_user_loved_quiz_user on public.user_loved_quiz(user_id);


-- ---------------------------------------------------------------------------
-- 6. TRIGGER: auto-create profile row on signup
-- ---------------------------------------------------------------------------
-- When a new user signs up via Supabase Auth (email, Apple, Google, or
-- anonymous guest), we insert a matching row into public.profiles. The
-- alias and avatar stay null until the user sets them from the app.

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, is_guest)
  values (
    new.id,
    coalesce(new.is_anonymous, false)
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ============================================================================
-- ROW-LEVEL SECURITY (RLS)
-- ============================================================================
-- Enable RLS on every table and write policies that restrict access to the
-- row owner. Without these, ANY authenticated user could read ANY other
-- user's ratings, vault, follows. This is not optional.
-- ============================================================================

alter table public.profiles        enable row level security;
alter table public.user_ratings    enable row level security;
alter table public.user_vault      enable row level security;
alter table public.user_follows    enable row level security;
alter table public.user_loved_quiz enable row level security;


-- ---- profiles ----
-- Read: public can read aliases + avatars (for showing @mentions and
-- creator-style lists in the future). Sensitive fields (country, language,
-- tier) are still owner-only. We achieve this by splitting into two policies
-- — but for Fase 0 keeping it simple: only the owner can read their row.
-- We'll relax this when we add public profile pages.

-- Todas las policies tienen `TO authenticated` explícito tras el checkpoint
-- de seguridad pre-Fase 1 (2026-04-09). Los guests siguen funcionando porque
-- son `auth.users` con `is_anonymous=true` bajo el rol `authenticated`.
-- Ver migrations/2026-04-09_rls_to_authenticated_and_public_profiles.sql

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles for select
  to authenticated
  using (auth.uid() = id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);


-- ---- user_ratings ----
drop policy if exists "ratings_select_own" on public.user_ratings;
create policy "ratings_select_own"
  on public.user_ratings for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "ratings_insert_own" on public.user_ratings;
create policy "ratings_insert_own"
  on public.user_ratings for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "ratings_update_own" on public.user_ratings;
create policy "ratings_update_own"
  on public.user_ratings for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "ratings_delete_own" on public.user_ratings;
create policy "ratings_delete_own"
  on public.user_ratings for delete
  to authenticated
  using (auth.uid() = user_id);


-- ---- user_vault ----
drop policy if exists "vault_select_own" on public.user_vault;
create policy "vault_select_own"
  on public.user_vault for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "vault_insert_own" on public.user_vault;
create policy "vault_insert_own"
  on public.user_vault for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "vault_update_own" on public.user_vault;
create policy "vault_update_own"
  on public.user_vault for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "vault_delete_own" on public.user_vault;
create policy "vault_delete_own"
  on public.user_vault for delete
  to authenticated
  using (auth.uid() = user_id);


-- ---- user_follows ----
drop policy if exists "follows_select_own" on public.user_follows;
create policy "follows_select_own"
  on public.user_follows for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "follows_insert_own" on public.user_follows;
create policy "follows_insert_own"
  on public.user_follows for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "follows_delete_own" on public.user_follows;
create policy "follows_delete_own"
  on public.user_follows for delete
  to authenticated
  using (auth.uid() = user_id);


-- ---- user_loved_quiz ----
drop policy if exists "loved_quiz_select_own" on public.user_loved_quiz;
create policy "loved_quiz_select_own"
  on public.user_loved_quiz for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "loved_quiz_insert_own" on public.user_loved_quiz;
create policy "loved_quiz_insert_own"
  on public.user_loved_quiz for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "loved_quiz_delete_own" on public.user_loved_quiz;
create policy "loved_quiz_delete_own"
  on public.user_loved_quiz for delete
  to authenticated
  using (auth.uid() = user_id);


-- ---- Vista public_profiles ----
-- Lookup público de alias (check de unicidad + futuros @mentions).
-- Expone SOLO id/alias/avatar_key. security_definer para poder leer filas
-- de otros users pese a las policies owner-only de la tabla base.
drop view if exists public.public_profiles;
create view public.public_profiles
  with (security_invoker = false)
  as
  select id, alias, avatar_key
  from public.profiles
  where alias is not null;

revoke all on public.public_profiles from public;
revoke all on public.public_profiles from anon;
grant select on public.public_profiles to authenticated;

comment on view public.public_profiles is
  'Lookup público de alias y avatares. Expone solo id/alias/avatar_key.';


-- ============================================================================
-- END Fase 0 schema
-- ============================================================================
-- Next: Fase 1 will add `content` and `creators` tables backed by TMDB
-- ingest, then a migration to map mock text IDs to TMDB bigints.
-- ============================================================================
