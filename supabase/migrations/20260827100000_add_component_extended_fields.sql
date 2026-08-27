-- Migration: Add extended fields to components table and update RPC functions
-- Preserves all existing component and user records seamlessly.

-- 1. Add new columns to public.components
ALTER TABLE public.components ADD COLUMN IF NOT EXISTS manufacturer TEXT NOT NULL DEFAULT '';
ALTER TABLE public.components ADD COLUMN IF NOT EXISTS vendor TEXT NOT NULL DEFAULT '';
ALTER TABLE public.components ADD COLUMN IF NOT EXISTS specification TEXT NOT NULL DEFAULT '';
ALTER TABLE public.components ADD COLUMN IF NOT EXISTS package TEXT NOT NULL DEFAULT '';

-- 2. Create search indexes on new fields
CREATE INDEX IF NOT EXISTS idx_components_manufacturer ON public.components (lower(manufacturer));
CREATE INDEX IF NOT EXISTS idx_components_vendor ON public.components (lower(vendor));
CREATE INDEX IF NOT EXISTS idx_components_package ON public.components (lower(package));

-- 3. Update search components function
CREATE OR REPLACE FUNCTION public.hpt_search_components(_session_token TEXT, _query TEXT DEFAULT '', _limit INTEGER DEFAULT 50)
RETURNS TABLE(
  id UUID,
  component_name TEXT,
  part_number TEXT,
  quantity INTEGER,
  cupboard_number TEXT,
  manufacturer TEXT,
  vendor TEXT,
  specification TEXT,
  package TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  created_by UUID,
  created_by_name TEXT,
  is_demo BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user RECORD;
  v_term TEXT;
  v_limit INTEGER;
BEGIN
  SELECT * INTO v_user FROM public.hpt_require_session(_session_token, false) LIMIT 1;
  v_term := trim(coalesce(_query, ''));
  v_limit := least(greatest(coalesce(_limit, 50), 1), 200);

  RETURN QUERY
  SELECT c.id, c.component_name, c.part_number, c.quantity, c.cupboard_number,
         coalesce(c.manufacturer, '') AS manufacturer,
         coalesce(c.vendor, '') AS vendor,
         coalesce(c.specification, '') AS specification,
         coalesce(c.package, '') AS package,
         c.created_at, c.updated_at, c.created_by, u.name AS created_by_name, c.is_demo
  FROM public.components c
  LEFT JOIN public.app_users u ON u.id = c.created_by
  WHERE v_term = ''
     OR c.component_name ILIKE '%' || v_term || '%'
     OR c.part_number ILIKE '%' || v_term || '%'
     OR c.manufacturer ILIKE '%' || v_term || '%'
     OR c.vendor ILIKE '%' || v_term || '%'
     OR c.specification ILIKE '%' || v_term || '%'
     OR c.package ILIKE '%' || v_term || '%'
  ORDER BY c.component_name ASC
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_search_components(TEXT, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hpt_search_components(TEXT, TEXT, INTEGER) TO anon, authenticated;

-- 4. Update count components function
CREATE OR REPLACE FUNCTION public.hpt_count_components(_session_token TEXT, _query TEXT DEFAULT '')
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user RECORD;
  v_term TEXT;
  v_total INTEGER;
BEGIN
  SELECT * INTO v_user FROM public.hpt_require_session(_session_token, false) LIMIT 1;
  v_term := trim(coalesce(_query, ''));

  SELECT count(*)::INTEGER INTO v_total
  FROM public.components c
  WHERE v_term = ''
     OR c.component_name ILIKE '%' || v_term || '%'
     OR c.part_number ILIKE '%' || v_term || '%'
     OR c.manufacturer ILIKE '%' || v_term || '%'
     OR c.vendor ILIKE '%' || v_term || '%'
     OR c.specification ILIKE '%' || v_term || '%'
     OR c.package ILIKE '%' || v_term || '%';

  RETURN coalesce(v_total, 0);
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_count_components(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hpt_count_components(TEXT, TEXT) TO anon, authenticated;

-- 5. Update create component function
CREATE OR REPLACE FUNCTION public.hpt_create_component(
  _session_token TEXT,
  _component_name TEXT,
  _part_number TEXT,
  _quantity INTEGER,
  _cupboard_number TEXT,
  _manufacturer TEXT DEFAULT '',
  _vendor TEXT DEFAULT '',
  _specification TEXT DEFAULT '',
  _package TEXT DEFAULT ''
)
RETURNS TABLE(
  id UUID,
  component_name TEXT,
  part_number TEXT,
  quantity INTEGER,
  cupboard_number TEXT,
  manufacturer TEXT,
  vendor TEXT,
  specification TEXT,
  package TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  created_by UUID,
  created_by_name TEXT,
  is_demo BOOLEAN
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user RECORD;
BEGIN
  SELECT * INTO v_user FROM public.hpt_require_session(_session_token, false) LIMIT 1;

  IF trim(coalesce(_component_name, '')) = '' OR trim(coalesce(_part_number, '')) = '' OR trim(coalesce(_cupboard_number, '')) = '' THEN
    RAISE EXCEPTION 'Component name, part number, and cupboard number are required.';
  END IF;

  IF _quantity IS NULL OR _quantity < 0 THEN
    RAISE EXCEPTION 'Quantity cannot be negative.';
  END IF;

  RETURN QUERY
  WITH inserted AS (
    INSERT INTO public.components (
      component_name, part_number, quantity, cupboard_number,
      manufacturer, vendor, specification, package, created_by
    )
    VALUES (
      trim(_component_name), trim(_part_number), _quantity, trim(_cupboard_number),
      coalesce(trim(_manufacturer), ''), coalesce(trim(_vendor), ''), coalesce(trim(_specification), ''), coalesce(trim(_package), ''),
      v_user.uid
    )
    RETURNING *
  )
  SELECT c.id, c.component_name, c.part_number, c.quantity, c.cupboard_number,
         c.manufacturer, c.vendor, c.specification, c.package,
         c.created_at, c.updated_at, c.created_by, v_user.name::TEXT AS created_by_name, c.is_demo
  FROM inserted c;
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_create_component(TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hpt_create_component(TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;

-- 6. Update update component function (allow authenticated users, not only admins)
CREATE OR REPLACE FUNCTION public.hpt_update_component(
  _session_token TEXT,
  _id UUID,
  _component_name TEXT,
  _part_number TEXT,
  _quantity INTEGER,
  _cupboard_number TEXT,
  _manufacturer TEXT DEFAULT '',
  _vendor TEXT DEFAULT '',
  _specification TEXT DEFAULT '',
  _package TEXT DEFAULT ''
)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user RECORD;
  v_count INTEGER;
BEGIN
  -- Authenticated user check (employee or admin)
  SELECT * INTO v_user FROM public.hpt_require_session(_session_token, false) LIMIT 1;

  IF trim(coalesce(_component_name, '')) = '' OR trim(coalesce(_part_number, '')) = '' OR trim(coalesce(_cupboard_number, '')) = '' THEN
    RAISE EXCEPTION 'Component name, part number, and cupboard number are required.';
  END IF;

  IF _quantity IS NULL OR _quantity < 0 THEN
    RAISE EXCEPTION 'Quantity cannot be negative.';
  END IF;

  UPDATE public.components
  SET component_name = trim(_component_name),
      part_number = trim(_part_number),
      quantity = _quantity,
      cupboard_number = trim(_cupboard_number),
      manufacturer = coalesce(trim(_manufacturer), ''),
      vendor = coalesce(trim(_vendor), ''),
      specification = coalesce(trim(_specification), ''),
      package = coalesce(trim(_package), '')
  WHERE components.id = _id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count = 0 THEN
    RAISE EXCEPTION 'Component not found.';
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_update_component(TEXT, UUID, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hpt_update_component(TEXT, UUID, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;

-- 7. Update dashboard stats function
CREATE OR REPLACE FUNCTION public.hpt_dashboard_stats(_session_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user RECORD;
  v_total_users INTEGER;
  v_total_components INTEGER;
  v_total_quantity INTEGER;
  v_recent JSONB;
BEGIN
  SELECT * INTO v_user FROM public.hpt_require_session(_session_token, true) LIMIT 1;

  SELECT count(*)::INTEGER INTO v_total_users FROM public.app_users WHERE role = 'user';
  SELECT count(*)::INTEGER INTO v_total_components FROM public.components;
  SELECT coalesce(sum(quantity), 0)::INTEGER INTO v_total_quantity FROM public.components;

  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'id', c.id,
      'component_name', c.component_name,
      'part_number', c.part_number,
      'quantity', c.quantity,
      'cupboard_number', c.cupboard_number,
      'manufacturer', coalesce(c.manufacturer, ''),
      'vendor', coalesce(c.vendor, ''),
      'specification', coalesce(c.specification, ''),
      'package', coalesce(c.package, ''),
      'created_at', c.created_at,
      'updated_at', c.updated_at,
      'created_by', c.created_by,
      'created_by_name', u.name,
      'is_demo', c.is_demo
    ) ORDER BY c.created_at DESC
  ), '[]'::jsonb)
  INTO v_recent
  FROM (
    SELECT * FROM public.components ORDER BY created_at DESC LIMIT 5
  ) c
  LEFT JOIN public.app_users u ON u.id = c.created_by;

  RETURN jsonb_build_object(
    'totalUsers', coalesce(v_total_users, 0),
    'totalComponents', coalesce(v_total_components, 0),
    'totalQuantity', coalesce(v_total_quantity, 0),
    'recent', v_recent
  );
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_dashboard_stats(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hpt_dashboard_stats(TEXT) TO anon, authenticated;
