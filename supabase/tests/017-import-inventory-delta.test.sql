begin;

create extension if not exists pgtap with schema extensions;
select plan(6);

create temp table fixture as select gen_random_uuid() org_id, gen_random_uuid() admin_id, gen_random_uuid() branch_id, gen_random_uuid() warehouse_id;
grant select on fixture to authenticated;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,created_at,updated_at)
select admin_id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated','import-delta@fixture.invalid','x',now(),now() from fixture;
insert into public.organizations(id,name,is_active) select org_id,'Import Delta Tenant',true from fixture;
insert into public.profiles(id,organization_id,role) select admin_id,org_id,'admin'::user_role from fixture;
insert into public.branches(id,organization_id,name,is_active) select branch_id,org_id,'Import Delta Branch',true from fixture;
insert into public.warehouses(id,organization_id,branch_id,name,is_active) select warehouse_id,org_id,branch_id,'Import Delta Warehouse',true from fixture;

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub',(select admin_id::text from fixture),true);

select is((select public.commit_product_import(public.stage_product_import('one.xlsx','delta-fp-001','[{"sku":"DELTA-TEST","name":"Delta Test","unit":"unit","category":"Delta","quantity":4,"prices":{"retail":10,"wholesale":9,"distributor":8}}]'::jsonb),(select warehouse_id from fixture))).inventory_changed,1,'First import records one inventory change');
select is((select quantity from public.inventory_balances where organization_id=(select org_id from fixture) and warehouse_id=(select warehouse_id from fixture)),4,'First import sets inventory to four');
select is((select delta from public.inventory_movements where organization_id=(select org_id from fixture) order by id desc limit 1),4,'First import records exact delta of four');

select is((select public.commit_product_import(public.stage_product_import('two.xlsx','delta-fp-002','[{"sku":"DELTA-TEST","name":"Delta Test","unit":"unit","category":"Delta","quantity":7,"prices":{"retail":10,"wholesale":9,"distributor":8}}]'::jsonb),(select warehouse_id from fixture))).inventory_changed,1,'Second import records one inventory change');
select is((select quantity from public.inventory_balances where organization_id=(select org_id from fixture) and warehouse_id=(select warehouse_id from fixture)),7,'Second import sets inventory to seven');
select is((select delta from public.inventory_movements where organization_id=(select org_id from fixture) order by id desc limit 1),3,'Second import records exact delta of three');

select * from finish();
rollback;
