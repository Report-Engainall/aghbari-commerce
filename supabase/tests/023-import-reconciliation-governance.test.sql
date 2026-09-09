begin;

select plan(10);

select ok(to_regprocedure('public.begin_product_import(text,text,integer)') is not null, 'resumable import begin RPC exists');
select ok(to_regprocedure('public.stage_product_import_chunk(uuid,integer,jsonb)') is not null, 'chunk RPC exists');
select ok(to_regprocedure('public.finalize_product_import(uuid)') is not null, 'finalize RPC exists');
select ok(to_regprocedure('public.commit_product_import(uuid,uuid)') is not null, 'commit RPC exists');
select ok(to_regprocedure('public.create_inventory_reconciliation(uuid,uuid)') is not null, 'reconciliation preview RPC exists');
select ok(to_regprocedure('public.approve_inventory_reconciliation(uuid)') is not null, 'reconciliation approval RPC exists');
select ok(to_regprocedure('public.apply_inventory_reconciliation(uuid)') is not null, 'reconciliation apply RPC exists');
select ok(to_regprocedure('public.rollback_inventory_reconciliation(uuid)') is not null, 'reconciliation rollback RPC exists');
select ok(has_function_privilege('anon','public.begin_product_import(text,text,integer)','execute') = false, 'anon cannot begin import');
select ok(has_function_privilege('anon','public.apply_inventory_reconciliation(uuid)','execute') = false, 'anon cannot mutate live inventory through reconciliation');

select * from finish();
rollback;
