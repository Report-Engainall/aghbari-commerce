begin;
create extension if not exists pgtap;
select plan(31);

select ok((select count(*) from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname='user_role' and e.enumlabel in ('owner','admin','employee','sales','warehouse','finance','viewer','customer'))=8,'F10 all required roles exist');
select ok(public.is_staff() is false,'F10 anonymous context is not staff');

insert into auth.users(id,email) values
 ('11111111-1111-4111-8111-111111111111','wave3-a@test.local'),
 ('22222222-2222-4222-8222-222222222222','wave3-b@test.local');
insert into public.organizations(id,name) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Wave3 A'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Wave3 B');
insert into public.customers(id,organization_id,name,tier) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','A Customer','wholesale'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb01','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','B Customer','wholesale');
insert into public.profiles(id,organization_id,customer_id,role) values
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01','admin'),
 ('22222222-2222-4222-8222-222222222222','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb01','customer');

select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"role":"authenticated","sub":"11111111-1111-4111-8111-111111111111"}',true);
select ok(public.current_role()='admin','F10 admin context resolves');
select ok(public.is_staff(),'F10 admin is staff');

insert into public.brands(organization_id,name,slug) values(public.current_organization_id(),'Brand A','brand-a');
insert into public.store_banners(organization_id,title,is_visible) values(public.current_organization_id(),'Banner A',true);
insert into public.store_content(organization_id,slug,title,body,is_published) values(public.current_organization_id(),'home','Home','A',true);
insert into public.customer_segments(organization_id,name) values(public.current_organization_id(),'Wholesale A');
select ok((select count(*) from public.brands where slug='brand-a')=1,'F20 authorized brand mutation persists');
select ok((select count(*) from public.store_banners where title='Banner A')=1,'F20 banner mutation persists');
select ok((select count(*) from public.store_content where slug='home')=1,'F20 content mutation persists');
select ok((select count(*) from public.customer_segments where name='Wholesale A')=1,'F20 segment mutation persists');

select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
select set_config('request.jwt.claims','{"role":"authenticated","sub":"22222222-2222-4222-8222-222222222222"}',true);
select ok((select count(*) from public.brands where organization_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')=0,'F20 tenant B cannot read tenant A brand');
select results_eq($$with changed as (update public.brands set name='HACK' where organization_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' returning 1) select count(*) from changed$$,$$values(0::bigint)$$,'F20 tenant B cannot mutate tenant A brand');

select has_table('public','shipments','F21 shipment persistence exists');
select has_function('public','create_shipment','F21 create shipment authority exists');
select has_function('public','transition_shipment','F21 transition authority exists');
select has_table('public','shipment_events','F21 transition audit persistence exists');

select has_table('public','returns','F22 return persistence exists');
select has_table('public','return_items','F22 return items persist');
select has_table('public','return_refunds','F22 refund persistence exists');
select has_table('public','operational_ledger_entries','F22 ledger persistence exists');
select has_function('public','create_return','F22 request authority exists');
select has_function('public','review_return','F22 review authority exists');
select has_function('public','receive_return','F22 receive authority exists');
select has_function('public','post_return_refund','F22 refund authority exists');

select has_function('public','create_order','F18 create_order exists');
select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='create_order' and pg_get_function_arguments(p.oid) ilike '%price%'),'F18 create_order has no client price parameter');
select ok(pg_get_functiondef((select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='create_order' limit 1)) ilike '%product_prices%','F18 create_order reads server-side product prices');
select ok(pg_get_functiondef((select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='create_order' limit 1)) ilike '%v_tier%','F18 create_order resolves customer tier server-side');

select has_column('public','audit_events','actor_id','F28 actor evidence');
select has_column('public','audit_events','organization_id','F28 tenant evidence');
select has_column('public','audit_events','target_id','F28 entity evidence');
select has_column('public','audit_events','result','F28 result evidence');
select has_column('public','audit_events','created_at','F28 timestamp evidence');

select * from finish();
rollback;
