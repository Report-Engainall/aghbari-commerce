begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users(id,email) values ('11111111-1111-4111-8111-111111111111','storage-authz@test.local');
insert into public.organizations(id,name) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Storage Authz Tenant');
insert into public.customers(id,organization_id,name,tier) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Storage Authz Customer','wholesale');
insert into public.profiles(id,organization_id,customer_id,role) values ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01','admin');
insert into public.products(id,organization_id,sku,name,unit,status) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','AUTHZ-1','Authz Product','كرتون','active');

set local role authenticated;
select set_config('request.jwt.claims',json_build_object('role','authenticated','sub','11111111-1111-4111-8111-111111111111')::text,false);
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);

select is(auth.uid(),'11111111-1111-4111-8111-111111111111'::uuid,'authenticated auth.uid resolves');
select is(public.storage_current_user_id(),'11111111-1111-4111-8111-111111111111'::uuid,'storage helper resolves under authenticated role');
select is(public.storage_current_organization_id(),'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,'organization helper resolves under authenticated role');
select ok(public.storage_is_staff(),'staff helper resolves under authenticated role');
select is((select count(*) from public.products where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11'),1::bigint,'product is visible to authenticated policy context');
select is((select count(*) from storage.objects where false),0::bigint,'storage relation is reachable under authenticated role');
select lives_ok($$insert into storage.objects(bucket_id,name,owner_id,metadata) values ('product-media','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa41.webp','11111111-1111-4111-8111-111111111111','{"mimetype":"image/webp","size":2048}'::jsonb)$$,'Storage insert policy evaluates under authenticated role');
select is((select count(*) from storage.objects where bucket_id='product-media' and name like 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/%'),1::bigint,'authenticated policy can read its inserted object');

select * from finish();
rollback;
