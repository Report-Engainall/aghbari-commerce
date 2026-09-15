begin;

create extension if not exists pgtap with schema extensions;
select plan(5);

insert into auth.users (id, email) values ('21212121-2121-4121-8121-212121212121', 'stock-count-concurrency@test.local');
insert into public.organizations (id, name) values ('22222222-2222-4222-8222-222222222222', 'Stock Count Concurrency Tenant');
insert into public.branches (id, organization_id, name) values ('23232323-2323-4232-8232-232323232323', '22222222-2222-4222-8222-222222222222', 'Main');
insert into public.warehouses (id, organization_id, branch_id, name) values ('24242424-2424-4242-8242-242424242424', '22222222-2222-4222-8222-222222222222', '23232323-2323-4232-8232-232323232323', 'Warehouse');
insert into public.products (id, organization_id, sku, name, unit) values ('25252525-2525-4252-8252-252525252525', '22222222-2222-4222-8222-222222222222', 'COUNT-001', 'Count Product', 'carton');
insert into public.inventory_balances(organization_id, warehouse_id, product_id, quantity)
values ('22222222-2222-4222-8222-222222222222','24242424-2424-4242-8242-242424242424','25252525-2525-4252-8252-252525252525',10);
insert into public.profiles(id, organization_id, role)
values ('21212121-2121-4121-8121-212121212121','22222222-2222-4222-8222-222222222222','warehouse');

set local role authenticated;
set local request.jwt.claim.sub = '21212121-2121-4121-8121-212121212121';

select is(
  (select id from public.start_stock_count('24242424-2424-4242-8242-242424242424','count-key-001')),
  (select id from public.stock_count_sessions where organization_id='22222222-2222-4222-8222-222222222222' and status='open'),
  'Starting a stock count creates the single open session for the warehouse'
);

select throws_ok(
  $$select public.start_stock_count('24242424-2424-4242-8242-242424242424','count-key-002')$$,
  '55006','an open stock count already exists for this warehouse',
  'A second open stock count for the same warehouse is rejected'
);

select public.set_stock_count_line(
  (select id from public.stock_count_sessions where organization_id='22222222-2222-4222-8222-222222222222' and status='open'),
  '25252525-2525-4252-8252-252525252525',
  12
);

select public.complete_stock_count(
  (select id from public.stock_count_sessions where organization_id='22222222-2222-4222-8222-222222222222' and status='open')
);

select throws_ok(
  $$select public.set_stock_count_line((select id from public.stock_count_sessions where organization_id='22222222-2222-4222-8222-222222222222' and status='completed'),'25252525-2525-4252-8252-252525252525',13)$$,
  '22023','stock count is not open',
  'Completed stock counts cannot be modified'
);

select is(
  (select quantity from public.inventory_balances where warehouse_id='24242424-2424-4242-8242-242424242424' and product_id='25252525-2525-4252-8252-252525252525'),
  12,
  'Completing the count reconciles inventory to the counted quantity'
);

select * from finish();
rollback;
