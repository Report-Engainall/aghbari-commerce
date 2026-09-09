-- Reconstructed from the deployed Supabase migration 20260909004145.
-- Keep anonymous execution disabled for the resumable product-import RPC surface.
REVOKE EXECUTE ON FUNCTION public.begin_product_import(text,text,integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.stage_product_import_chunk(uuid,integer,jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.finalize_product_import(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.commit_product_import(uuid,uuid) FROM anon;
