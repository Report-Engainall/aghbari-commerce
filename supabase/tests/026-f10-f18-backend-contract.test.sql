begin;
create extension if not exists pgtap;
select plan(10);

select ok(exists(select 1 from pg_type t join pg_enum e on e.enumtypid=t.oid where t.typname='user_role' and e.enumlabel='owner'),'F10 owner role exists');
select ok(exists(select 1 from pg_type t join pg_enum e on e.enumtypid=t.oid where t.typname='user_role' and e.enumlabel='admin'),'F10 admin role exists');
select ok(exists(select 1 from pg_type t join pg_enum e on e.enumtypid=t.oid where t.typname='user_role' and e.enumlabel='employee'),'F10 employee role exists');
select ok(exists(select 1 from pg_type t join pg_enum e on e.enumtypid=t.oid where t.typname='user_role' and e.enumlabel='sales'),'F10 sales role exists');
select ok(exists(select 1 from pg_type t join pg_enum e on e.enumtypid=t.oid where t.typname='user_role' and e.enumlabel='warehouse'),'F10 warehouse role exists');
select ok(exists(select 1 from pg_type t join pg_enum e on e.enumtypid=t.oid where t.typname='user_role' and e.enumlabel='finance'),'F10 finance role exists');
select ok(exists(select 1 from pg_type t join pg_enum e on e.enumtypid=t.oid where t.typname='user_role' and e.enumlabel='viewer'),'F10 viewer role exists');
select ok(exists(select 1 from pg_type t join pg_enum e on e.enumtypid=t.oid where t.typname='user_role' and e.enumlabel='customer'),'F10 customer role exists');

select has_function('public','create_order','F18 checkout uses a server-side create_order authority');
select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='create_order' and pg_get_function_arguments(p.oid) ilike '%price%'),'F18 create_order has no client-supplied price parameter');

select * from finish();
rollback;
