begin;

create extension if not exists pgtap with schema extensions;
select plan(8);

create temp table fixture as
select
  gen_random_uuid() as org_a,
  gen_random_uuid() as org_b,
  gen_random_uuid() as user_a,
  gen_random_uuid() as user_b,
  gen_random_uuid() as customer_a,
  gen_random_uuid() as customer_b,
  gen_random_uuid() as branch_a,
  gen_random_uuid() as branch_b,
  gen_random_uuid() as warehouse_a,
  gen_random_uuid() as warehouse_b,
  gen_random_uuid() as product_a,
  gen_random_uuid() as product_b;

grant select on fixture to authenticated;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
select user_a, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', 'cart-a@fixture.invalid', 'x', now(), now() from fixture
union all
select user_b, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated', 'cart-b@fixture.invalid', 'x', now(), now() from fixture;

insert into public.organizations (id, name, is_active)
select org_a, 'Cart Tenant A', true from fixture
union all
select org_b, 'Cart Tenant B', true from fixture;

insert into public.customers (id, organization_id, name, tier, is_active)
select customer_a, org_a, 'Cart Customer A', 'retail'::customer_tier, true from fixture
union all
select customer_b, org_b, 'Cart Customer B', 'retail'::customer_tier, true from fixture;

insert into public.profiles (id, organization_id, customer_id, role)
select user_a, org_a, customer_a, 'viewer'::user_role from fixture
union all
select user_b, org_b, customer_b, 'viewer'::user_role from fixture;

insert into public.branches (id, organization_id, name, is_active)
select branch_a, org_a, 'Cart Branch A', true from fixture
union all
select branch_b, org_b, 'Cart Branch B', true from fixture;

insert into public.warehouses (id, organization_id, branch_id, name, is_active)
select warehouse_a, org_a, branch_a, 'Cart Warehouse A', true from fixture
union all
select warehouse_b, org_b, branch_b, 'Cart Warehouse B', true from fixture;

insert into public.products (id, organization_id, sku, name, unit, status)
select product_a, org_a, 'CART-A-1', 'Cart Product A', 'unit', 'active' from fixture
union all
select product_b, org_b, 'CART-B-1', 'Cart Product B', 'unit', 'active' from fixture;

insert into public.inventory_balances (organization_id, warehouse_id, product_id, quantity)
select org_a, warehouse_a, product_a, 20 from fixture
union all
select org_b, warehouse_b, product_b, 30 from fixture;

insert into public.price_lists (organization_id, tier, name, currency)
select org_a, 'retail'::customer_tier, 'Retail A', 'YER' from fixture
union all
select org_b, 'retail'::customer_tier, 'Retail B', 'YER' from fixture;

insert into public.product_prices (organization_id, price_list_id, product_id, amount, valid_from)
select org_a, (select id from public.price_lists where organization_id = org_a and tier = 'retail'), product_a, 100, now() from fixture
union all
select org_b, (select id from public.price_lists where organization_id = org_b and tier = 'retail'), product_b, 200, now() from fixture;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', (select user_a::text from fixture), true);

select ok(public.create_order('cart-boundary-a-0010', (select warehouse_a from fixture), jsonb_build_array(jsonb_build_object('product_id', (select product_a from fixture), 'quantity', 1))) is not null, 'Tenant A can create its own order');

select throws_ok(
  format('select public.set_cart_item(%L, 1)', (select product_b from fixture)),
  'P0001',
  'product unavailable',
  'Tenant A cannot add Tenant B product to cart'
);

select throws_ok(
  format('select public.create_order(%L, %L, %L)', 'cross-tenant-order-0010', (select warehouse_b from fixture), jsonb_build_array(jsonb_build_object('product_id', (select product_b from fixture), 'quantity', 1))),
  '42501',
  'warehouse not available',
  'Tenant A cannot create order against Tenant B warehouse'
);

select set_config('request.jwt.claim.sub', (select user_b::text from fixture), true);

select ok(public.create_order('cart-boundary-b-0010', (select warehouse_b from fixture), jsonb_build_array(jsonb_build_object('product_id', (select product_b from fixture), 'quantity', 1))) is not null, 'Tenant B can create its own order');

select throws_ok(
  format('select public.transition_order(%L, %L)',
    (select o.id from public.orders o join fixture f on o.organization_id = f.org_a order by o.created_at desc limit 1),
    'cancelled'),
  'P0002',
  'order not found',
  'Tenant B cannot transition Tenant A order'
);

select ok(not exists (
  select 1 from public.orders o join fixture f on o.id = (select o2.id from public.orders o2 join fixture f2 on o2.organization_id = f2.org_a order by o2.created_at desc limit 1) and f.org_a = o.organization_id
), 'Tenant B RLS hides Tenant A order');

select set_config('request.jwt.claim.sub', (select user_a::text from fixture), true);

select ok(not exists (
  select 1 from public.orders o join fixture f on o.id = (select o2.id from public.orders o2 join fixture f2 on o2.organization_id = f2.org_b order by o2.created_at desc limit 1) and f.org_b = o.organization_id
), 'Tenant A RLS hides Tenant B order');

select ok(not exists (
  select 1 from public.get_cart() where product_id = (select product_b from fixture)
), 'Tenant A cart cannot contain Tenant B product');

select * from finish();
rollback;
