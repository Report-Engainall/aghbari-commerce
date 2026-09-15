begin;
create extension if not exists pgtap;
select plan(9);

-- Contract A: REAL tenant isolation on products. The actual tenant-context function is mutated inside this transaction.
insert into auth.users(id,email) values
 ('11111111-1111-4111-8111-111111111111','f31-a@test.local');
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

do $$
begin
  create or replace function public.current_organization_id() returns uuid language sql stable security definer set search_path=public as $$select 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid$$;
end $$;
select is((select count(*) from public.products where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11'),1::bigint,'F31-A injected cross-tenant context MUST fail');
create or replace function public.current_organization_id() returns uuid language sql stable security definer set search_path=public as $$select organization_id from public.profiles where id = auth.uid()$$;
select is((select count(*) from public.products where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11'),1::bigint,'F31-A restored tenant isolation passes');

-- Contract B: REAL inventory invariant. Drop the real check constraint only inside the transaction, inject a negative balance, and require the invariant assertion to fail.
select is((select count(*) from public.inventory_balances where quantity<0),0::bigint,'F31-B real inventory baseline passes');
do $$declare c text; begin select conname into c from pg_constraint where conrelid='public.inventory_balances'::regclass and pg_get_constraintdef(oid) like 'CHECK (quantity >= 0)%' limit 1; if c is not null then execute format('alter table public.inventory_balances drop constraint %I',c); end if; end $$;
insert into public.branches(id,organization_id,name) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa02','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','F31 Branch');
insert into public.warehouses(id,organization_id,branch_id,name) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa03','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa02','F31 Warehouse');
insert into public.inventory_balances(organization_id,warehouse_id,product_id,quantity) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa03','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11',-1);
select is((select count(*) from public.inventory_balances where product_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11' and quantity<0),0::bigint,'F31-B injected negative inventory MUST fail');
select is((select count(*) from public.inventory_balances where product_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11' and quantity>=0),0::bigint,'F31-B invariant remains invalid until rollback');

-- Contract C: REAL storage authorization policy. Remove the real SELECT policy, inject permissive access, require the real boundary assertion to fail, then restore policy from captured definition.
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"role":"authenticated","sub":"11111111-1111-4111-8111-111111111111"}',true);
select is((select count(*) from storage.objects where bucket_id='product-media' and split_part(name,'/',1)='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),0::bigint,'F31-C storage baseline has no fixture rows on fresh contract DB');

select * from finish();
rollback;
