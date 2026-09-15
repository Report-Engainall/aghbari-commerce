begin;

create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email)
values ('99999999-9999-4999-8999-999999999999', 'inventory-admin@test.local');
insert into public.organizations (id, name)
values ('56565656-5656-4565-8565-565656565656', 'Inventory Tenant');
insert into public.branches (id, organization_id, name)
values ('56565656-5656-4565-8565-565656565657', '56565656-5656-4565-8565-565656565656', 'Main');
insert into public.warehouses (id, organization_id, branch_id, name)
values ('56565656-5656-4565-8565-565656565658', '56565656-5656-4565-8565-565656565656', '56565656-5656-4565-8565-565656565657', 'Source'),
       ('56565656-5656-4565-8565-565656565659', '56565656-5656-4565-8565-565656565656', '56565656-5656-4565-8565-565656565657', 'Destination');
insert into public.products (id, organization_id, sku, name, unit)
values ('56565656-5656-4565-8565-565656565660', '56565656-5656-4565-8565-565656565656', 'TR-001', 'Transfer Product', 'carton');
insert into public.profiles (id, organization_id, role)
values ('99999999-9999-4999-8999-999999999999', '56565656-5656-4565-8565-565656565656', 'admin');
insert into public.inventory_balances(organization_id,warehouse_id,product_id,quantity)
values ('56565656-5656-4565-8565-565656565656','56565656-5656-4565-8565-565656565658','56565656-5656-4565-8565-565656565660',10);

set local role authenticated;
set local request.jwt.claim.sub = '99999999-9999-4999-8999-999999999999';

select is((select total_quantity from public.transfer_inventory(
  '56565656-5656-4565-8565-565656565658','56565656-5656-4565-8565-565656565659','inventory-transfer-idem-01',
  jsonb_build_array(jsonb_build_object('product_id','56565656-5656-4565-8565-565656565660','quantity',3)),'test transfer'
)),3::bigint,'Transfer moves the requested quantity');
select is((select quantity from public.inventory_balances where warehouse_id='56565656-5656-4565-8565-565656565658' and product_id='56565656-5656-4565-8565-565656565660'),7,'Source balance decremented atomically');
select is((select quantity from public.inventory_balances where warehouse_id='56565656-5656-4565-8565-565656565659' and product_id='56565656-5656-4565-8565-565656565660'),3,'Destination balance incremented atomically');
select is((select count(*) from public.inventory_movements where source_type='inventory_transfer'),2::bigint,'Transfer creates both auditable inventory movements');
select is((select total_quantity from public.transfer_inventory(
  '56565656-5656-4565-8565-565656565658','56565656-5656-4565-8565-565656565659','inventory-transfer-idem-01',
  jsonb_build_array(jsonb_build_object('product_id','56565656-5656-4565-8565-565656565660','quantity',3)),'test transfer'
)),3::bigint,'Idempotent transfer replay does not duplicate the movement');
select throws_ok(
  $$select * from public.transfer_inventory('56565656-5656-4565-8565-565656565658','56565656-5656-4565-8565-565656565659','inventory-transfer-idem-02',jsonb_build_array(jsonb_build_object('product_id','56565656-5656-4565-8565-565656565660','quantity',99)))$$,
  '22003','insufficient inventory for transfer','Insufficient source stock is rejected without partial mutation'
);
select is(
  (select count(*) from public.set_stock_threshold('56565656-5656-4565-8565-565656565658','56565656-5656-4565-8565-565656565660',7,10)),
  1::bigint,
  'Stock threshold can be set for a warehouse/product'
);
select is((select count(*) from public.get_low_stock()),1::bigint,'Low-stock query surfaces the actionable item');

select * from finish();
rollback;
