-- Add director and cast fields to content table
-- These will be populated from TMDB credits API.

ALTER TABLE public.content
  ADD COLUMN IF NOT EXISTS director text,
  ADD COLUMN IF NOT EXISTS cast_list text[];   -- top 5-8 actors

COMMENT ON COLUMN public.content.director IS 'Primary director name from TMDB credits';
COMMENT ON COLUMN public.content.cast_list IS 'Top billed cast names from TMDB credits (array)';

-- Index for search by director
CREATE INDEX IF NOT EXISTS idx_content_director
  ON public.content (director);
