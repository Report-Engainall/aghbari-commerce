begin;
select plan(6);

select ok(to_regprocedure('public.set_cart_items(jsonb)') is not null, 'bulk cart RPC exists');
select is(has_function_privilege('authenticated','public.set_cart_items(jsonb)','execute'), true, 'authenticated can execute bulk cart RPC');
select is(has_function_privilege('anon','public.set_cart_items(jsonb)','execute'), false, 'anon cannot execute bulk cart RPC');
select ok((select prosecdef from pg_proc where oid='public.set_cart_items(jsonb)'::regprocedure), 'bulk cart RPC is security definer');
select ok((select proconfig @> array['search_path=""'] from pg_proc where oid='public.set_cart_items(jsonb)'::regprocedure), 'bulk cart RPC pins empty search_path');
select ok(not has_function_privilege('public','public.set_cart_items(jsonb)','execute'), 'public cannot execute bulk cart RPC');

select * from finish();
rollback;
