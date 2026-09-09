-- Unified data governance layer: versioned import profiles, central synonyms,
-- server-side idempotency, evidence provenance, and isolated Onyx/live inventory reconciliation.

CREATE TABLE IF NOT EXISTS public.import_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  profile_id text NOT NULL, profile_name text NOT NULL, report_type text NOT NULL, source text NOT NULL, version integer NOT NULL CHECK (version > 0),
  required_columns jsonb NOT NULL DEFAULT '[]'::jsonb, optional_columns jsonb NOT NULL DEFAULT '[]'::jsonb, ignored_columns jsonb NOT NULL DEFAULT '[]'::jsonb,
  synonyms jsonb NOT NULL DEFAULT '{}'::jsonb, transformation_rules jsonb NOT NULL DEFAULT '[]'::jsonb, validation_rules jsonb NOT NULL DEFAULT '[]'::jsonb,
  matching_key text NOT NULL, merge_strategy text NOT NULL, date_rules jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('draft','active','retired')), created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL, created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, profile_id, version)
);
CREATE INDEX IF NOT EXISTS import_profiles_org_type_idx ON public.import_profiles(organization_id, report_type, status);

CREATE TABLE IF NOT EXISTS public.import_synonyms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  canonical_column text NOT NULL, synonym text NOT NULL, locale text NOT NULL DEFAULT 'ar', created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL, created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, locale, synonym), UNIQUE (organization_id, locale, canonical_column, synonym)
);
CREATE INDEX IF NOT EXISTS import_synonyms_lookup_idx ON public.import_synonyms(organization_id, locale, synonym);

CREATE TABLE IF NOT EXISTS public.operation_idempotency (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  idempotency_key text NOT NULL CHECK (length(trim(idempotency_key)) BETWEEN 8 AND 200), request_hash text NOT NULL CHECK (length(trim(request_hash)) BETWEEN 32 AND 128),
  operation_type text NOT NULL CHECK (length(trim(operation_type)) BETWEEN 2 AND 120), response_reference uuid, created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'processing' CHECK (status IN ('processing','completed','failed','expired')), UNIQUE (organization_id, idempotency_key, operation_type)
);
CREATE INDEX IF NOT EXISTS operation_idempotency_expiry_idx ON public.operation_idempotency(organization_id, expires_at);

CREATE TABLE IF NOT EXISTS public.intelligence_evidence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  source_type text NOT NULL, source_id uuid, transformation text NOT NULL, metric_key text, metric_value jsonb, insight_key text, insight_value jsonb,
  recommendation jsonb, decision jsonb, outcome jsonb, confidence numeric CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1), period_start timestamptz, period_end timestamptz,
  provenance jsonb NOT NULL DEFAULT '{}'::jsonb, created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS intelligence_evidence_source_idx ON public.intelligence_evidence(organization_id, source_type, source_id, created_at DESC);
CREATE INDEX IF NOT EXISTS intelligence_evidence_metric_idx ON public.intelligence_evidence(organization_id, metric_key, created_at DESC);

CREATE TABLE IF NOT EXISTS public.inventory_reconciliations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT, dataset_id uuid NOT NULL, warehouse_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'preview' CHECK (status IN ('preview','ready','applied','rolled_back','failed')), source_name text NOT NULL, source_fingerprint text NOT NULL,
  summary jsonb NOT NULL DEFAULT '{}'::jsonb, conflicts jsonb NOT NULL DEFAULT '[]'::jsonb, preview jsonb NOT NULL DEFAULT '[]'::jsonb, applied_at timestamptz, rolled_back_at timestamptz,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE (id, organization_id),
  FOREIGN KEY (dataset_id, organization_id) REFERENCES public.onyx_datasets(id, organization_id) ON DELETE RESTRICT,
  FOREIGN KEY (warehouse_id, organization_id) REFERENCES public.warehouses(id, organization_id) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS inventory_reconciliations_lookup_idx ON public.inventory_reconciliations(organization_id, warehouse_id, created_at DESC);

ALTER TABLE public.import_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.import_synonyms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.operation_idempotency ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.intelligence_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_reconciliations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS import_profiles_staff_read ON public.import_profiles;
CREATE POLICY import_profiles_staff_read ON public.import_profiles FOR SELECT TO authenticated USING (organization_id=(select public.current_organization_id()) AND (select public.current_role()) IN ('owner','admin','sales','warehouse'));
DROP POLICY IF EXISTS import_synonyms_staff_read ON public.import_synonyms;
CREATE POLICY import_synonyms_staff_read ON public.import_synonyms FOR SELECT TO authenticated USING (organization_id=(select public.current_organization_id()) AND (select public.current_role()) IN ('owner','admin'));
DROP POLICY IF EXISTS operation_idempotency_staff_read ON public.operation_idempotency;
CREATE POLICY operation_idempotency_staff_read ON public.operation_idempotency FOR SELECT TO authenticated USING (organization_id=(select public.current_organization_id()) AND (select public.current_role()) IN ('owner','admin'));
DROP POLICY IF EXISTS intelligence_evidence_staff_read ON public.intelligence_evidence;
CREATE POLICY intelligence_evidence_staff_read ON public.intelligence_evidence FOR SELECT TO authenticated USING (organization_id=(select public.current_organization_id()) AND (select public.current_role()) IN ('owner','admin','sales','warehouse','viewer'));
DROP POLICY IF EXISTS inventory_reconciliations_staff_read ON public.inventory_reconciliations;
CREATE POLICY inventory_reconciliations_staff_read ON public.inventory_reconciliations FOR SELECT TO authenticated USING (organization_id=(select public.current_organization_id()) AND (select public.current_role()) IN ('owner','admin','warehouse'));

