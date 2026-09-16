begin;

create extension if not exists pgtap with schema extensions;
select plan(6);

insert into auth.users(id,email) values
  ('41414141-4141-4414-8414-414141414141','staff-a@test.local'),
  ('42424242-4242-4424-8424-424242424242','staff-b@test.local');
insert into public.organizations(id,name) values
  ('41414141-4141-4414-8414-414141414142','Staff Tenant A'),
  ('42424242-4242-4424-8424-424242424243','Staff Tenant B');
insert into public.customers(id,organization_id,name,tier) values
  ('41414141-4141-4414-8414-414141414144','41414141-4141-4414-8414-414141414142','Customer A','wholesale'),
  ('42424242-4242-4424-8424-424242424245','42424242-4242-4424-8424-424242424243','Customer B','wholesale');
insert into public.profiles(id,organization_id,customer_id,role) values
  ('41414141-4141-4414-8414-414141414141','41414141-4141-4414-8414-414141414142','41414141-4141-4414-8414-414141414144','admin'),
  ('42424242-4242-4424-8424-424242424242','42424242-4242-4424-8424-424242424243','42424242-4242-4424-8424-424242424245','admin');
insert into public.branches(id,organization_id,name) values
  ('41414141-4141-4414-8414-414141414146','41414141-4141-4414-8414-414141414142','A Branch'),
  ('42424242-4242-4424-8424-424242424247','42424242-4242-4424-8424-424242424243','B Branch');
insert into public.warehouses(id,organization_id,branch_id,name) values
  ('41414141-4141-4414-8414-414141414148','41414141-4141-4414-8414-414141414142','41414141-4141-4414-8414-414141414146','A Warehouse'),
  ('42424242-4242-4424-8424-424242424249','42424242-4242-4424-8424-424242424243','42424242-4242-4424-8424-424242424247','B Warehouse');
insert into public.products(id,organization_id,sku,name,unit,status) values
  ('41414141-4141-4414-8414-414141414150','41414141-4141-4414-8414-414141414142','A-001','A Product','carton','active'),
  ('42424242-4242-4424-8424-424242424251','42424242-4242-4424-8424-424242424243','B-001','B Product','carton','active');
insert into public.inventory_balances(organization_id,warehouse_id,product_id,quantity) values
  ('41414141-4141-4414-8414-414141414142','41414141-4141-4414-8414-414141414148','41414141-4141-4414-8414-414141414150',10),
  ('42424242-4242-4424-8424-424242424243','42424242-4242-4424-8424-424242424249','42424242-4242-4424-8424-424242424251',20);
insert into public.price_lists(organization_id,tier,name,currency) values
  ('41414141-4141-4414-8414-414141414142','wholesale','A Wholesale','YER'),
  ('42424242-4242-4424-8424-424242424243','wholesale','B Wholesale','YER');

set local role authenticated;
set local request.jwt.claim.sub='41414141-4141-4414-8414-414141414141';

select throws_ok($$select public.upsert_product('42424242-4242-4424-8424-424242424251','X-001','Cross Tenant','carton',null,null,'active')$$,'P0002',null,'Tenant A cannot mutate Tenant B product');
select throws_ok($$select public.create_category('Invalid Parent','invalid-parent','42424242-4242-4424-8424-424242424252')$$,'22023',null,'Tenant A cannot use Tenant B category as parent');
select throws_ok($$select public.adjust_inventory('42424242-4242-4424-8424-424242424249','41414141-4141-4414-8414-414141414150',1,'cross tenant')$$,'42501',null,'Tenant A cannot mutate Tenant B warehouse');
select throws_ok($$select public.set_product_price('42424242-4242-4424-8424-424242424251','wholesale',10,'YER')$$,'P0002',null,'Tenant A cannot price Tenant B product');

set local request.jwt.claim.sub='42424242-4242-4424-8424-424242424242';
select throws_ok($$select public.upsert_product('41414141-4141-4414-8414-414141414150','B-X','Forbidden','carton',null,null,'active')$$,'P0002',null,'Tenant B cannot mutate Tenant A product');

select * from finish();
rollback;
