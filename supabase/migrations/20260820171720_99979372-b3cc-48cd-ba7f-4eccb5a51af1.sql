CREATE TABLE public.app_users (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  user_id TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user','admin')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.components (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  component_name TEXT NOT NULL,
  part_number TEXT NOT NULL,
  quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  cupboard_number TEXT NOT NULL,
  created_by UUID REFERENCES public.app_users(id) ON DELETE SET NULL,
  is_demo BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_components_name ON public.components (lower(component_name));
CREATE INDEX idx_components_part ON public.components (lower(part_number));
CREATE INDEX idx_components_cupboard ON public.components (lower(cupboard_number));
CREATE INDEX idx_components_created_at ON public.components (created_at DESC);
CREATE INDEX idx_app_users_user_id ON public.app_users (lower(user_id));

GRANT ALL ON public.app_users TO service_role;
GRANT ALL ON public.components TO service_role;

ALTER TABLE public.app_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.components ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.hpt_touch_updated_at() RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql SET search_path = public;

CREATE TRIGGER trg_app_users_updated BEFORE UPDATE ON public.app_users
FOR EACH ROW EXECUTE FUNCTION public.hpt_touch_updated_at();
CREATE TRIGGER trg_components_updated BEFORE UPDATE ON public.components
FOR EACH ROW EXECUTE FUNCTION public.hpt_touch_updated_at();

INSERT INTO public.app_users (name, user_id, password_hash, role)
VALUES ('HPT Administrator', 'hpt_admin', 'pbkdf2$100000$88f075c7c141d60c7f00016e0acf506d$01e543d0384e68a546d9c86ec346b766ba264a2b6d29b3fd562e7b1e6598dc75', 'admin');

INSERT INTO public.components (component_name, part_number, quantity, cupboard_number, is_demo) VALUES
  ('10K Resistor', 'R-10K-0805', 500, 'C-01', true),
  ('100K Resistor', 'R-100K-0805', 300, 'C-01', true),
  ('1N4007 Diode', '1N4007', 150, 'C-02', true),
  ('LM358 IC', 'LM358P', 80, 'C-03', true),
  ('100uF Capacitor', 'CAP-100UF-25V', 120, 'C-04', true);