begin;
create extension if not exists pgtap with schema extensions;
select plan(1);

insert into auth.users(id,email) values
 ('11111111-1111-4111-8111-111111111111','storage-a-diagnostic@test.local');
insert into public.organizations(id,name) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Storage Diagnostic Tenant');
insert into public.profiles(id,organization_id,role)
values ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','admin');

set local role authenticated;
select set_config('request.jwt.claims',json_build_object('role','authenticated','sub','11111111-1111-4111-8111-111111111111')::text,false);
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);

DO $$
DECLARE
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_claims text := current_setting('request.jwt.claims', true);
  v_uid uuid := public.storage_current_user_id();
  v_org uuid := public.storage_current_organization_id();
  v_staff boolean := public.storage_is_staff();
  v_auth_uid uuid := auth.uid();
  v_force_rls boolean;
  v_owner_type text;
  v_policy_count integer;
BEGIN
  SELECT c.relforcerowsecurity INTO v_force_rls
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='storage' AND c.relname='objects';

  SELECT data_type INTO v_owner_type
  FROM information_schema.columns
  WHERE table_schema='storage' AND table_name='objects' AND column_name='owner_id';

  SELECT count(*) INTO v_policy_count
  FROM pg_policies
  WHERE schemaname='storage' AND tablename='objects';

  RAISE NOTICE 'STORAGE_DIAG sub=% claims=% auth_uid=% helper_uid=% helper_org=% helper_staff=% force_rls=% owner_type=% policy_count=%',
    v_sub,v_claims,v_auth_uid,v_uid,v_org,v_staff,v_force_rls,v_owner_type,v_policy_count;

  FOR v_sub IN
    SELECT policyname || ' | permissive=' || permissive || ' | roles=' || array_to_string(roles,',') || ' | using=' || coalesce(qual,'<null>') || ' | check=' || coalesce(with_check,'<null>')
    FROM pg_policies
    WHERE schemaname='storage' AND tablename='objects'
    ORDER BY policyname
  LOOP
    RAISE NOTICE 'STORAGE_POLICY %', v_sub;
  END LOOP;
END $$;

select pass('storage authorization context diagnostic emitted');
select * from finish();
rollback;
