-- Build 16 — bilingual quick takes.
--
-- Problem: quick_takes only has a plain `body` column, so a Spanish
-- quick take stays Spanish even when the reader's UI is English
-- (reported by Vivi after Amaru posted "hola, me gustó el encapuchado"
-- and it still showed in Spanish with the app switched to English).
--
-- Fix: mirror the pattern already in place for creator_takes —
-- `body_en` + `body_es` + `original_language`. The Flutter client
-- writes the source-language column on insert and fires the new
-- `translate-quick-take` Edge Function to backfill the other side
-- via DeepL. The `QuickTake` model exposes `localizedBody(locale)`
-- with the same fallback chain used by `CreatorTake`.
--
-- Backfill strategy: every quick take in the DB today was authored
-- in Spanish by Vivi or Amaru during testing. We copy `body` into
-- `body_es` and mark `original_language = 'es'`. The translation
-- pipeline will fill in `body_en` lazily — either by an admin retry
-- or the next time someone edits.

alter table public.quick_takes
  add column if not exists body_en  text,
  add column if not exists body_es  text,
  add column if not exists original_language text
      check (original_language in ('en','es'));

comment on column public.quick_takes.body_en is
  'English rendering. Either authored or DeepL-translated. NULL until translated.';
comment on column public.quick_takes.body_es is
  'Spanish rendering. Either authored or DeepL-translated. NULL until translated.';
comment on column public.quick_takes.original_language is
  'Source language chosen at compose time (''en'' | ''es''). Authoritative source for translate-quick-take.';

-- Backfill: assume existing takes are Spanish (they are — Vivi + Amaru).
update public.quick_takes
   set body_es = coalesce(body_es, body),
       original_language = coalesce(original_language, 'es')
 where body_es is null
    or original_language is null;
