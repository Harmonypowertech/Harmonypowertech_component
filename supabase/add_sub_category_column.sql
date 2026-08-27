-- Migration: Add sub_category column to components table safely
-- Preserves all existing component data completely without disturbance.

ALTER TABLE public.components ADD COLUMN IF NOT EXISTS sub_category TEXT DEFAULT '';

-- Optional index for faster filtering and search by sub_category
CREATE INDEX IF NOT EXISTS idx_components_sub_category ON public.components (lower(sub_category));
