-- ====================================================================
-- COMPLETE SETUP & DATA IMPORT SCRIPT FOR DATABASE: tqfifjxhuzahisyahnzl
-- Preserves all schema, triggers, functions, user accounts, and component inventory.
-- ====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- 1. Create Tables
CREATE TABLE IF NOT EXISTS public.app_users (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  user_id TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user','admin')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.components (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  component_name TEXT NOT NULL,
  part_number TEXT NOT NULL,
  quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  cupboard_number TEXT NOT NULL,
  manufacturer TEXT NOT NULL DEFAULT '',
  vendor TEXT NOT NULL DEFAULT '',
  specification TEXT NOT NULL DEFAULT '',
  package TEXT NOT NULL DEFAULT '',
  created_by UUID REFERENCES public.app_users(id) ON DELETE SET NULL,
  is_demo BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.hpt_sessions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES public.app_users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Ensure all extended columns exist on public.components even if table already existed
ALTER TABLE public.components ADD COLUMN IF NOT EXISTS manufacturer TEXT NOT NULL DEFAULT '';
ALTER TABLE public.components ADD COLUMN IF NOT EXISTS vendor TEXT NOT NULL DEFAULT '';
ALTER TABLE public.components ADD COLUMN IF NOT EXISTS specification TEXT NOT NULL DEFAULT '';
ALTER TABLE public.components ADD COLUMN IF NOT EXISTS package TEXT NOT NULL DEFAULT '';

-- 2. Indexes
CREATE INDEX IF NOT EXISTS idx_components_name ON public.components (lower(component_name));
CREATE INDEX IF NOT EXISTS idx_components_part ON public.components (lower(part_number));
CREATE INDEX IF NOT EXISTS idx_components_cupboard ON public.components (lower(cupboard_number));
CREATE INDEX IF NOT EXISTS idx_components_manufacturer ON public.components (lower(manufacturer));
CREATE INDEX IF NOT EXISTS idx_components_vendor ON public.components (lower(vendor));
CREATE INDEX IF NOT EXISTS idx_components_package ON public.components (lower(package));
CREATE INDEX IF NOT EXISTS idx_components_created_at ON public.components (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_app_users_user_id ON public.app_users (lower(user_id));
CREATE INDEX IF NOT EXISTS idx_hpt_sessions_token_hash ON public.hpt_sessions (token_hash);
CREATE INDEX IF NOT EXISTS idx_hpt_sessions_expires_at ON public.hpt_sessions (expires_at);

-- 3. Grants & RLS
GRANT ALL ON public.app_users TO service_role;
GRANT ALL ON public.components TO service_role;
GRANT ALL ON public.hpt_sessions TO service_role;

ALTER TABLE public.app_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.components ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hpt_sessions ENABLE ROW LEVEL SECURITY;

-- 4. Triggers
CREATE OR REPLACE FUNCTION public.hpt_touch_updated_at() RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS trg_app_users_updated ON public.app_users;
CREATE TRIGGER trg_app_users_updated BEFORE UPDATE ON public.app_users
FOR EACH ROW EXECUTE FUNCTION public.hpt_touch_updated_at();

DROP TRIGGER IF EXISTS trg_components_updated ON public.components;
CREATE TRIGGER trg_components_updated BEFORE UPDATE ON public.components
FOR EACH ROW EXECUTE FUNCTION public.hpt_touch_updated_at();

-- 5. Functions & Stored Procedures
CREATE OR REPLACE FUNCTION public.hpt_pbkdf2_sha256(_password TEXT, _salt_hex TEXT, _iterations INTEGER)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_key BYTEA;
  v_salt BYTEA;
  v_u BYTEA;
  v_result BYTEA;
  i INTEGER;
  j INTEGER;
BEGIN
  IF _password IS NULL OR _salt_hex IS NULL OR _iterations IS NULL OR _iterations < 1 THEN
    RETURN '';
  END IF;

  v_key := convert_to(_password, 'UTF8');
  v_salt := decode(_salt_hex, 'hex');
  v_u := hmac(v_salt || decode('00000001', 'hex'), v_key, 'sha256');
  v_result := v_u;

  IF _iterations > 1 THEN
    FOR i IN 2.._iterations LOOP
      v_u := hmac(v_u, v_key, 'sha256');
      FOR j IN 0..(octet_length(v_result) - 1) LOOP
        v_result := set_byte(v_result, j, get_byte(v_result, j) # get_byte(v_u, j));
      END LOOP;
    END LOOP;
  END IF;

  RETURN encode(v_result, 'hex');
EXCEPTION
  WHEN others THEN
    RETURN '';
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_pbkdf2_sha256(TEXT, TEXT, INTEGER) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.hpt_verify_password(_password TEXT, _stored TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_parts TEXT[];
  v_iterations INTEGER;
  v_actual TEXT;
  v_expected TEXT;
BEGIN
  IF _password IS NULL OR _stored IS NULL THEN
    RETURN false;
  END IF;

  v_parts := string_to_array(_stored, '$');
  IF array_length(v_parts, 1) <> 4 OR v_parts[1] <> 'pbkdf2' THEN
    RETURN false;
  END IF;

  v_iterations := v_parts[2]::INTEGER;
  v_expected := v_parts[4];
  v_actual := public.hpt_pbkdf2_sha256(_password, v_parts[3], v_iterations);

  RETURN v_actual = v_expected;
EXCEPTION
  WHEN others THEN
    RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_verify_password(TEXT, TEXT) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.hpt_current_session(_session_token TEXT)
RETURNS TABLE(uid UUID, name TEXT, login_id TEXT, role TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF _session_token IS NULL OR length(_session_token) < 32 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT u.id, u.name, u.user_id, u.role
  FROM public.hpt_sessions s
  JOIN public.app_users u ON u.id = s.user_id
  WHERE s.token_hash = encode(digest(_session_token, 'sha256'), 'hex')
    AND s.expires_at > now()
    AND u.status = 'active'
  LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_current_session(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hpt_current_session(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.hpt_require_session(_session_token TEXT, _require_admin BOOLEAN DEFAULT false)
RETURNS TABLE(uid UUID, name TEXT, login_id TEXT, role TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user RECORD;
BEGIN
  SELECT * INTO v_user FROM public.hpt_current_session(_session_token) LIMIT 1;

  IF v_user.uid IS NULL OR (_require_admin AND v_user.role <> 'admin') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  RETURN QUERY SELECT v_user.uid::UUID, v_user.name::TEXT, v_user.login_id::TEXT, v_user.role::TEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_require_session(TEXT, BOOLEAN) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.hpt_authenticate_user(_login_id TEXT, _password TEXT, _expect_admin BOOLEAN DEFAULT false)
RETURNS TABLE(uid UUID, name TEXT, login_id TEXT, role TEXT, session_token TEXT)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user RECORD;
  v_token TEXT;
BEGIN
  DELETE FROM public.hpt_sessions WHERE expires_at <= now();

  SELECT u.id, u.name, u.user_id, u.password_hash, u.role, u.status
  INTO v_user
  FROM public.app_users u
  WHERE lower(u.user_id) = lower(trim(_login_id))
  LIMIT 1;

  IF v_user.id IS NULL OR v_user.status <> 'active' THEN
    RETURN;
  END IF;

  IF _expect_admin AND v_user.role <> 'admin' THEN
    RETURN;
  END IF;

  IF NOT public.hpt_verify_password(_password, v_user.password_hash) THEN
    RETURN;
  END IF;

  v_token := encode(gen_random_bytes(32), 'hex');

  INSERT INTO public.hpt_sessions (user_id, token_hash, expires_at)
  VALUES (v_user.id, encode(digest(v_token, 'sha256'), 'hex'), now() + interval '12 hours');

  RETURN QUERY SELECT v_user.id::UUID, v_user.name::TEXT, v_user.user_id::TEXT, v_user.role::TEXT, v_token::TEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_authenticate_user(TEXT, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hpt_authenticate_user(TEXT, TEXT, BOOLEAN) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.hpt_logout(_session_token TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF _session_token IS NOT NULL THEN
    DELETE FROM public.hpt_sessions WHERE token_hash = encode(digest(_session_token, 'sha256'), 'hex');
  END IF;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_logout(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hpt_logout(TEXT) TO anon, authenticated;

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

CREATE OR REPLACE FUNCTION public.hpt_delete_component(_session_token TEXT, _id UUID)
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
  SELECT * INTO v_user FROM public.hpt_require_session(_session_token, true) LIMIT 1;

  DELETE FROM public.components WHERE components.id = _id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count = 0 THEN
    RAISE EXCEPTION 'Component not found.';
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_delete_component(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hpt_delete_component(TEXT, UUID) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.hpt_list_users(_session_token TEXT)
RETURNS TABLE(id UUID, name TEXT, user_id TEXT, role TEXT, status TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user RECORD;
BEGIN
  SELECT * INTO v_user FROM public.hpt_require_session(_session_token, true) LIMIT 1;

  RETURN QUERY
  SELECT u.id, u.name, u.user_id, u.role, u.status, u.created_at
  FROM public.app_users u
  ORDER BY u.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_list_users(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hpt_list_users(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.hpt_create_user(_session_token TEXT, _name TEXT, _user_id TEXT, _password_hash TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user RECORD;
BEGIN
  SELECT * INTO v_user FROM public.hpt_require_session(_session_token, true) LIMIT 1;

  IF trim(coalesce(_name, '')) = '' OR trim(coalesce(_user_id, '')) = '' OR coalesce(_password_hash, '') = '' THEN
    RAISE EXCEPTION 'Name, user ID, and password are required.';
  END IF;

  IF EXISTS (SELECT 1 FROM public.app_users u WHERE lower(u.user_id) = lower(trim(_user_id))) THEN
    RAISE EXCEPTION 'That User ID is already taken.';
  END IF;

  INSERT INTO public.app_users (name, user_id, password_hash, role)
  VALUES (trim(_name), trim(_user_id), _password_hash, 'user');

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_create_user(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hpt_create_user(TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.hpt_set_user_status(_session_token TEXT, _id UUID, _status TEXT)
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
  SELECT * INTO v_user FROM public.hpt_require_session(_session_token, true) LIMIT 1;

  IF _status NOT IN ('active', 'inactive') THEN
    RAISE EXCEPTION 'Invalid status.';
  END IF;

  UPDATE public.app_users SET status = _status WHERE app_users.id = _id AND app_users.role = 'user';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count = 0 THEN
    RAISE EXCEPTION 'User not found.';
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_set_user_status(TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hpt_set_user_status(TEXT, UUID, TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.hpt_reset_user_password(_session_token TEXT, _id UUID, _password_hash TEXT)
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
  SELECT * INTO v_user FROM public.hpt_require_session(_session_token, true) LIMIT 1;

  IF coalesce(_password_hash, '') = '' THEN
    RAISE EXCEPTION 'Password is required.';
  END IF;

  UPDATE public.app_users SET password_hash = _password_hash WHERE app_users.id = _id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count = 0 THEN
    RAISE EXCEPTION 'User not found.';
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_reset_user_password(TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hpt_reset_user_password(TEXT, UUID, TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.hpt_delete_user(_session_token TEXT, _id UUID)
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
  SELECT * INTO v_user FROM public.hpt_require_session(_session_token, true) LIMIT 1;

  DELETE FROM public.app_users WHERE app_users.id = _id AND app_users.role = 'user';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count = 0 THEN
    RAISE EXCEPTION 'User not found.';
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_delete_user(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hpt_delete_user(TEXT, UUID) TO anon, authenticated;

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

-- ====================================================================
-- 6. DATA MIGRATION: USERS & COMPONENTS
-- ====================================================================

-- 6.1 Administrator Account
INSERT INTO public.app_users (id, name, user_id, password_hash, role, status)
VALUES (
  '6e611fda-88ff-4651-b92a-7161d953805d',
  'HPT Administrator',
  'hpt_admin',
  'pbkdf2$100000$88f075c7c141d60c7f00016e0acf506d$01e543d0384e68a546d9c86ec346b766ba264a2b6d29b3fd562e7b1e6598dc75',
  'admin',
  'active'
)
ON CONFLICT (user_id) DO NOTHING;

-- 6.2 Employee Accounts
INSERT INTO public.app_users (id, name, user_id, password_hash, role, status, created_at)
VALUES ('d2e6abc1-d9b9-45f2-8d5b-497eb6d5019c', 'Monik Dobariya', 'Hpt_6', 'pbkdf2$100000$88f075c7c141d60c7f00016e0acf506d$01e543d0384e68a546d9c86ec346b766ba264a2b6d29b3fd562e7b1e6598dc75', 'user', 'active', '2026-08-27T05:35:21.918401+00:00')
ON CONFLICT (user_id) DO NOTHING;
INSERT INTO public.app_users (id, name, user_id, password_hash, role, status, created_at)
VALUES ('f1614130-f0cd-4399-b830-ada9c76bc4a0', 'Raj Prasad', 'Hpt_5', 'pbkdf2$100000$88f075c7c141d60c7f00016e0acf506d$01e543d0384e68a546d9c86ec346b766ba264a2b6d29b3fd562e7b1e6598dc75', 'user', 'active', '2026-08-27T05:35:00.006623+00:00')
ON CONFLICT (user_id) DO NOTHING;
INSERT INTO public.app_users (id, name, user_id, password_hash, role, status, created_at)
VALUES ('fb5cfd35-9cbf-4443-ad9b-736464bd17d4', 'Rohit Patadiya', 'Hpt_4', 'pbkdf2$100000$88f075c7c141d60c7f00016e0acf506d$01e543d0384e68a546d9c86ec346b766ba264a2b6d29b3fd562e7b1e6598dc75', 'user', 'active', '2026-08-27T05:34:42.27145+00:00')
ON CONFLICT (user_id) DO NOTHING;
INSERT INTO public.app_users (id, name, user_id, password_hash, role, status, created_at)
VALUES ('ad7b6683-d215-4983-863a-d4e82338aa3b', 'Sohil Pathan', 'Hpt_3', 'pbkdf2$100000$88f075c7c141d60c7f00016e0acf506d$01e543d0384e68a546d9c86ec346b766ba264a2b6d29b3fd562e7b1e6598dc75', 'user', 'active', '2026-08-27T05:34:27.506483+00:00')
ON CONFLICT (user_id) DO NOTHING;
INSERT INTO public.app_users (id, name, user_id, password_hash, role, status, created_at)
VALUES ('969fa117-3ec6-4ced-8542-7ab5da7482a1', 'Krunal Chavda', 'Hpt_2', 'pbkdf2$100000$88f075c7c141d60c7f00016e0acf506d$01e543d0384e68a546d9c86ec346b766ba264a2b6d29b3fd562e7b1e6598dc75', 'user', 'active', '2026-08-27T05:34:11.198932+00:00')
ON CONFLICT (user_id) DO NOTHING;
INSERT INTO public.app_users (id, name, user_id, password_hash, role, status, created_at)
VALUES ('7251bdc0-4580-4868-8049-8c71a590eebe', 'Harshil Vadher', 'hpt_1', 'pbkdf2$100000$88f075c7c141d60c7f00016e0acf506d$01e543d0384e68a546d9c86ec346b766ba264a2b6d29b3fd562e7b1e6598dc75', 'user', 'active', '2026-08-26T11:13:35.1147+00:00')
ON CONFLICT (user_id) DO NOTHING;

-- 6.3 Component Records (122 components)
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('e0cc3de2-0215-402f-9c94-8787e9f5a9c6', '100nf cap', 'hshshsh', 100, 'A2', '', '', '', '', NULL, false, '2026-08-21T17:13:10.890016+00:00', '2026-08-26T11:12:36.745731+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('1dbae478-af2c-46a7-961b-cc83f981ab85', 'Capacitor', '2200uf / 50V', 200, 'A4', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-26T11:28:49.590653+00:00', '2026-08-26T11:28:49.590653+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('c7cf8539-bae0-4f2c-8ddc-0db6c9e81d93', 'Capacitor', '100nf 250vAC', 100, 'A3', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-26T11:14:24.819801+00:00', '2026-08-26T11:14:24.819801+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('d0d60d65-d3ca-4645-b75a-fc0c96a38c46', 'CAPACITOR_0603', '10UF', 100, 'B2.2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:36:04.314894+00:00', '2026-08-27T06:36:04.314894+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('e5fec9ce-122c-4956-8fa4-e2864d511f03', 'CAPACITOR_0603', '10NF', 100, 'B2.2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:38:18.617931+00:00', '2026-08-27T06:38:18.617931+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('564686a0-382c-4f12-8a00-350b01471f93', 'CAPACITOR_0603', '100NF', 200, 'B2.2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:38:03.399463+00:00', '2026-08-27T06:38:03.399463+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('aff4f17b-37c1-4270-9afb-b1253b6891a3', 'CAPACITOR_0603', '220NF', 100, 'B2.2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:37:23.296883+00:00', '2026-08-27T06:37:23.296883+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('b9d911c3-1212-4498-83e7-1a1664e3e0ff', 'CAPACITOR_0603', '1UF', 200, 'B2.2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:37:04.493833+00:00', '2026-08-27T06:37:04.493833+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('6ede7b5c-9b0b-4a93-9ecb-b38e73332536', 'CAPACITOR_0603', '47PF', 100, 'B2.2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:36:35.177776+00:00', '2026-08-27T06:36:35.177776+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('916b6cd8-23a5-4a82-b103-746f0cb3b675', 'CAPACITOR_0603', '100PF', 100, 'B2.2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:36:21.055289+00:00', '2026-08-27T06:36:21.055289+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('134ece5b-e1b0-45f7-b4dd-94a462bb6554', 'CAPACITOR_0805', '2.2UF', 200, 'B2.2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:39:15.936184+00:00', '2026-08-27T06:39:15.936184+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('fdd86920-ffe8-4515-874e-f50898cdb653', 'CAPACITOR_0805', '100NF', 300, 'B2.2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:39:56.030265+00:00', '2026-08-27T06:39:56.030265+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('4b1daebd-1e54-4987-96fb-61e283ee2e96', 'CAPACITOR_0805', '10UF', 300, 'B2.2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:40:25.762259+00:00', '2026-08-27T06:40:25.762259+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('017283ee-bf27-47a9-870f-f8b0c2acae38', 'CAPACITOR_0805', '2.2UF', 100, 'B2.2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:40:40.368331+00:00', '2026-08-27T06:40:40.368331+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('3bf19e3e-c79c-46b0-8545-1cb06d051ede', 'CAPACITOR_THT', '150UF_450V', 50, 'B2.4', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:04:37.235736+00:00', '2026-08-27T07:04:37.235736+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('c812026c-d8e3-4d63-a704-1fbbd73bf612', 'CAPACITOR_THT', '220UF_25V', 250, 'B2.4', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:03:55.427128+00:00', '2026-08-27T07:03:55.427128+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('f3b31bb4-295b-4ae8-ad05-ffdc1e04b659', 'CAPACITOR_THT', '10UF_450V', 150, 'B2.6', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:09:38.332184+00:00', '2026-08-27T07:09:38.332184+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('a9933908-6a63-43af-b935-1b77183099ba', 'CAPACITOR_THT', '470UF_25V', 200, 'B2.5', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:07:12.572669+00:00', '2026-08-27T07:07:12.572669+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('07a4681f-d445-4e5e-83ec-e2b9f680a2f1', 'CAPACITOR_THT', '470UF_40V', 200, 'B2.5', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:06:43.770925+00:00', '2026-08-27T07:06:43.770925+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('52fe9caf-4864-4a35-8320-2c03bf894b7e', 'CAPACITOR_THT', '47UF_63V', 200, 'B2.5', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:06:13.276342+00:00', '2026-08-27T07:06:13.276342+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('c2fb9c41-721c-45a4-9b6a-880e9e235a84', 'CAPACITOR_THT', '2200UF_50V', 50, 'B2.7', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:14:10.741804+00:00', '2026-08-27T07:14:10.741804+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('3e3cb12c-2d43-47a6-9037-04f6b171a81b', 'CAPACITOR_THT', '220UF_250V', 15, 'B2.7', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:13:34.623726+00:00', '2026-08-27T07:13:34.623726+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('874e9f5a-0ce3-4561-a0a3-3f64620b6d9a', 'CAPACITOR_THT', '1000UF_35V', 150, 'B2.7', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:12:38.067248+00:00', '2026-08-27T07:12:38.067248+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('820a4b58-7e30-4660-a78d-bae01e316756', 'CAPACITOR_THT', '10UF_63V', 200, 'B2.6', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:10:39.816143+00:00', '2026-08-27T07:10:39.816143+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('b1f4ad02-04c1-4a65-9051-7306a437d8f1', 'CAPACITOR_THT', '1000UF_50V', 100, 'B2.6', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:09:07.475647+00:00', '2026-08-27T07:09:07.475647+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('b45a8326-aefb-48e9-9ef0-c95feb6da6b2', 'DIODE_BRIGE', 'SGBJ3516', 12, 'B1.4', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:58:56.520703+00:00', '2026-08-27T06:58:56.520703+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('78d9df52-6720-44d4-ad4e-e501659e80c3', 'DIODE_BRIGE', 'W10', 12, 'B1.4', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:59:21.776153+00:00', '2026-08-27T06:59:21.776153+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('06f293eb-e013-4fa9-91ff-165e8a20a96a', 'DIODE_BRIGE', 'GBU4M', 50, 'B1.4', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:02:33.2529+00:00', '2026-08-27T07:02:33.2529+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('8694304c-376f-4164-88b0-8d137ac0f184', 'DIODE_BRIGE', 'KBL10', 100, 'B1.5', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:03:35.603783+00:00', '2026-08-27T07:03:35.603783+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('a8a57cfa-4bd4-4145-9635-3f11847c1ecd', 'DIODE_BRIGE', 'GBU1010', 56, 'STRIP_BOX-3', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:26:25.587963+00:00', '2026-08-27T09:26:25.587963+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('ca99c773-8ca4-4ed6-a81a-3e0f84170aa9', 'DIODE_THT', 'LTTH806SDM', 100, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:03:48.713089+00:00', '2026-08-27T09:03:48.713089+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('2ad31530-9b17-409e-bc96-027aef2979cc', 'DIODE_THT', 'MUR460', 150, 'B2.8', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:16:15.100326+00:00', '2026-08-27T07:16:15.100326+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('a041b53e-0528-4702-8c2a-38533b96da15', 'DIODE_THT', 'P6KE160A', 100, 'B2.8', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:16:45.433243+00:00', '2026-08-27T07:16:45.433243+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('75ecc8af-6a59-4ed7-84a5-a6c720151786', 'DIODE_THT', 'UF4007', 200, 'B2.8', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:17:49.76524+00:00', '2026-08-27T07:17:49.76524+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('3a6f0ab7-34ea-4b00-a91b-421072480f14', 'DIODE_THT', '15V_ZENER_1WATT', 200, 'B2.8', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:18:43.175792+00:00', '2026-08-27T07:18:43.175792+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('3c920363-d5f4-4cc8-a67e-214dc79fcc11', 'DIODE_THT', 'FR107', 50, 'B2.8', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:18:59.020563+00:00', '2026-08-27T07:18:59.020563+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('b82bd159-d7df-4454-a421-257b0212c28a', 'DIODE_THT', 'FR607', 50, 'B2.8', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:19:22.749701+00:00', '2026-08-27T07:19:22.749701+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('85094a2d-9ba5-4f0c-bca3-878cfcffa805', 'DIODE_THT', 'SR5100', 100, 'B2.8', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:20:22.637658+00:00', '2026-08-27T07:20:22.637658+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('e23c664b-439c-4409-ae5c-84e8bdeec7ea', 'DIODE_THT', 'RFRG30120', 23, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T08:58:18.313805+00:00', '2026-08-27T08:58:18.313805+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('7ed41ced-32ec-4b78-9df5-0c34259e6c0d', 'DIODE_THT', 'STTH3012W', 8, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:05:28.728314+00:00', '2026-08-27T09:05:28.728314+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('796fe5bd-4912-487c-9601-97ca60f53f3e', 'DIODE_THT', 'MBR30200', 48, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:06:01.138877+00:00', '2026-08-27T09:06:01.138877+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('adb53056-3bff-4476-989a-f299bcaf8b7e', 'DIODE_THT', 'V60200PG', 27, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:07:26.671177+00:00', '2026-08-27T09:07:26.671177+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('af636091-9303-4ab9-b463-b74d1892c945', 'DIODE_THT', 'STTH10LCD06FP', 30, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:09:53.732164+00:00', '2026-08-27T09:09:53.732164+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('cd648e5d-9af0-4d52-b9a8-8a9202bfb0bf', 'DIODE_THT', 'MUR3060WT', 2, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:12:12.063628+00:00', '2026-08-27T09:12:12.063628+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('1bcd98e7-bbf8-4286-856c-6cb4b05365f8', 'DIODE_THT', 'BYE32E200', 35, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:14:13.320264+00:00', '2026-08-27T09:14:13.320264+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('de604cb6-df33-476b-bb29-8bbb936c99ca', 'DIODE_THT', 'STPS20S100CT', 20, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:17:03.328369+00:00', '2026-08-27T09:17:03.328369+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('dd6a17e5-d212-4503-8e3a-71787f2a7bfe', 'DIODE_THT', 'STPS20S100CT', 320, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:19:24.824663+00:00', '2026-08-27T09:19:24.824663+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('497479a7-640c-47a7-9d2c-7e8e284de07d', 'DIODE_THT', 'MBR20200CT', 271, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:22:27.63925+00:00', '2026-08-27T09:22:27.63925+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('d2ba7c21-8e77-49f1-8924-2ea1c74413cc', 'ELECTROLITIC CAPACITORE', '100uF/450V', 25, 'C2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:21:42.787792+00:00', '2026-08-27T09:21:42.787792+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('aba87753-9639-481f-9d37-cbbfa1757618', 'ELECTROLITIC CAPACITORE', '82uF/450V', 80, 'C2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:22:21.207051+00:00', '2026-08-27T09:22:21.207051+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('b3b2b279-df28-439a-8b48-87dab9e90124', 'ELECTROLITIC CAPACITORE', '2200uf/16V', 300, 'B11.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:22:11.201141+00:00', '2026-08-27T07:22:11.201141+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('83121a31-3645-433a-adf1-331e7569d9ac', 'ELECTROLITIC CAPACITORE', '100uf/160V', 300, 'B11.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:23:26.276968+00:00', '2026-08-27T07:23:26.276968+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('504c5d66-f7cc-449b-84bb-6f281063ac3d', 'ELECTROLITIC CAPACITORE', '330uF/250V', 50, 'C2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:12:44.204473+00:00', '2026-08-27T09:12:44.204473+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('41430899-803a-4ac5-ac4f-ba0a23adbd03', 'ELECTROLITIC CAPACITORE', '22uF/450V', 190, 'C2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:15:58.480248+00:00', '2026-08-27T09:15:58.480248+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('5c3a0444-ed2d-4af6-9843-62b404a99c55', 'ELECTROLITIC CAPACITORE', '220uF/50v', 500, 'B1.3', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:54:11.170561+00:00', '2026-08-27T06:54:11.170561+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('0baaa07f-891b-461c-be73-8030167a9bc2', 'ELECTROLITIC CAPACITORE', '1000uF/35V', 5, 'B1.3', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:54:58.265971+00:00', '2026-08-27T06:54:58.265971+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('4cd402e4-ef6f-4b32-8527-c7600b638e44', 'ELECTROLITIC CAPACITORE', '100uF/50V', 500, 'B1.3', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:55:47.559602+00:00', '2026-08-27T06:55:47.559602+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('6937bca5-d199-40f6-8610-f106d3ea70a6', 'ELECTROLITIC CAPACITORE', '1000UF/16V', 200, 'C2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:15:17.774119+00:00', '2026-08-27T09:15:17.774119+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('9bb12202-dcbe-4d03-a07f-f8c601e71ea9', 'ELECTROLITIC CAPACITORE', '100uF/25V', 100, 'B1.3', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:56:26.08861+00:00', '2026-08-27T06:56:26.08861+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('f65b3c69-d742-4843-801d-042ce72e7b65', 'ELECTROLITIC CAPACITORE', '2200uF/50V', 50, 'C2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:13:29.797366+00:00', '2026-08-27T09:13:29.797366+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('badb2fef-861d-4f4a-9b41-6732304ba4a1', 'ELECTROLITIC CAPACITORE', '1000UF/50V', 200, 'C2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:16:51.713636+00:00', '2026-08-27T09:16:51.713636+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('5d3909b1-f5bf-4038-9e06-48ff07c2f38d', 'ELECTROLITIC CAPACITORE', '2200uF/35V', 25, 'C2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:18:57.960731+00:00', '2026-08-27T09:18:57.960731+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('23214d67-db69-47a5-b87d-366842f85b46', 'FILM CAPACITOR', '100nF/305V~', 450, 'C2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:09:06.818616+00:00', '2026-08-27T09:09:06.818616+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('9a759b87-9db2-4eda-906a-a8e1247d8315', 'IGBT_THT', 'ID30G65HB', 52, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:37:26.755479+00:00', '2026-08-27T09:37:26.755479+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('bc047ac7-1e74-4371-88df-01929accd134', 'IGBT_THT', '75G65WE', 20, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:48:02.252304+00:00', '2026-08-27T09:48:02.252304+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('475d332c-6f83-49f6-97ae-02e38ed8d756', 'IGBT_THT', '75X5120C', 9, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:46:44.436773+00:00', '2026-08-27T09:46:44.436773+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('321eadff-de9a-4849-8a0d-0d203feca9ce', 'IGBT_THT', 'FGH40N60', 6, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:42:11.228202+00:00', '2026-08-27T09:42:11.228202+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('768b8143-9b96-45bf-8bb3-5f524306dc04', 'IGBT_THT', 'PC50N065AH7S', 25, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:49:42.404193+00:00', '2026-08-27T09:49:42.404193+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('83f037f5-0de3-4000-b0ad-b66491418bb8', 'IGBT_THT', 'SG60T121UDB3', 7, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:41:14.65288+00:00', '2026-08-27T09:41:14.65288+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('ea61f9a6-fe25-4be6-bebe-2369eba921bf', 'INDUCTOR_0805', '4.7UH', 40, 'B2.2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:48:57.010533+00:00', '2026-08-27T06:48:57.010533+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('bf798b59-c9d1-4ed8-80ae-d730cee10fff', 'INDUCTOR_12X12MM', '33UH', 16, 'B2.3', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:46:12.740417+00:00', '2026-08-27T06:46:12.740417+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('42cfd838-88db-4047-8d13-e6f9ef13188e', 'INDUCTOR_12X12MM', '220UH', 7, 'B2.3', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:45:01.050852+00:00', '2026-08-27T06:45:01.050852+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('40007d6a-8a2c-45e7-87e3-2918e67ad84d', 'INDUCTOR_2A_SMD', '47UH', 9, 'B2.3', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:46:58.758485+00:00', '2026-08-27T06:46:58.758485+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('5ddfeb0e-c548-4b7d-b6df-3d80063e7083', 'INDUCTOR_5X5MM', '22UH', 70, 'B2.3', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:52:39.630034+00:00', '2026-08-27T06:52:39.630034+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('5e85f41c-bc7b-49f3-bc83-23790d1a0420', 'INDUCTOR_5X5MM', '220UH', 10, 'B2.3', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:54:07.865965+00:00', '2026-08-27T06:54:07.865965+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('c0dc49ec-6810-4f51-8a2b-d646a29382c3', 'INDUCTOR_5X5MM', '4.7UH', 4, 'B2.3', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:51:02.674539+00:00', '2026-08-27T06:51:02.674539+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('7981e45c-0763-4aa0-893b-73cea92e9859', 'LED', '3MM(GREEN)', 900, 'B3.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:08:59.906566+00:00', '2026-08-27T07:08:59.906566+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('29539cb0-d59d-475a-ac3f-fbfc557d4588', 'LED', '3MM(BLUE)', 900, 'B3.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:07:47.849624+00:00', '2026-08-27T07:07:47.849624+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('5b9f01c7-e3bb-484a-863a-01b5a20d59ba', 'LED', '3MM(RED)', 950, 'B3.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:08:21.56737+00:00', '2026-08-27T07:08:21.56737+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('d8d851bc-4195-4054-90d7-3a5872acc350', 'LED', '3MM(YELLOW)', 900, 'B3.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:07:01.346662+00:00', '2026-08-27T07:07:01.346662+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('50c018ef-04fe-4b86-88f1-be26239d8fe8', 'NTC', 'MF72 10 D-15', 18, 'B1.2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:49:50.232261+00:00', '2026-08-27T06:49:50.232261+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('c0c5d00e-fc9b-4310-94b2-8e5c8930460c', 'POLYESTER CAPACIROR', '2.2uF/630V', 200, 'C2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:11:56.43179+00:00', '2026-08-27T09:11:56.43179+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('bf196985-5067-4c54-8a2a-97092c4807b7', 'POLYESTER CAPACITOR', '1uF/ 630V', 300, 'C2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:07:42.269086+00:00', '2026-08-27T09:07:42.269086+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('325daa2f-589f-4d4d-9f51-9454919a6837', 'Relay', 'HF33F', 100, 'A3', '', '', '', '', NULL, false, '2026-08-22T16:25:30.387646+00:00', '2026-08-26T11:12:36.745731+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('d87a368b-b3b5-4399-abdd-1580a1506c3e', 'RESISTOR', '10OHMS', 1000, 'A5', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T05:46:52.217021+00:00', '2026-08-27T05:46:52.217021+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('ced2c8ce-1676-4983-9853-72d30edf36c9', 'RESISTOR_0603', '12K', 100, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:07:46.142789+00:00', '2026-08-27T06:07:46.142789+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('9391cb1f-17db-438b-abec-e66ad8a0cbf3', 'RESISTOR_0603', '200R', 100, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:14:40.316275+00:00', '2026-08-27T06:14:40.316275+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('6b15be30-64a7-44da-97b5-cd34362dc6a9', 'RESISTOR_0603', '2K7', 100, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:14:20.366655+00:00', '2026-08-27T06:14:20.366655+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('20795bdd-326e-4755-9568-9482066195c2', 'RESISTOR_0603', '56K', 100, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:13:58.336373+00:00', '2026-08-27T06:13:58.336373+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('c7bc78a7-17b9-47bd-a0fb-7b492c62085f', 'RESISTOR_0603', '220R', 100, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:13:05.905431+00:00', '2026-08-27T06:13:05.905431+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('dc0a985a-93ab-422b-855f-f1de0a153c85', 'RESISTOR_0603', '15K', 100, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:12:43.905811+00:00', '2026-08-27T06:12:43.905811+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('ce67a6b6-6359-422f-80f0-02c018155f84', 'RESISTOR_0603', '20k', 100, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:12:16.030999+00:00', '2026-08-27T06:12:16.030999+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('3b1392d4-192e-4047-a727-46b8e1b94de1', 'RESISTOR_0603', '0R', 200, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:10:42.50468+00:00', '2026-08-27T06:10:42.50468+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('3b70040f-0d85-4387-8e70-81867c931a5e', 'RESISTOR_0603', '1K2', 100, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:10:05.716636+00:00', '2026-08-27T06:10:05.716636+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('c0eff885-e4bf-49fb-a88f-ab198c035c78', 'RESISTOR_0603', '3K', 100, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:09:38.72794+00:00', '2026-08-27T06:09:38.72794+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('117d52e7-a733-4729-a767-7438c5df6d9c', 'RESISTOR_0603', '1K', 100, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:09:16.984499+00:00', '2026-08-27T06:09:16.984499+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('eeea4387-e8e3-40a4-ac39-684904a599c1', 'RESISTOR_0603', '150K', 100, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:07:08.461034+00:00', '2026-08-27T06:07:08.461034+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('28b66363-2c09-45b1-864a-c6cd8be01ddd', 'RESISTOR_0603', '33K', 100, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:33:42.785753+00:00', '2026-08-27T06:33:42.785753+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('a08af6ac-5eaf-48a2-ab22-be87f41cc62d', 'RESISTOR_0603', '56R', 200, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:33:29.89534+00:00', '2026-08-27T06:33:29.89534+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('816133ae-43b1-4adc-8c8b-4f4dcf4efa32', 'RESISTOR_0603', '4K3', 100, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:32:41.178928+00:00', '2026-08-27T06:32:41.178928+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('3303068d-7855-4b51-a2ca-9340bde3e9c8', 'RESISTOR_0603', '100K', 100, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:32:17.416803+00:00', '2026-08-27T06:32:17.416803+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('36cd83bd-1188-4fa1-b190-915859498eba', 'RESISTOR_0603', '5K6', 200, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:31:57.729133+00:00', '2026-08-27T06:31:57.729133+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('198ebe83-76ea-4ac2-85d7-7a2e5eef0dd4', 'RESISTOR_0603', '10R', 100, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:31:28.447391+00:00', '2026-08-27T06:31:28.447391+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('31597139-389f-48ed-97e2-d90958ba9ede', 'RESISTOR_0603', '39K', 200, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:16:37.986529+00:00', '2026-08-27T06:16:37.986529+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('389449c0-63b2-4a4e-8195-2a3dd600ed98', 'RESISTOR_0603', '680R', 100, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:15:38.855082+00:00', '2026-08-27T06:15:38.855082+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('d336e284-5003-48ea-b114-dcaeccef99fc', 'RESISTOR_0603', '1R', 1000, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:15:22.762414+00:00', '2026-08-27T06:15:22.762414+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('7e322434-e7f2-42c7-a411-5c3b8dc0b03e', 'RESISTOR_0603', '10K', 200, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:14:59.276247+00:00', '2026-08-27T06:14:59.276247+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('9e094890-1d3d-4751-b03a-40cc5a3f0dc1', 'RESISTOR_0805', '0R', 100, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:11:08.712026+00:00', '2026-08-27T06:11:08.712026+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('0a55c784-c9a7-418a-b007-8a9aafc73e69', 'RESISTOR_0805', '10R', 300, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:17:18.43843+00:00', '2026-08-27T06:17:18.43843+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('cc0b87a5-7dbc-4aca-a7e9-bf1b491511a8', 'RESISTOR_0805', '10R', 500, 'B2.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:08:41.803136+00:00', '2026-08-27T06:08:41.803136+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('186052f0-4027-401e-b89f-65cfed7508b3', 'SCHOTTKY DIODE', 'SS14', 20, 'B4.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:15:50.816026+00:00', '2026-08-27T07:15:50.816026+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('182c739b-4593-4ecd-967b-e2c855e29316', 'SCHOTTKY DIODE', 'SS34', 30, 'B4.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T07:14:31.752538+00:00', '2026-08-27T07:14:31.752538+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('1a1f3626-a1ec-4352-8f60-3c4bb675c3a9', 'STM32F401 Microcontroller', 'STM32F401RCT6', 25, 'C-12', '', '', '', '', NULL, false, '2026-08-26T11:11:47.880678+00:00', '2026-08-27T05:33:51.845213+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('e8f6f202-efac-43dd-8786-e3ef1284d98a', 'TRANSISTOR', 'D44H11T', 5, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:22:54.265808+00:00', '2026-08-27T09:22:54.265808+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('875dcdb6-e76d-425a-89a7-b86303a825c2', 'TRANSISTOR_THT', 'D45H11T', 19, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:26:46.216589+00:00', '2026-08-27T09:26:46.216589+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('4a270489-0a93-428b-942c-23fb2b80c82d', 'TRANSISTOR_THT', 'D44H11T', 21, 'LAB_3(BOX)', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T09:26:16.479339+00:00', '2026-08-27T09:26:16.479339+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('3a9c97c8-f492-4d0f-8cc7-58e30fc86293', 'VARIASTER (MOV)', '14D511K', 90, 'B1.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:35:23.151644+00:00', '2026-08-27T06:35:23.151644+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('276dc735-b7b0-4761-a0ea-7e929142d2ca', 'VARIASTER (MOV)', '20D751K', 220, 'B1.2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:45:39.498897+00:00', '2026-08-27T06:45:39.498897+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('f9e8ee72-3c4e-468b-bb80-01db39f1568f', 'VARIASTER (MOV)', '07D471K', 900, 'B1.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:41:28.661498+00:00', '2026-08-27T06:41:28.661498+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('527b337f-bcf7-4931-9daa-8df4a49a1a6b', 'VARIASTER (MOV)', 'S14K680', 9, 'B1.2', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:47:00.58152+00:00', '2026-08-27T06:47:00.58152+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('d4d61d38-f2e7-437d-a30a-6635de6f0124', 'VARIASTER (MOV)', '14D471K', 200, 'B1.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:37:36.221323+00:00', '2026-08-27T06:37:36.221323+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
INSERT INTO public.components (id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_by, is_demo, created_at, updated_at)
VALUES ('12d2b82a-25a2-4e1b-b990-eacd23d8eccc', 'VARIASTER (MOV)', '14D431K', 68, 'B1.1', '', '', '', '', (SELECT id FROM public.app_users WHERE user_id = 'hpt_admin' LIMIT 1), false, '2026-08-27T06:29:27.525774+00:00', '2026-08-27T06:29:27.525774+00:00')
ON CONFLICT (id) DO UPDATE SET
  component_name = EXCLUDED.component_name,
  part_number = EXCLUDED.part_number,
  quantity = EXCLUDED.quantity,
  cupboard_number = EXCLUDED.cupboard_number,
  manufacturer = EXCLUDED.manufacturer,
  vendor = EXCLUDED.vendor,
  specification = EXCLUDED.specification,
  package = EXCLUDED.package,
  created_by = EXCLUDED.created_by,
  updated_at = EXCLUDED.updated_at;
