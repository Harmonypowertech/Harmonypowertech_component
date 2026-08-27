CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE TABLE IF NOT EXISTS public.hpt_sessions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES public.app_users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT ALL ON public.hpt_sessions TO service_role;

ALTER TABLE public.hpt_sessions ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_hpt_sessions_token_hash ON public.hpt_sessions (token_hash);
CREATE INDEX IF NOT EXISTS idx_hpt_sessions_expires_at ON public.hpt_sessions (expires_at);

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
         c.created_at, c.updated_at, c.created_by, u.name AS created_by_name, c.is_demo
  FROM public.components c
  LEFT JOIN public.app_users u ON u.id = c.created_by
  WHERE v_term = ''
     OR c.component_name ILIKE '%' || v_term || '%'
     OR c.part_number ILIKE '%' || v_term || '%'
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
     OR c.part_number ILIKE '%' || v_term || '%';

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
  _cupboard_number TEXT
)
RETURNS TABLE(
  id UUID,
  component_name TEXT,
  part_number TEXT,
  quantity INTEGER,
  cupboard_number TEXT,
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
    INSERT INTO public.components (component_name, part_number, quantity, cupboard_number, created_by)
    VALUES (trim(_component_name), trim(_part_number), _quantity, trim(_cupboard_number), v_user.uid)
    RETURNING *
  )
  SELECT c.id, c.component_name, c.part_number, c.quantity, c.cupboard_number,
         c.created_at, c.updated_at, c.created_by, v_user.name::TEXT AS created_by_name, c.is_demo
  FROM inserted c;
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_create_component(TEXT, TEXT, TEXT, INTEGER, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hpt_create_component(TEXT, TEXT, TEXT, INTEGER, TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.hpt_update_component(
  _session_token TEXT,
  _id UUID,
  _component_name TEXT,
  _part_number TEXT,
  _quantity INTEGER,
  _cupboard_number TEXT
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
  SELECT * INTO v_user FROM public.hpt_require_session(_session_token, true) LIMIT 1;

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
      cupboard_number = trim(_cupboard_number)
  WHERE components.id = _id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count = 0 THEN
    RAISE EXCEPTION 'Component not found.';
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.hpt_update_component(TEXT, UUID, TEXT, TEXT, INTEGER, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hpt_update_component(TEXT, UUID, TEXT, TEXT, INTEGER, TEXT) TO anon, authenticated;

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