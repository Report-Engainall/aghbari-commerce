begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

insert into auth.users (id,email) values
('99999999-9999-4999-8999-999999999991','transfer-admin@test.local'),
('99999999-9999-4999-8999-999999999992','transfer-other@test.local');
insert into public.organizations(id,name) values
('56565656-5656-4565-8565-565656565651','Transfer A'),
('56565656-5656-4565-8565-565656565652','Transfer B');
insert into public.branches(id,organization_id,name) values
('56565656-5656-4565-8565-565656565661','56565656-5656-4565-8565-565656565651','Main A'),
('56565656-5656-4565-8565-565656565662','56565656-5656-4565-8565-565656565652','Main B');
insert into public.warehouses(id,organization_id,branch_id,name) values
('56565656-5656-4565-8565-565656565671','56565656-5656-4565-8565-565656565651','56565656-5656-4565-8565-565656565661','Source A'),
('56565656-5656-4565-8565-565656565672','56565656-5656-4565-8565-565656565651','56565656-5656-4565-8565-565656565661','Dest A'),
('56565656-5656-4565-8565-565656565673','56565656-5656-4565-8565-565656565652','56565656-5656-4565-8565-565656565662','Source B'),
('56565656-5656-4565-8565-565656565674','56565656-5656-4565-8565-565656565652','56565656-5656-4565-8565-565656565662','Dest B');
insert into public.products(id,organization_id,sku,name,unit) values
('56565656-5656-4565-8565-565656565681','56565656-5656-4565-8565-565656565651','TR-A','Transfer A','unit'),
('56565656-5656-4565-8565-565656565682','56565656-5656-4565-8565-565656565652','TR-B','Transfer B','unit');
insert into public.profiles(id,organization_id,role) values
('99999999-9999-4999-8999-999999999991','56565656-5656-4565-8565-565656565651','admin'),
('99999999-9999-4999-8999-999999999992','56565656-5656-4565-8565-565656565652','admin');
insert into public.inventory_balances(organization_id,warehouse_id,product_id,quantity) values
('56565656-5656-4565-8565-565656565651','56565656-5656-4565-8565-565656565671','56565656-5656-4565-8565-565656565681',10),
('56565656-5656-4565-8565-565656565652','56565656-5656-4565-8565-565656565673','56565656-5656-4565-8565-565656565682',10);
set local role authenticated;
set local request.jwt.claim.sub='99999999-9999-4999-8999-999999999991';
select lives_ok($$select * from public.transfer_inventory('56565656-5656-4565-8565-565656565671','56565656-5656-4565-8565-565656565672','transfer-adversarial-01',jsonb_build_array(jsonb_build_object('product_id','56565656-5656-4565-8565-565656565681','quantity',2)))$$,'valid transfer succeeds');
select is((select quantity from public.inventory_balances where warehouse_id='56565656-5656-4565-8565-565656565671' and product_id='56565656-5656-4565-8565-565656565681'),8,'source decremented');
select is((select quantity from public.inventory_balances where warehouse_id='56565656-5656-4565-8565-565656565672' and product_id='56565656-5656-4565-8565-565656565681'),2,'destination incremented');
select lives_ok($$select * from public.transfer_inventory('56565656-5656-4565-8565-565656565671','56565656-5656-4565-8565-565656565672','transfer-adversarial-01',jsonb_build_array(jsonb_build_object('product_id','56565656-5656-4565-8565-565656565681','quantity',2)))$$,'same-key same-payload replay succeeds');
select throws_ok($$select * from public.transfer_inventory('56565656-5656-4565-8565-565656565671','56565656-5656-4565-8565-565656565672','transfer-adversarial-01',jsonb_build_array(jsonb_build_object('product_id','56565656-5656-4565-8565-565656565681','quantity',3)))$$,'40001','idempotency key payload conflict','same-key different quantity is rejected');
select throws_ok($$select * from public.transfer_inventory('56565656-5656-4565-8565-565656565673','56565656-5656-4565-8565-565656565674','transfer-cross-tenant-01',jsonb_build_array(jsonb_build_object('product_id','56565656-5656-4565-8565-565656565682','quantity',1)))$$,'P0002','source warehouse not found','cross-tenant warehouse is rejected');
select throws_ok($$select * from public.transfer_inventory('56565656-5656-4565-8565-565656565671','56565656-5656-4565-8565-565656565672','short-stock-01',jsonb_build_array(jsonb_build_object('product_id','56565656-5656-4565-8565-565656565681','quantity',99)))$$,'22003','insufficient inventory for transfer','insufficient stock rejected');
select throws_ok($$select * from public.transfer_inventory('56565656-5656-4565-8565-565656565671','56565656-5656-4565-8565-565656565672','bad-quantity-01',jsonb_build_array(jsonb_build_object('product_id','56565656-5656-4565-8565-565656565681','quantity',0)))$$,'22023','invalid transfer quantity','zero quantity rejected');
select throws_ok($$select * from public.transfer_inventory('56565656-5656-4565-8565-565656565671','56565656-5656-4565-8565-565656565672','duplicate-line-01',jsonb_build_array(jsonb_build_object('product_id','56565656-5656-4565-8565-565656565681','quantity',1),jsonb_build_object('product_id','56565656-5656-4565-8565-565656565681','quantity',1)))$$,'22023','duplicate product line','duplicate product rejected');
select is((select count(*) from public.inventory_movements where source_type='inventory_transfer'),2::bigint,'audit movements only from one committed transfer');
select is((select count(*) from public.outbox_events where aggregate_type='inventory_transfer'),1::bigint,'one outbox event for one committed transfer');
select * from finish(); rollback;
