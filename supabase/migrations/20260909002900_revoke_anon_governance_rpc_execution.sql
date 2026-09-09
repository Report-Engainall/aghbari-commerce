REVOKE EXECUTE ON FUNCTION public.begin_operation_idempotency(text,text,text,integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.complete_operation_idempotency(uuid,text,uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_intelligence_evidence(text,uuid,text,text,jsonb,text,jsonb,jsonb,numeric,timestamptz,timestamptz) FROM anon;
