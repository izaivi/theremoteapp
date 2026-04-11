-- =====================================================================
-- Fase 1 — Content ingest foundation
-- =====================================================================
-- Crea el catálogo público (platforms, content, content_availability),
-- migra las tablas de user (ratings/vault/loved_quiz) de content_id text
-- a bigint con FK a content(tmdb_id), y habilita RLS read-only para
-- authenticated en las tablas nuevas.
--
-- Notas:
--   * user_follows usa creator_id (no content_id) → NO se toca.
--   * Writes al catálogo solo vía service_role (sin policies de insert/update/delete).
--   * synopsis trilingüe: en / es / sv (Suecia es mercado Fase 1).
--   * watcher_score queda nullable — se calcula en Fase 2.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. platforms (catálogo de plataformas soportadas en Fase 1)
-- ---------------------------------------------------------------------
create table if not exists public.platforms (
  id            smallint primary key,
  slug          text not null unique,
  name          text not null,
  tmdb_provider_id integer not null unique,
  color_hex     text not null,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

insert into public.platforms (id, slug, name, tmdb_provider_id, color_hex) values
  (1, 'netflix',   'Netflix',    8,    '#E50914'),
  (2, 'max',       'Max',        1899, '#002BE7'),
  (3, 'disney',    'Disney+',    337,  '#113CCF'),
  (4, 'prime',     'Prime Video',119,  '#00A8E1'),
  (5, 'appletv',   'Apple TV+',  350,  '#000000'),
  (6, 'mubi',      'MUBI',       11,   '#000000')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 2. content (catálogo maestro, PK = tmdb_id)
-- ---------------------------------------------------------------------
create table if not exists public.content (
  tmdb_id           bigint primary key,
  media_type        text not null check (media_type in ('movie','tv')),
  title             text not null,
  original_title    text,
  release_year      smallint,
  runtime_minutes   integer,
  genres            smallint[] not null default '{}',
  classification    text,
  poster_path       text,
  backdrop_path     text,

  -- Sinopsis multi-idioma (Fase 1: en, es, sv)
  synopsis_en       text,
  synopsis_es       text,
  synopsis_sv       text,

  -- IDs externos
  imdb_id           text,

  -- Scores externos (OMDb / Watchmode / RapidAPI)
  imdb_score        numeric(3,1),
  rt_score          smallint,
  metacritic_score  smallint,

  -- Señales TMDB
  tmdb_popularity   numeric(10,3),
  tmdb_vote_average numeric(3,1),
  tmdb_vote_count   integer,

  -- Watcher Score (Fase 2, nullable por ahora)
  watcher_score     numeric(4,1),
  trend             text,
  hype_level        smallint,
  drop_off_rate     numeric(5,2),
  trust_score       numeric(4,1),

  -- Trazabilidad de fuentes
  data_sources      text[] not null default '{}',

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

drop trigger if exists content_touch_updated_at on public.content;
create trigger content_touch_updated_at
  before update on public.content
  for each row execute function public.tg_touch_updated_at();

create index if not exists content_popularity_idx
  on public.content (tmdb_popularity desc nulls last);
create index if not exists content_watcher_score_idx
  on public.content (watcher_score desc nulls last);
create index if not exists content_media_type_idx
  on public.content (media_type);

-- ---------------------------------------------------------------------
-- 3. content_availability (disponibilidad por país/plataforma/tipo)
-- ---------------------------------------------------------------------
create table if not exists public.content_availability (
  content_id        bigint not null references public.content(tmdb_id) on delete cascade,
  country_code      text not null check (char_length(country_code) = 2),
  platform_id       smallint not null references public.platforms(id) on delete cascade,
  monetization_type text not null check (monetization_type in ('flatrate','free','ads','rent','buy')),
  price_amount      numeric(8,2),
  price_currency    text,
  deep_link         text,
  source            text not null, -- 'tmdb' | 'watchmode' | 'rapidapi'
  last_checked_at   timestamptz not null default now(),
  primary key (content_id, country_code, platform_id, monetization_type)
);

create index if not exists content_avail_country_platform_idx
  on public.content_availability (country_code, platform_id);
create index if not exists content_avail_last_checked_idx
  on public.content_availability (last_checked_at);

-- ---------------------------------------------------------------------
-- 4. Migrar tablas de user: content_id text → bigint con FK
--    (no hay data real en prod → TRUNCATE seguro)
-- ---------------------------------------------------------------------
truncate table public.user_ratings;
truncate table public.user_vault;
truncate table public.user_loved_quiz;

alter table public.user_ratings
  alter column content_id type bigint using null,
  add constraint user_ratings_content_fk
    foreign key (content_id) references public.content(tmdb_id) on delete cascade;

alter table public.user_vault
  alter column content_id type bigint using null,
  add constraint user_vault_content_fk
    foreign key (content_id) references public.content(tmdb_id) on delete cascade;

alter table public.user_loved_quiz
  alter column content_id type bigint using null,
  add constraint user_loved_quiz_content_fk
    foreign key (content_id) references public.content(tmdb_id) on delete cascade;

-- ---------------------------------------------------------------------
-- 5. RLS read-only para authenticated en el catálogo
--    (writes solo vía service_role desde el ingest script)
-- ---------------------------------------------------------------------
alter table public.platforms            enable row level security;
alter table public.content              enable row level security;
alter table public.content_availability enable row level security;

drop policy if exists platforms_select_all on public.platforms;
create policy platforms_select_all
  on public.platforms for select
  to authenticated
  using (true);

drop policy if exists content_select_all on public.content;
create policy content_select_all
  on public.content for select
  to authenticated
  using (true);

drop policy if exists content_availability_select_all on public.content_availability;
create policy content_availability_select_all
  on public.content_availability for select
  to authenticated
  using (true);

grant select on public.platforms            to authenticated;
grant select on public.content              to authenticated;
grant select on public.content_availability to authenticated;

commit;
