begin;
create extension if not exists pgtap;
select plan(18);

insert into auth.users(id,email) values
 ('11111111-1111-4111-8111-111111111111','cms-a@test.local'),
 ('22222222-2222-4222-8222-222222222222','cms-b@test.local');
insert into public.organizations(id,name) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','CMS A'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','CMS B');
insert into public.customers(id,organization_id,name,tier) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','CMS A Customer','wholesale'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','CMS B Customer','wholesale');
insert into public.profiles(id,organization_id,customer_id,role) values
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01','admin'),
 ('22222222-2222-4222-8222-222222222222','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','customer');

select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"role":"authenticated","sub":"11111111-1111-4111-8111-111111111111"}',true);

insert into public.client_ui_settings(organization_id,config) values(public.current_organization_id(),'{"showSearch":true}'::jsonb);
update public.client_ui_settings set config='{"showSearch":false}'::jsonb where organization_id=public.current_organization_id();
select is((select config->>'showSearch' from public.client_ui_settings where organization_id=public.current_organization_id()),'false','F20 store settings update persists');

insert into public.categories(organization_id,name,slug) values(public.current_organization_id(),'CMS Category','cms-category');
update public.categories set name='CMS Category Updated' where organization_id=public.current_organization_id() and slug='cms-category';
select is((select name from public.categories where organization_id=public.current_organization_id() and slug='cms-category'),'CMS Category Updated','F20 category update persists');
delete from public.categories where organization_id=public.current_organization_id() and slug='cms-category';
select is((select count(*) from public.categories where organization_id=public.current_organization_id() and slug='cms-category'),0::bigint,'F20 category delete persists');

insert into public.brands(organization_id,name,slug) values(public.current_organization_id(),'CMS Brand','cms-brand');
update public.brands set name='CMS Brand Updated' where organization_id=public.current_organization_id() and slug='cms-brand';
select is((select name from public.brands where organization_id=public.current_organization_id() and slug='cms-brand'),'CMS Brand Updated','F20 brand update persists');
delete from public.brands where organization_id=public.current_organization_id() and slug='cms-brand';
select is((select count(*) from public.brands where organization_id=public.current_organization_id() and slug='cms-brand'),0::bigint,'F20 brand delete persists');

insert into public.store_banners(organization_id,title,is_visible) values(public.current_organization_id(),'CMS Banner',true);
update public.store_banners set title='CMS Banner Updated',is_visible=false where organization_id=public.current_organization_id() and title='CMS Banner';
select is((select count(*) from public.store_banners where organization_id=public.current_organization_id() and title='CMS Banner Updated' and is_visible=false),1::bigint,'F20 banner visibility/update persists');
select is((select count(*) from public.store_banners where organization_id=public.current_organization_id() and title='CMS Banner Updated'),1::bigint,'F20 inactive banner remains persisted but not public');
delete from public.store_banners where organization_id=public.current_organization_id() and title='CMS Banner Updated';
select is((select count(*) from public.store_banners where organization_id=public.current_organization_id() and title='CMS Banner Updated'),0::bigint,'F20 banner delete persists');

insert into public.store_content(organization_id,slug,title,body,is_published) values(public.current_organization_id(),'cms','CMS','Draft',false);
update public.store_content set body='Published',is_published=true where organization_id=public.current_organization_id() and slug='cms';
select is((select body from public.store_content where organization_id=public.current_organization_id() and slug='cms'),'Published','F20 content publish/update persists');

after_delete:
insert into public.customer_segments(organization_id,name) values(public.current_organization_id(),'CMS Segment');
update public.customer_segments set description='Updated' where organization_id=public.current_organization_id() and name='CMS Segment';
select is((select description from public.customer_segments where organization_id=public.current_organization_id() and name='CMS Segment'),'Updated','F20 customer segment update persists');

delete from public.store_content where organization_id=public.current_organization_id() and slug='cms';
delete from public.customer_segments where organization_id=public.current_organization_id() and name='CMS Segment';
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
select set_config('request.jwt.claims','{"role":"authenticated","sub":"22222222-2222-4222-8222-222222222222"}',true);
select is((select count(*) from public.store_content where organization_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),0::bigint,'F20 tenant B cannot read tenant A content');
select * from finish();
rollback;
