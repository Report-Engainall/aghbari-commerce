begin;
create extension if not exists pgtap;

select plan(20);

-- F20 CMS/control-plane persistence currently available in this lineage.
select has_table('public','client_ui_settings','F20 has client_ui_settings persistence');
select has_column('public','client_ui_settings','organization_id','F20 settings are tenant keyed');
select has_column('public','client_ui_settings','config','F20 settings have persisted config');
select has_column('public','client_ui_settings','updated_at','F20 settings have update timestamp');

-- F21/F22 must have executable domain persistence before they can be PASS.
select has_table('public','shipping','F21 shipping table exists');
select has_table('public','returns','F22 returns table exists');

-- F10 RBAC: role source and staff authorization surface.
select has_column('public','profiles','role','F10 profiles expose role');
select has_function('public','is_staff','F10 backend staff authorization function exists');

-- F13/F14 authentication backend primitives.
select has_table('auth','users','F13/F14 auth users exist');
select has_table('public','customer_invitations','F14 invitation persistence exists');
select has_function('public','consume_customer_invitation','F14 invitation consume function exists');

-- F18 pricing/MOQ server-side source of truth.
select has_table('public','customer_price_tiers','F18 customer-specific pricing tiers exist');
select has_column('public','customer_price_tiers','min_quantity','F18 MOQ is persisted');
select has_column('public','customer_price_tiers','unit_price','F18 server-side unit price exists');

-- F24 PWA contract surface is static/runtime code, not a DB entity; record it here as explicit executable gate.
select has_function('public','get_dashboard_snapshot','F28 trace target backend function exists');

-- F28 evidence/audit + F12 outbox linkage.
select has_table('public','audit_logs','F28 audit log persistence exists');
select has_table('public','outbox_events','F28/F12 outbox evidence persistence exists');

-- F25 offline/sync must have an idempotency authority in the DB.
select has_table('public','operation_idempotency','F25 exactly-once idempotency authority exists');

select * from finish();
rollback;
