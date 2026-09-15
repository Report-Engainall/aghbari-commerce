begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users (id, email) values ('11111111-1111-4111-8111-111111111111','transfer-admin@test.local');
insert into public.organizations (id,name) values
 ('11111111-1111-4111-8111-111111111112','Tenant A'),
 ('22222222-2222-4222-8222-222222222222','Tenant B');
insert into public.branches (id,organization_id,name) values
 ('11111111-1111-4111-8111-111111111113','11111111-1111-4111-8111-111111111112','A Main'),
 ('22222222-2222-4222-8222-222222222223','22222222-2222-4222-8222-222222222222','B Main');
insert into public.warehouses (id,organization_id,branch_id,name) values
 ('11111111-1111-4111-8111-111111111114','11111111-1111-4111-8111-111111111112','11111111-1111-4111-8111-111111111113','A Source'),
 ('11111111-1111-4111-8111-111111111115','11111111-1111-4111-8111-111111111112','11111111-1111-4111-8111-111111111113','A Dest'),
 ('22222222-2222-4222-8222-222222222224','22222222-2222-4222-8222-222222222223','B Warehouse');
insert into public.products (id,organization_id,sku,name,unit) values
 ('11111111-1111-4111-8111-111111111116','11111111-1111-4111-8111-111111111112','A-001','A Product','carton'),
 ('22222222-2222-4222-8222-222222222225','22222222-2222-4222-8222-222222222222','B-001','B Product','carton');
insert into public.profiles (id,organization_id,role) values
 ('11111111-1111-4111-8111-111111111111','11111111-1111-4111-8111-111111111112','admin');
insert into public.inventory_balances(organization_id,warehouse_id,product_id,quantity) values
 ('11111111-1111-4111-8111-111111111112','11111111-1111-4111-8111-111111111114','11111111-1111-4111-8111-111111111116',10),
 ('11111111-1111-4111-8111-111111111112','11111111-1111-4111-8111-111111111115','11111111-1111-4111-8111-111111111116',0),
 ('22222222-2222-4222-8222-222222222222','22222222-2222-4222-8222-222222222224','22222222-2222-4222-8222-222222222225',10);

set local role authenticated;
set local request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';

select is((select total_quantity from public.transfer_inventory('11111111-1111-4111-8111-111111111114','11111111-1111-4111-8111-111111111115','adv-001',jsonb_build_array(jsonb_build_object('product_id','11111111-1111-4111-8111-111111111116','quantity',2)),'adversarial')),2::bigint,'valid transfer');
select is((select quantity from public.inventory_balances where warehouse_id='11111111-1111-4111-8111-111111111114' and product_id='11111111-1111-4111-8111-111111111116'),8,'source decremented');
select is((select quantity from public.inventory_balances where warehouse_id='11111111-1111-4111-8111-111111111115' and product_id='11111111-1111-4111-8111-111111111116'),2,'destination incremented');
select is((select total_quantity from public.transfer_inventory('11111111-1111-4111-8111-111111111114','11111111-1111-4111-8111-111111111115','adv-001',jsonb_build_array(jsonb_build_object('product_id','11111111-1111-4111-8111-111111111116','quantity',2)),'adversarial')),2::bigint,'same-key replay is idempotent');
select throws_ok($$select * from public.transfer_inventory('11111111-1111-4111-8111-111111111114','11111111-1111-4111-8111-111111111115','adv-001',jsonb_build_array(jsonb_build_object('product_id','11111111-1111-4111-8111-111111111116','quantity',3)),'conflict')$$,NULL,NULL,'same-key different payload is rejected');
select throws_ok($$select * from public.transfer_inventory('11111111-1111-4111-8111-111111111114','11111111-1111-4111-8111-111111111115','adv-002',jsonb_build_array(jsonb_build_object('product_id','11111111-1111-4111-8111-111111111116','quantity',99)),'insufficient')$$,NULL,NULL,'insufficient stock is rejected');
select throws_ok($$select * from public.transfer_inventory('11111111-1111-4111-8111-111111111114','22222222-2222-4222-8222-222222222224','adv-003',jsonb_build_array(jsonb_build_object('product_id','11111111-1111-4111-8111-111111111116','quantity',1)),'cross tenant')$$,NULL,NULL,'cross-tenant warehouse is rejected');
select throws_ok($$select * from public.transfer_inventory('11111111-1111-4111-8111-111111111114','11111111-1111-4111-8111-111111111115','adv-004',jsonb_build_array(jsonb_build_object('product_id','11111111-1111-4111-8111-111111111116','quantity',0)),'zero')$$,NULL,NULL,'zero quantity is rejected');
select throws_ok($$select * from public.transfer_inventory('11111111-1111-4111-8111-111111111114','11111111-1111-4111-8111-111111111115','adv-005',jsonb_build_array(jsonb_build_object('product_id','22222222-2222-4222-8222-222222222225','quantity',1)),'cross tenant product')$$,NULL,NULL,'cross-tenant product is rejected');
select is((select quantity from public.inventory_balances where warehouse_id='11111111-1111-4111-8111-111111111114' and product_id='11111111-1111-4111-8111-111111111116'),8,'rejected operations do not mutate source');
select * from finish();
rollback;
