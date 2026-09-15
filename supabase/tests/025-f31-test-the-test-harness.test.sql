begin;
create extension if not exists pgtap;

select plan(9);

-- Contract A: tenant isolation. Baseline must pass, injected policy defect must fail, rollback restores pass.
create temporary table f31_tenant(id uuid primary key, organization_id uuid not null, value text);
insert into f31_tenant values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','A'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','B');
alter table f31_tenant enable row level security;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"role":"authenticated","sub":"11111111-1111-4111-8111-111111111111"}',true);
create policy f31_tenant_guard on f31_tenant using (organization_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid);
select is((select count(*) from f31_tenant),1::bigint,'F31-A baseline tenant isolation passes');
drop policy f31_tenant_guard on f31_tenant;
select is((select count(*) from f31_tenant),2::bigint,'F31-A injected tenant defect changes observable result');
create policy f31_tenant_guard on f31_tenant using (organization_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid);
select is((select count(*) from f31_tenant),1::bigint,'F31-A restored tenant isolation passes');

-- Contract B: inventory/order invariant. Inject a negative-balance defect; invariant must detect it; restore.
create temporary table f31_inventory(product_id uuid primary key, quantity integer check (quantity >= -100000));
insert into f31_inventory values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11',10);
select is((select count(*) from f31_inventory where quantity >= 0),1::bigint,'F31-B baseline inventory invariant passes');
update f31_inventory set quantity = -1;
select is((select count(*) from f31_inventory where quantity >= 0),0::bigint,'F31-B injected negative inventory is detected');
update f31_inventory set quantity = 10;
select is((select count(*) from f31_inventory where quantity >= 0),1::bigint,'F31-B restored inventory invariant passes');

-- Contract C: storage authorization sensitivity. A tenant/path mismatch must be observable; restore proves rollback.
create temporary table f31_storage(organization_id uuid, owner_id text, name text);
insert into f31_storage values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/p.webp');
select is((select count(*) from f31_storage where organization_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and owner_id='11111111-1111-4111-8111-111111111111'),1::bigint,'F31-C baseline storage authorization condition passes');
update f31_storage set owner_id='22222222-2222-4222-8222-222222222222';
select is((select count(*) from f31_storage where organization_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and owner_id='11111111-1111-4111-8111-111111111111'),0::bigint,'F31-C injected storage owner defect is detected');
update f31_storage set owner_id='11111111-1111-4111-8111-111111111111';
select is((select count(*) from f31_storage where organization_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and owner_id='11111111-1111-4111-8111-111111111111'),1::bigint,'F31-C restored storage authorization condition passes');

select * from finish();
rollback;
