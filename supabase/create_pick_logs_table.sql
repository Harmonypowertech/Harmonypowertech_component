-- Run this in your Supabase SQL Editor (Project ID: tqfifjxhuzahisyahnzl)
-- Table to store pick / issue transactions of components with reasons

CREATE TABLE IF NOT EXISTS public.component_pick_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    component_id UUID REFERENCES public.components(id) ON DELETE SET NULL,
    component_name TEXT NOT NULL,
    part_number TEXT NOT NULL,
    cupboard_number TEXT DEFAULT '',
    quantity_taken INTEGER NOT NULL CHECK (quantity_taken > 0),
    previous_quantity INTEGER NOT NULL DEFAULT 0,
    remaining_quantity INTEGER NOT NULL DEFAULT 0,
    reason TEXT NOT NULL,
    taken_by UUID REFERENCES public.app_users(id) ON DELETE SET NULL,
    taken_by_name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS & grants
ALTER TABLE public.component_pick_logs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    DROP POLICY IF EXISTS "component_pick_logs_all" ON public.component_pick_logs;
    CREATE POLICY "component_pick_logs_all" ON public.component_pick_logs FOR ALL TO public USING (true) WITH CHECK (true);
END $$;

GRANT ALL ON TABLE public.component_pick_logs TO anon, authenticated, service_role, postgres;

CREATE INDEX IF NOT EXISTS idx_pick_logs_created_at ON public.component_pick_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pick_logs_component_id ON public.component_pick_logs (component_id);
