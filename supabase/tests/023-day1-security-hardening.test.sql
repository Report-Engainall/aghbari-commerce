begin;

select plan(10);

select has_index('public', 'payments', 'uq_payments_organization_idempotency_key', 'payments have a tenant-scoped idempotency index');
select has_column('public', 'payments', 'idempotency_key', 'payments store an idempotency key');
select has_column('public', 'payments', 'idempotency_payload_hash', 'payments store the bound payload hash');
select has_function('public', 'record_payment', array['uuid','numeric','payment_method','uuid','text','text'], 'record_payment requires an idempotency key');
select is(to_regprocedure('public.record_payment(uuid,numeric,payment_method,uuid,text)')::text, null::text, 'legacy five-argument record_payment is removed');
select is(to_regprocedure('public.get_catalog(text,uuid,integer,integer)')::text, null::text, 'obsolete four-argument get_catalog is removed');
select has_function('public', 'get_catalog', array['text','uuid','integer','integer','uuid'], 'canonical warehouse-aware get_catalog remains');
select is(has_function_privilege('anon', 'public.record_payment(uuid,numeric,payment_method,uuid,text,text)', 'EXECUTE'), false, 'anon cannot execute record_payment');
select is(has_function_privilege('authenticated', 'public.notify_order_status_change()', 'EXECUTE'), false, 'authenticated cannot directly execute notification trigger');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and not (coalesce(array_to_string(p.proconfig,','),'') like '%search_path=""%')), 0::bigint, 'all public SECURITY DEFINER functions have empty search_path');

select * from finish();
rollback;
