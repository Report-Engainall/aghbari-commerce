begin;
create extension if not exists pgtap;
select plan(16);

insert into auth.users(id,email) values ('11111111-1111-4111-8111-111111111111','ship-return@test.local');
insert into public.organizations(id,name) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Shipping Returns A');
insert into public.customers(id,organization_id,name,tier) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Return Customer','wholesale');
insert into public.profiles(id,organization_id,customer_id,role) values ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01','admin');
insert into public.branches(id,organization_id,name) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa02','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Main');
insert into public.warehouses(id,organization_id,branch_id,name) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa03','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa02','Main WH');
insert into public.products(id,organization_id,sku,name,unit,status) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','SR-1','Returnable Product','unit','active');
insert into public.orders(id,organization_id,customer_id,warehouse_id,status,currency,subtotal,total,idempotency_key,created_by) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa04','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa03','completed','YER',200,200,'f31-sr-order-001','11111111-1111-4111-8111-111111111111');
insert into public.order_items(id,organization_id,order_id,product_id,quantity,unit_price,pricing_tier) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa05','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa04','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11',2,100,'wholesale');
insert into public.inventory_balances(organization_id,warehouse_id,product_id,quantity) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa03','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11',0);

select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"role":"authenticated","sub":"11111111-1111-4111-8111-111111111111"}',true);

select ok((select status from public.create_shipment('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa04','Driver A','TRK-001'))='pending','F21 create shipment starts pending');
select ok((select status from public.transition_shipment((select id from public.shipments where order_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa04'),'packed'))='packed','F21 pending to packed passes');
select ok((select status from public.transition_shipment((select id from public.shipments where order_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa04'),'shipped','Driver B','TRK-002'))='shipped','F21 packed to shipped records driver and tracking');
select ok((select status from public.transition_shipment((select id from public.shipments where order_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa04'),'delivered'))='delivered','F21 shipped to delivered passes');
select throws_ok($$select public.transition_shipment((select id from public.shipments where order_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa04'),'delivered')$$,'40001',null,'F21 duplicate transition is rejected');
select throws_ok($$select public.transition_shipment((select id from public.shipments where order_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa04'),'packed')$$,'22023',null,'F21 reverse transition is rejected');
select ok((select count(*) from public.shipment_events where shipment_id=(select id from public.shipments where order_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa04'))=4,'F21 shipment events capture every transition');
select ok((select count(*) from public.audit_events where target_type='shipment' and target_id=(select id from public.shipments where order_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa04'))>=4,'F21 shipment transitions are audited');

select ok((select status from public.create_return('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa04','damaged',jsonb_build_array(jsonb_build_object('order_item_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa05','quantity',2))))='requested','F22 return request persists');
select ok((select status from public.review_return((select id from public.returns where order_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa04'),true))='approved','F22 approved return enters receiveable state');
select ok((select status from public.receive_return((select id from public.returns where order_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa04'),'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa03'))='received','F22 receive return restores inventory');
select is((select quantity from public.inventory_balances where warehouse_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa03' and product_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11'),2,'F22 returned quantity is added exactly once');
select throws_ok($$select public.receive_return((select id from public.returns where order_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa04'),'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa03')$$,'22023',null,'F22 duplicate receive is rejected');
update public.profiles set role='finance' where id='11111111-1111-4111-8111-111111111111';
select ok((select status from public.post_return_refund((select id from public.returns where order_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa04'),'other',null))='refunded','F22 refund posts after receipt');
select is((select count(*) from public.operational_ledger_entries where source_type='return_refund' and customer_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01'),1::bigint,'F22 refund creates one customer ledger credit');
select is((select id from public.post_return_refund((select id from public.returns where order_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa04'),'other',null)),(select id from public.return_refunds where return_id=(select id from public.returns where order_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa04')),'F22 refund replay is idempotent');

select * from finish();
rollback;
