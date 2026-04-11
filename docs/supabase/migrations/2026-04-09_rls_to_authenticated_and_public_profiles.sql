-- ============================================================================
-- Migration: 2026-04-09 — Checkpoint de seguridad pre-Fase 1
-- ============================================================================
-- Objetivos:
--  1. Agregar `TO authenticated` explícito a las 13 policies de las 5 tablas
--     (profiles, user_ratings, user_vault, user_follows, user_loved_quiz).
--     Esto cierra los 5 WARN del Security Advisor sobre `auth_allow_anonymous_sign_ins`.
--     NOTA: Los guests siguen funcionando porque son `auth.users` con
--     `is_anonymous=true` bajo el rol `authenticated`. Solo quedan fuera los
--     callers sin JWT (rol `anon`), que es justamente lo que queremos.
--
--  2. Reemplazar la policy permisiva `profiles_select_public_alias`
--     (`USING (true)`) por una vista `public_profiles` que expone SOLO
--     `id, alias, avatar_key`. El check de unicidad de alias consulta la
--     vista. Las columnas sensibles (country, language, tier, created_at)
--     quedan owner-only.
--
-- Aplicar en orden. Es idempotente: se puede correr varias veces.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- PARTE 1 — Drop policies existentes y recrear con TO authenticated
-- ----------------------------------------------------------------------------

-- ---- profiles ----
drop policy if exists "profiles_select_own" on public.profiles;
drop policy if exists "profiles_insert_own" on public.profiles;
drop policy if exists "profiles_update_own" on public.profiles;
drop policy if exists "profiles_select_public_alias" on public.profiles;  -- policy permisiva vieja

create policy "profiles_select_own"
  on public.profiles for select
  to authenticated
  using (auth.uid() = id);

create policy "profiles_insert_own"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);


-- ---- user_ratings ----
drop policy if exists "ratings_select_own" on public.user_ratings;
drop policy if exists "ratings_insert_own" on public.user_ratings;
drop policy if exists "ratings_update_own" on public.user_ratings;
drop policy if exists "ratings_delete_own" on public.user_ratings;

create policy "ratings_select_own"
  on public.user_ratings for select
  to authenticated
  using (auth.uid() = user_id);

create policy "ratings_insert_own"
  on public.user_ratings for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "ratings_update_own"
  on public.user_ratings for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "ratings_delete_own"
  on public.user_ratings for delete
  to authenticated
  using (auth.uid() = user_id);


-- ---- user_vault ----
drop policy if exists "vault_select_own" on public.user_vault;
drop policy if exists "vault_insert_own" on public.user_vault;
drop policy if exists "vault_update_own" on public.user_vault;
drop policy if exists "vault_delete_own" on public.user_vault;

create policy "vault_select_own"
  on public.user_vault for select
  to authenticated
  using (auth.uid() = user_id);

create policy "vault_insert_own"
  on public.user_vault for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "vault_update_own"
  on public.user_vault for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "vault_delete_own"
  on public.user_vault for delete
  to authenticated
  using (auth.uid() = user_id);


-- ---- user_follows ----
drop policy if exists "follows_select_own" on public.user_follows;
drop policy if exists "follows_insert_own" on public.user_follows;
drop policy if exists "follows_delete_own" on public.user_follows;

create policy "follows_select_own"
  on public.user_follows for select
  to authenticated
  using (auth.uid() = user_id);

create policy "follows_insert_own"
  on public.user_follows for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "follows_delete_own"
  on public.user_follows for delete
  to authenticated
  using (auth.uid() = user_id);


-- ---- user_loved_quiz ----
drop policy if exists "loved_quiz_select_own" on public.user_loved_quiz;
drop policy if exists "loved_quiz_insert_own" on public.user_loved_quiz;
drop policy if exists "loved_quiz_delete_own" on public.user_loved_quiz;

create policy "loved_quiz_select_own"
  on public.user_loved_quiz for select
  to authenticated
  using (auth.uid() = user_id);

create policy "loved_quiz_insert_own"
  on public.user_loved_quiz for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "loved_quiz_delete_own"
  on public.user_loved_quiz for delete
  to authenticated
  using (auth.uid() = user_id);


-- ----------------------------------------------------------------------------
-- PARTE 2 — Vista public_profiles (para lookup de alias y futuros @mentions)
-- ----------------------------------------------------------------------------
-- La vista expone SOLO id/alias/avatar_key. Como no tiene RLS propia, hereda
-- los permisos del caller; pero al ser `security_invoker=true` (default en
-- Postgres 15+) y las columnas filtradas, cualquier authenticated puede leer
-- estos campos públicos sin ver country/language/tier.
--
-- La policy `profiles_select_own` de la tabla base sigue limitando los
-- SELECT directos a `profiles` a las filas del propio user — por eso la vista
-- necesita `security_definer` para poder exponer filas de OTROS users
-- (limitado a las 3 columnas no sensibles).

drop view if exists public.public_profiles;

create view public.public_profiles
  with (security_invoker = false)  -- definer: corre con privilegios del owner
  as
  select
    id,
    alias,
    avatar_key
  from public.profiles
  where alias is not null;

-- Revocar accesos por defecto y dar solo SELECT a authenticated
revoke all on public.public_profiles from public;
revoke all on public.public_profiles from anon;
grant select on public.public_profiles to authenticated;

comment on view public.public_profiles is
  'Lookup público de alias y avatares. Usado por el check de unicidad de alias y (futuro) @mentions. Expone solo id/alias/avatar_key — country/language/tier permanecen owner-only vía RLS en public.profiles.';


-- ============================================================================
-- Verificación post-aplicación
-- ============================================================================
-- Después de correr esto, en el SQL Editor de Supabase ejecutá:
--
--   select tablename, policyname, roles
--     from pg_policies
--    where schemaname = 'public'
--    order by tablename, policyname;
--
-- Debe mostrar `{authenticated}` en la columna `roles` para las 13 policies.
-- `profiles_select_public_alias` NO debe aparecer.
--
-- Y para verificar la vista:
--
--   select * from public.public_profiles limit 5;
--
-- Debe devolver filas con solo las 3 columnas.
-- ============================================================================
