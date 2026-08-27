-- ====================================================================
-- FIX PERMISSIONS SCRIPT FOR DATABASE: tqfifjxhuzahisyahnzl
-- Grants execute permissions to anon, authenticated, service_role, and postgres.
-- ====================================================================

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role, postgres;
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role, postgres;

GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role, postgres;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role, postgres;
GRANT ALL ON ALL ROUTINES IN SCHEMA public TO anon, authenticated, service_role, postgres;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role, postgres;