CREATE OR REPLACE FUNCTION public.begin_operation_idempotency(p_idempotency_key text,p_request_hash text,p_operation_type text,p_ttl_seconds integer DEFAULT 86400)
RETURNS public.operation_idempotency LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_org uuid:=public.current_organization_id(); v_role public.user_role:=public.current_role(); v_row public.operation_idempotency%rowtype;
BEGIN
  IF v_org IS NULL OR v_role NOT IN ('owner','admin','sales','warehouse') THEN RAISE EXCEPTION USING errcode='42501',message='idempotency access required'; END IF;
  IF nullif(trim(p_idempotency_key),'') IS NULL OR length(trim(p_idempotency_key)) < 8 THEN RAISE EXCEPTION USING errcode='22023',message='idempotency key required'; END IF;
  IF nullif(trim(p_request_hash),'') IS NULL OR length(trim(p_request_hash)) < 32 THEN RAISE EXCEPTION USING errcode='22023',message='request hash required'; END IF;
  IF nullif(trim(p_operation_type),'') IS NULL THEN RAISE EXCEPTION USING errcode='22023',message='operation type required'; END IF;
  IF p_ttl_seconds < 60 OR p_ttl_seconds > 604800 THEN RAISE EXCEPTION USING errcode='22023',message='ttl out of bounds'; END IF;
  SELECT * INTO v_row FROM public.operation_idempotency WHERE organization_id=v_org AND idempotency_key=trim(p_idempotency_key) AND operation_type=trim(p_operation_type) FOR UPDATE;
  IF FOUND THEN
    IF v_row.request_hash <> trim(p_request_hash) THEN RAISE EXCEPTION USING errcode='23505',message='idempotency key is already bound to a different request'; END IF;
    IF v_row.expires_at <= now() AND v_row.status <> 'completed' THEN UPDATE public.operation_idempotency SET status='expired',expires_at=now() WHERE id=v_row.id RETURNING * INTO v_row; END IF;
    RETURN v_row;
  END IF;
  INSERT INTO public.operation_idempotency(organization_id,idempotency_key,request_hash,operation_type,expires_at) VALUES(v_org,trim(p_idempotency_key),trim(p_request_hash),trim(p_operation_type),now()+make_interval(secs=>p_ttl_seconds)) RETURNING * INTO v_row;
  RETURN v_row;
END; $$;
REVOKE ALL ON FUNCTION public.begin_operation_idempotency(text,text,text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.begin_operation_idempotency(text,text,text,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.complete_operation_idempotency(p_id uuid,p_status text,p_response_reference uuid DEFAULT NULL)
RETURNS public.operation_idempotency LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_org uuid:=public.current_organization_id(); v_row public.operation_idempotency%rowtype;
BEGIN
  IF v_org IS NULL OR p_status NOT IN ('completed','failed') THEN RAISE EXCEPTION USING errcode='22023',message='invalid idempotency completion'; END IF;
  UPDATE public.operation_idempotency SET status=p_status,response_reference=coalesce(p_response_reference,response_reference) WHERE id=p_id AND organization_id=v_org RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002',message='idempotency record not found'; END IF;
  RETURN v_row;
END; $$;
REVOKE ALL ON FUNCTION public.complete_operation_idempotency(uuid,text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_operation_idempotency(uuid,text,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_intelligence_evidence(p_source_type text,p_source_id uuid,p_transformation text,p_metric_key text,p_metric_value jsonb,p_insight_key text,p_insight_value jsonb,p_recommendation jsonb,p_confidence numeric,p_period_start timestamptz,p_period_end timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_org uuid:=public.current_organization_id(); v_role public.user_role:=public.current_role(); v_id uuid;
BEGIN
  IF v_org IS NULL OR v_role NOT IN ('owner','admin') THEN RAISE EXCEPTION USING errcode='42501',message='evidence write access required'; END IF;
  IF nullif(trim(p_source_type),'') IS NULL OR nullif(trim(p_transformation),'') IS NULL THEN RAISE EXCEPTION USING errcode='22023',message='evidence source and transformation required'; END IF;
  IF p_confidence IS NOT NULL AND (p_confidence < 0 OR p_confidence > 1) THEN RAISE EXCEPTION USING errcode='22023',message='confidence must be between 0 and 1'; END IF;
  INSERT INTO public.intelligence_evidence(organization_id,source_type,source_id,transformation,metric_key,metric_value,insight_key,insight_value,recommendation,confidence,period_start,period_end,created_by) VALUES(v_org,trim(p_source_type),p_source_id,trim(p_transformation),p_metric_key,p_metric_value,p_insight_key,p_insight_value,p_recommendation,p_confidence,p_period_start,p_period_end,auth.uid()) RETURNING id INTO v_id;
  RETURN v_id;
END; $$;
REVOKE ALL ON FUNCTION public.create_intelligence_evidence(text,uuid,text,text,jsonb,text,jsonb,jsonb,numeric,timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_intelligence_evidence(text,uuid,text,text,jsonb,text,jsonb,jsonb,numeric,timestamptz,timestamptz) TO authenticated;
