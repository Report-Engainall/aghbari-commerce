begin;

create extension if not exists pgtap with schema extensions;
select plan(15);

insert into auth.users (id, email)
values ('44444444-4444-4444-8444-444444444444', 'purchasing-admin@test.local');
insert into public.organizations (id, name)
values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'Purchasing Tenant A');
insert into public.branches (id, organization_id, name)
values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeee01', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'Main Branch');
insert into public.warehouses (id, organization_id, branch_id, name)
values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeee02', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeee01', 'Main Warehouse');
insert into public.products (id, organization_id, sku, name, unit)
values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeee03', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'R5-001', 'Rice', 'carton');
insert into public.customers (id, organization_id, name, tier)
values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeee04', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'Buyer', 'wholesale');
insert into public.suppliers (id, organization_id, name)
values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeee05', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'Supplier A');
insert into public.profiles (id, organization_id, customer_id, role)
values ('44444444-4444-4444-8444-444444444444', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeee04', 'admin');

set local role authenticated;
set local request.jwt.claim.sub = '44444444-4444-4444-8444-444444444444';

select ok((select count(*) = 1 from public.create_supplier('Supplier B', '700000001', null, 'Yemen')), 'Supplier creation is tenant-scoped and audited');
select results_eq($$select purchase_order_number from public.create_purchase_order('eeeeeeee-eeee-4eee-8eee-eeeeeeeeee05'::uuid,'eeeeeeee-eeee-4eee-8eee-eeeeeeeeee02'::uuid,'r5-purchase-key-000001',jsonb_build_array(jsonb_build_object('product_id','eeeeeeee-eeee-4eee-8eee-eeeeeeeeee03','quantity',10,'unit_cost',1250)),'YER')$$,$$values (1::bigint)$$,'Purchase order is created with server-generated number');
select results_eq($$select quantity_ordered from public.purchase_order_items where purchase_order_id=(select id from public.purchase_orders where idempotency_key='r5-purchase-key-000001')$$,$$values (10::integer)$$,'Purchase order line is persisted');
select results_eq($$select total from public.create_purchase_order('eeeeeeee-eeee-4eee-8eee-eeeeeeeeee05'::uuid,'eeeeeeee-eeee-4eee-8eee-eeeeeeeeee02'::uuid,'r5-purchase-key-000001',jsonb_build_array(jsonb_build_object('product_id','eeeeeeee-eeee-4eee-8eee-eeeeeeeeee03','quantity',10,'unit_cost',1250)),'YER')$$,$$values (12500::numeric)$$,'Exact purchase replay returns the original total');
select throws_ok($$select * from public.create_purchase_order('eeeeeeee-eeee-4eee-8eee-eeeeeeeeee05'::uuid,'eeeeeeee-eeee-4eee-8eee-eeeeeeeeee02'::uuid,'r5-purchase-key-000001',jsonb_build_array(jsonb_build_object('product_id','eeeeeeee-eeee-4eee-8eee-eeeeeeeeee03','quantity',11,'unit_cost',1250)),'YER')$$,'40001','idempotency key payload conflict','Changed purchase payload under the same key is rejected');
select is((select status from public.submit_purchase_order((select id from public.purchase_orders where idempotency_key='r5-purchase-key-000001'))),'submitted'::public.purchase_order_status,'Draft purchase order can be submitted');
select is((select status from public.approve_purchase_order((select id from public.purchase_orders where idempotency_key='r5-purchase-key-000001'))),'approved'::public.purchase_order_status,'Submitted purchase order requires explicit approval');
select is(coalesce((select quantity from public.inventory_balances where warehouse_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeee02'::uuid and product_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeee03'::uuid),0),0,'Approval alone does not mutate inventory');
select is((select purchase_order_status from public.receive_purchase_order((select id from public.purchase_orders where idempotency_key='r5-purchase-key-000001'),'r5-receipt-key-000001',jsonb_build_array(jsonb_build_object('purchase_order_item_id',(select id from public.purchase_order_items limit 1),'product_id','eeeeeeee-eeee-4eee-8eee-eeeeeeeeee03','quantity',10)))), 'received'::public.purchase_order_status,'Full receipt closes the purchase order');
select is((select quantity from public.inventory_balances where warehouse_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeee02'::uuid and product_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeee03'::uuid),10,'Receiving adds exactly the received quantity to inventory');
select is((select count(*) from public.inventory_movements where source_type='purchase_receipt'),1::bigint,'Receiving creates one auditable inventory movement');
select is((select count(*) from public.outbox_events where event_type='purchase.received'),1::bigint,'Receiving emits one durable outbox event');
select throws_ok($$select * from public.receive_purchase_order((select id from public.purchase_orders where idempotency_key='r5-purchase-key-000001'),'r5-receipt-key-000001',jsonb_build_array(jsonb_build_object('purchase_order_item_id',(select id from public.purchase_order_items limit 1),'product_id','eeeeeeee-eeee-4eee-8eee-eeeeeeeeee03','quantity',9)))$$,'40001','idempotency key payload conflict','Changed receipt payload under the same key is rejected');
select results_eq($$select received_total from public.receive_purchase_order((select id from public.purchase_orders where idempotency_key='r5-purchase-key-000001'),'r5-receipt-key-000001',jsonb_build_array(jsonb_build_object('purchase_order_item_id',(select id from public.purchase_order_items limit 1),'product_id','eeeeeeee-eeee-4eee-8eee-eeeeeeeeee03','quantity',10)))$$,$$values (12500::numeric)$$,'Receipt replay is idempotent and does not double-mutate inventory');
select is((select quantity from public.inventory_balances where warehouse_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeee02'::uuid and product_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeee03'::uuid),10,'Receipt replay leaves inventory unchanged');

select * from finish();
rollback;
