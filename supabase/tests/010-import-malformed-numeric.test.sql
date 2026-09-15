begin;

create extension if not exists pgtap with schema extensions;
select plan(4);

insert into auth.users (id, email)
values ('77777777-7777-4777-8777-777777777777', 'import-numeric@test.local');
insert into public.organizations (id, name)
values ('13131313-1313-4131-8131-131313131313', 'Import Numeric Tenant');
insert into public.profiles (id, organization_id, role)
values ('77777777-7777-4777-8777-777777777777', '13131313-1313-4131-8131-131313131313', 'admin');

set local role authenticated;
set local request.jwt.claim.sub = '77777777-7777-4777-8777-777777777777';

select lives_ok(
  $$select public.stage_product_import(
    'malformed-numeric.xlsx',
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    jsonb_build_array(jsonb_build_object(
      'sku','NUM-001',
      'name','Malformed Numeric Product',
      'unit','carton',
      'category','General',
      'quantity','not-a-number',
      'prices',jsonb_build_object('retail','oops','wholesale','100.00','distributor','200.00')
    ))
  )$$,
  'Malformed numeric cells must not abort the import stage'
);

select is(
  (select invalid_rows from public.import_jobs where source_fingerprint='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
  1,
  'Malformed numeric row is recorded as invalid'
);

select ok(
  exists (
    select 1
    from public.import_rows ir
    where ir.import_job_id=(select id from public.import_jobs where source_fingerprint='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
      and ir.status='invalid'
      and ir.diagnostics @> jsonb_build_array(jsonb_build_object('field','quantity','message','Quantity must be a non-negative integer not exceeding 10000'))
  ),
  'Quantity parsing failure becomes a row diagnostic'
);

select ok(
  exists (
    select 1
    from public.import_rows ir
    where ir.import_job_id=(select id from public.import_jobs where source_fingerprint='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
      and ir.diagnostics @> jsonb_build_array(jsonb_build_object('field','price.retail','message','Retail price must be a finite non-negative amount with at most 2 decimals within the safe client range'))
  ),
  'Price parsing failure becomes a row diagnostic'
);

select * from finish();
rollback;
