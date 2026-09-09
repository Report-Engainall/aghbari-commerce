begin;

select plan(12);

select ok(to_regprocedure('public.create_inventory_reconciliation(uuid,uuid)') is not null, 'preview RPC exists');
select ok(to_regprocedure('public.approve_inventory_reconciliation(uuid)') is not null, 'approval RPC exists');
select ok(to_regprocedure('public.apply_inventory_reconciliation(uuid)') is not null, 'apply RPC exists');
select ok(to_regprocedure('public.rollback_inventory_reconciliation(uuid)') is not null, 'rollback RPC exists');
select ok(has_function_privilege('anon','public.create_inventory_reconciliation(uuid,uuid)','execute') = false, 'anon cannot preview reconciliation');
select ok(has_function_privilege('anon','public.approve_inventory_reconciliation(uuid)','execute') = false, 'anon cannot approve reconciliation');
select ok(has_function_privilege('anon','public.apply_inventory_reconciliation(uuid)','execute') = false, 'anon cannot apply reconciliation');
select ok(has_function_privilege('anon','public.rollback_inventory_reconciliation(uuid)','execute') = false, 'anon cannot rollback reconciliation');
select ok(has_function_privilege('authenticated','public.create_inventory_reconciliation(uuid,uuid)','execute'), 'authenticated can preview reconciliation');
select ok(has_function_privilege('authenticated','public.approve_inventory_reconciliation(uuid)','execute'), 'authenticated can approve reconciliation');
select ok(has_function_privilege('authenticated','public.apply_inventory_reconciliation(uuid)','execute'), 'authenticated can apply reconciliation');
select ok(has_function_privilege('authenticated','public.rollback_inventory_reconciliation(uuid)','execute'), 'authenticated can rollback reconciliation');

select * from finish();
rollback;
