begin;

select plan(25);

select has_index('public', 'payments', 'payments_org_idempotency_key_uidx'::name);
select ok(exists (select 1 from information_schema.columns where table_schema='public' and table_name='payments' and column_name='idempotency_key'), 'payments stores idempotency key');
select ok(exists (select 1 from information_schema.columns where table_schema='public' and table_name='payments' and column_name='idempotency_payload_hash'), 'payments stores idempotency payload binding');
select ok(to_regprocedure('public.record_payment(uuid,numeric,payment_method,uuid,text,text)') is not null, 'record_payment exposes canonical idempotent signature');
select ok(to_regprocedure('public.record_payment(uuid,numeric,payment_method,uuid,text)') is null, 'legacy non-idempotent record_payment signature removed');
select is(has_function_privilege('authenticated','public.record_payment(uuid,numeric,payment_method,uuid,text,text)','execute'), true, 'authenticated can execute canonical payment RPC');
select is(has_function_privilege('anon','public.record_payment(uuid,numeric,payment_method,uuid,text,text)','execute'), false, 'anon cannot execute payment RPC');

select is((select pg_get_function_result('public.bind_customer_device(text,text)'::regprocedure)), 'jsonb', 'bind_customer_device returns safe JSON contract');
select is((select pg_get_function_result('public.request_customer_device_change(text,text,text)'::regprocedure)), 'jsonb', 'request_customer_device_change returns safe JSON contract');
select is((select pg_get_function_result('public.review_device_change_request(uuid,boolean,text)'::regprocedure)), 'jsonb', 'review_device_change_request returns safe JSON contract');
select ok(position('jsonb_build_object(''device_key_hash''' in pg_get_functiondef('public.bind_customer_device(text,text)'::regprocedure)) = 0, 'bind JSON response has no device hash key');
select ok(position('jsonb_build_object(''requested_device_key_hash''' in pg_get_functiondef('public.request_customer_device_change(text,text,text)'::regprocedure)) = 0, 'request JSON response has no requested hash key');
select ok(position('jsonb_build_object(''requested_device_key_hash''' in pg_get_functiondef('public.review_device_change_request(uuid,boolean,text)'::regprocedure)) = 0, 'review JSON response has no requested hash key');

select is(has_function_privilege('authenticated','public.notify_order_status_change()','execute'), false, 'authenticated cannot execute trigger-only notification function');
select is(has_function_privilege('anon','public.notify_order_status_change()','execute'), false, 'anon cannot execute trigger-only notification function');
select ok(exists (select 1 from pg_trigger where tgfoid='public.notify_order_status_change()'::regprocedure), 'order status notification trigger remains installed');

select ok(to_regprocedure('public.get_catalog(text,uuid,integer,integer,uuid)') is not null, 'five-argument catalog RPC exists');
select ok(to_regprocedure('public.get_catalog(text,uuid,integer,integer)') is null, 'four-argument catalog RPC removed');

select ok(to_regprocedure('public.get_customer_payments()') is not null, 'customer payment history RPC exists');
select is(has_function_privilege('authenticated','public.get_customer_payments()','execute'), true, 'authenticated can read scoped customer payment history');
select is(has_function_privilege('anon','public.get_customer_payments()','execute'), false, 'anon cannot read customer payment history');

select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef), 46::bigint, 'expected hardened SECURITY DEFINER function count');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and coalesce(p.proconfig,'{}') @> array['search_path=""']), 46::bigint, 'all SECURITY DEFINER functions pin empty search_path');
select is((select prosecdef from pg_proc where oid='public.record_payment(uuid,numeric,payment_method,uuid,text,text)'::regprocedure), true, 'record_payment remains SECURITY DEFINER');
select is((select proconfig @> array['search_path=""'] from pg_proc where oid='public.record_payment(uuid,numeric,payment_method,uuid,text,text)'::regprocedure), true, 'record_payment pins empty search_path');
select is((select proconfig @> array['search_path=""'] from pg_proc where oid='public.get_catalog(text,uuid,integer,integer,uuid)'::regprocedure), true, 'canonical catalog pins empty search_path');

select * from finish();
rollback;
