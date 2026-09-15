begin;
create extension if not exists pgtap;
select plan(9);

-- Contract A: REAL tenant isolation. Mutate the real tenant-context function inside this transaction.
insert into auth.users(id,email) values ('11111111-1111-4111-8111-111111111111','f31-a@test.local');
insert into public.organizations(id,name) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','F31 A'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','F31 B');
insert into public.profiles(id,organization_id,role) values
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','admin');
insert into public.products(id,organization_id,sku,name,unit,status) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','F31-A','F31 A','unit','active'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','F31-B','F31 B','unit','active');
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"role":"authenticated","sub":"11111111-1111-4111-8111-111111111111"}',true);
select is((select count(*) from public.products where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11'),1::bigint,'F31-A real tenant baseline passes');
do $do$
begin
  create or replace function public.current_organization_id() returns uuid language sql stable security definer set search_path=public as $fn$select 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid$fn$;
end $do$;
select is((select count(*) from public.products where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11'),1::bigint,'F31-A injected cross-tenant defect MUST fail');
create or replace function public.current_organization_id() returns uuid language sql stable security definer set search_path=public as $fn$select organization_id from public.profiles where id = auth.uid()$fn$;
select is((select count(*) from public.products where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11'),1::bigint,'F31-A restored tenant isolation passes');

-- Contract B: REAL inventory invariant. Remove the real check constraint, inject a negative balance, assert the invariant detects it, then restore the constraint.
insert into public.branches(id,organization_id,name) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa02','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','F31 Branch');
insert into public.warehouses(id,organization_id,branch_id,name) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa03','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa02','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','F31 Warehouse');
select is((select count(*) from public.inventory_balances where quantity<0),0::bigint,'F31-B real inventory baseline passes');
do $do$
declare c text;
begin
  select conname into c from pg_constraint where conrelid='public.inventory_balances'::regclass and pg_get_constraintdef(oid) like 'CHECK (quantity >= 0)%' limit 1;
  if c is null then raise exception 'inventory quantity check constraint not found'; end if;
  execute format('alter table public.inventory_balances drop constraint %I',c);
end $do$;
insert into public.inventory_balances(organization_id,warehouse_id,product_id,quantity) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa03','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11',-1);
select is((select count(*) from public.inventory_balances where quantity<0),0::bigint,'F31-B injected negative inventory MUST fail');
delete from public.inventory_balances where warehouse_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa03' and product_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11';
alter table public.inventory_balances add constraint inventory_balances_quantity_check_f31 check(quantity>=0);
select is((select count(*) from public.inventory_balances where quantity<0),0::bigint,'F31-B restored inventory invariant passes');

-- Contract C: REAL storage authorization. Add a permissive SELECT defect, assert the real boundary detects it, then remove the defect.
set local role service_role;
insert into storage.objects(bucket_id,name,owner_id,metadata) values
 ('product-media','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa41.webp','11111111-1111-4111-8111-111111111111','{"mimetype":"image/webp","size":1024}'::jsonb),
 ('product-media','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2.webp','22222222-2222-4222-8222-222222222222','{"mimetype":"image/webp","size":1024}'::jsonb);
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"role":"authenticated","sub":"11111111-1111-4111-8111-111111111111"}',true);
select is((select count(*) from storage.objects where bucket_id='product-media'),1::bigint,'F31-C real storage baseline passes');
create policy f31_storage_defect on storage.objects for select to authenticated using(bucket_id='product-media');
select is((select count(*) from storage.objects where bucket_id='product-media'),1::bigint,'F31-C injected permissive storage defect MUST fail');
drop policy f31_storage_defect on storage.objects;
select is((select count(*) from storage.objects where bucket_id='product-media'),1::bigint,'F31-C restored storage authorization passes');

select * from finish();
rollback;
