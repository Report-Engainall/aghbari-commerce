begin;
select plan(8);

select ok(to_regclass('public.order_templates') is not null, 'order_templates table exists');
select is((select relrowsecurity from pg_class where oid='public.order_templates'::regclass), true, 'order_templates has RLS enabled');
select ok(exists(select 1 from pg_policy where polrelid='public.order_templates'::regclass and polname='order_templates_select_own' and polcmd='r'), 'order_templates select is customer-owned');
select ok(exists(select 1 from pg_policy where polrelid='public.order_templates'::regclass and polname='order_templates_insert_own' and polcmd='a'), 'order_templates insert is customer-owned');
select ok(to_regprocedure('public.get_customer_payments()') is not null, 'customer payment history RPC exists');
select is(has_function_privilege('authenticated','public.get_customer_payments()','execute'), true, 'authenticated can execute customer payment history RPC');
select is(has_function_privilege('anon','public.get_customer_payments()','execute'), false, 'anon cannot execute customer payment history RPC');
select ok(exists(select 1 from pg_policy where polrelid='public.payments'::regclass and polname='payments_customer_read'), 'customer payment access is controlled by payments RLS');

select * from finish();
rollback;
