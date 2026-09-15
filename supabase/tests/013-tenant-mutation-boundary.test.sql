begin;

create extension if not exists pgtap with schema extensions;
select plan(8);

create temp table fixture as
select
  gen_random_uuid() as org_a,
  gen_random_uuid() as org_b,
  gen_random_uuid() as user_a,
  gen_random_uuid() as admin_a,
  gen_random_uuid() as branch_a,
  gen_random_uuid() as branch_b,
  gen_random_uuid() as warehouse_a,
  gen_random_uuid() as warehouse_b,
  gen_random_uuid() as product_a,
  gen_random_uuid() as product_b,
  gen_random_uuid() as category_a;

grant select on fixture to authenticated;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
select user_a, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', 'tenant-viewer@fixture.invalid', 'x', now(), now()
from fixture
union all
select admin_a, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', 'tenant-admin@fixture.invalid', 'x', now(), now()
from fixture;

insert into public.organizations (id, name, is_active)
select org_a, 'Tenant A', true from fixture
union all
select org_b, 'Tenant B', true from fixture;

insert into public.profiles (id, organization_id, role)
select user_a, org_a, 'viewer'::user_role from fixture
union all
select admin_a, org_a, 'admin'::user_role from fixture;

insert into public.branches (id, organization_id, name, is_active)
select branch_a, org_a, 'Branch A', true from fixture
union all
select branch_b, org_b, 'Branch B', true from fixture;

insert into public.warehouses (id, organization_id, branch_id, name, is_active)
select warehouse_a, org_a, branch_a, 'Warehouse A', true from fixture
union all
select warehouse_b, org_b, branch_b, 'Warehouse B', true from fixture;

insert into public.categories (id, organization_id, name, slug, is_active)
select category_a, org_a, 'Category A', 'category-a', true from fixture;

insert into public.products (id, organization_id, category_id, sku, name, unit, status)
select product_a, org_a, category_a, 'TENANT-A-1', 'Tenant A Product', 'unit', 'active' from fixture
union all
select product_b, org_b, null, 'TENANT-B-1', 'Tenant B Product', 'unit', 'active' from fixture;

insert into public.inventory_balances (organization_id, warehouse_id, product_id, quantity)
select org_a, warehouse_a, product_a, 10 from fixture
union all
select org_b, warehouse_b, product_b, 20 from fixture;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', (select user_a::text from fixture), true);

select throws_ok(
  format('select public.adjust_inventory(%L,%L,-5,%L)', warehouse_b, product_b, 'cross-tenant viewer'),
  '42501',
  'viewer cannot mutate Tenant B inventory'
) from fixture;

select is(
  (select count(*) from public.inventory_balances ib join fixture f on f.warehouse_b = ib.warehouse_id and f.product_b = ib.product_id),
  0::bigint,
  'Tenant A viewer cannot read Tenant B inventory through RLS'
);

select throws_ok(
  format('select public.upsert_product(%L,%L,%L,%L,%L,%L,%L)', product_b, 'TENANT-B-HACK', 'Cross Tenant', 'unit', null, null, 'active'),
  '42501',
  'viewer cannot upsert Tenant B product'
) from fixture;

select throws_ok(
  format('select public.set_product_price(%L,%L,%L,%L)', product_b, 'retail', 1, 'YER'),
  '42501',
  'viewer cannot change Tenant B pricing'
) from fixture;

select set_config('request.jwt.claim.sub', (select admin_a::text from fixture), true);

select throws_ok(
  format('select public.adjust_inventory(%L,%L,-5,%L)', warehouse_b, product_b, 'cross-tenant admin'),
  'P0002',
  'Tenant A admin cannot mutate Tenant B inventory'
) from fixture;

select public.adjust_inventory(warehouse_a, product_a, 1, 'same-tenant admin') from fixture;

select is(
  (select quantity from public.inventory_balances ib join fixture f on f.warehouse_a = ib.warehouse_id and f.product_a = ib.product_id),
  11,
  'Tenant A admin can mutate Tenant A inventory'
);

select is(
  (select count(*) from public.inventory_balances ib join fixture f on f.warehouse_b = ib.warehouse_id and f.product_b = ib.product_id),
  0::bigint,
  'Tenant A admin cannot read Tenant B inventory through RLS'
);

select * from finish();
rollback;
