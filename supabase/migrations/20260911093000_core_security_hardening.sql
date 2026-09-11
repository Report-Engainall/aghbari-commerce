-- Day 1 canonical operational-schema hardening.
-- No historical migration is modified; all corrections are additive/reversible at the release boundary.

-- 1) Payment idempotency: bind one operation key to one immutable payment payload.
alter table public.payments
  add column if not exists idempotency_key text,
  add column if not exists idempotency_payload_hash text;

create unique index if not exists uq_payments_organization_idempotency_key
  on public.payments(organization_id, idempotency_key)
  where idempotency_key is not null;

drop function if exists public.record_payment(uuid,numeric,payment_method,uuid,text,text);
drop function if exists public.record_payment(uuid,numeric,payment_method,uuid,text);

create function public.record_payment(
  p_invoice_id uuid,
  p_amount numeric,
  p_method public.payment_method,
  p_cash_account_id uuid default null,
  p_reference text default null,
  p_idempotency_key text default null
)
returns public.payments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := public.current_organization_id();
  v_role public.user_role := public.current_role();
  v_invoice public.operational_invoices%rowtype;
  v_account public.cash_accounts%rowtype;
  v_payment public.payments%rowtype;
  v_existing public.payments%rowtype;
  v_paid numeric := 0;
  v_key text := nullif(pg_catalog.btrim(p_idempotency_key), '');
  v_reference text := nullif(pg_catalog.btrim(p_reference), '');
  v_payload_hash text;
begin
  if auth.uid() is null or v_org is null or v_role not in ('owner','admin','sales') then
    raise exception using errcode='42501', message='payment access required';
  end if;
  if v_key is null or pg_catalog.length(v_key) < 16 or pg_catalog.length(v_key) > 128 then
    raise exception using errcode='22023', message='payment idempotency key required';
  end if;
  if p_amount is null or not pg_catalog.isfinite(p_amount) or p_amount <= 0 or p_amount > 9007199254740991 then
    raise exception using errcode='22023', message='invalid payment amount';
  end if;

  v_payload_hash := pg_catalog.md5(pg_catalog.jsonb_build_object(
    'invoice_id', p_invoice_id,
    'amount', p_amount,
    'method', p_method::text,
    'cash_account_id', p_cash_account_id,
    'reference', v_reference
  )::text);

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_org::text || ':payment:' || v_key, 0)
  );

  select * into v_existing
    from public.payments p
   where p.organization_id=v_org and p.idempotency_key=v_key
   limit 1;
  if found then
    if v_existing.idempotency_payload_hash is distinct from v_payload_hash then
      raise exception using errcode='40001', message='payment idempotency payload conflict';
    end if;
    return v_existing;
  end if;

  select * into v_invoice
    from public.operational_invoices i
   where i.id=p_invoice_id and i.organization_id=v_org
   for update;
  if not found then raise exception using errcode='P0002', message='invoice not found'; end if;
  if v_invoice.status='void' then raise exception using errcode='22023', message='invoice not payable'; end if;

  select coalesce(sum(p.amount),0) into v_paid
    from public.payments p
   where p.organization_id=v_org and p.invoice_id=v_invoice.id;
  if p_amount > v_invoice.total-v_paid then
    raise exception using errcode='22003', message='payment exceeds invoice balance';
  end if;

  if p_method='cash' and p_cash_account_id is null then
    raise exception using errcode='22023', message='cash account required';
  end if;
  if p_cash_account_id is not null then
    select * into v_account
      from public.cash_accounts a
     where a.id=p_cash_account_id and a.organization_id=v_org and a.is_active
     for update;
    if not found or v_account.currency<>v_invoice.currency then
      raise exception using errcode='22023', message='cash account unavailable or currency mismatch';
    end if;
  end if;

  insert into public.payments(
    organization_id,invoice_id,cash_account_id,amount,method,reference,actor_id,idempotency_key,idempotency_payload_hash
  ) values (
    v_org,v_invoice.id,p_cash_account_id,p_amount,p_method,v_reference,auth.uid(),v_key,v_payload_hash
  ) returning * into v_payment;

  if p_cash_account_id is not null then
    insert into public.cash_transactions(
      organization_id,cash_account_id,direction,amount,source_type,source_id,actor_id
    ) values (
      v_org,p_cash_account_id,'in',p_amount,'payment',v_payment.id,auth.uid()
    );
  end if;

  update public.operational_invoices
     set status=case when v_paid+p_amount>=total then 'paid' else 'partially_paid' end,
         updated_at=pg_catalog.now()
   where id=v_invoice.id and organization_id=v_org;

  return v_payment;
end;
$$;

revoke all on function public.record_payment(uuid,numeric,public.payment_method,uuid,text,text) from public, anon;
grant execute on function public.record_payment(uuid,numeric,public.payment_method,uuid,text,text) to authenticated;

-- 2) Device security: hashes are never returned to the customer/client boundary.
drop function if exists public.bind_customer_device(text,text);
create function public.bind_customer_device(p_device_key_hash text, p_device_label text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := public.current_organization_id();
  v_customer uuid := public.current_customer_id();
  v_device public.customer_devices%rowtype;
begin
  if auth.uid() is null or v_customer is null or v_org is null then raise exception using errcode='42501',message='device binding access required'; end if;
  if p_device_key_hash is null or pg_catalog.length(pg_catalog.btrim(p_device_key_hash)) < 32 or pg_catalog.length(pg_catalog.btrim(p_device_key_hash)) > 256 then raise exception using errcode='22023',message='invalid device key'; end if;
  if exists(select 1 from public.customer_devices where organization_id=v_org and customer_id=v_customer and is_active and device_key_hash<>pg_catalog.btrim(p_device_key_hash)) then raise exception using errcode='40901',message='another active device is already bound'; end if;
  insert into public.customer_devices(organization_id,customer_id,device_key_hash,device_label,is_active,last_seen_at,updated_at)
  values(v_org,v_customer,pg_catalog.btrim(p_device_key_hash),nullif(pg_catalog.btrim(p_device_label),''),true,pg_catalog.now(),pg_catalog.now())
  on conflict (organization_id,customer_id,device_key_hash) do update set is_active=true,last_seen_at=pg_catalog.now(),updated_at=pg_catalog.now()
  returning * into v_device;
  return pg_catalog.jsonb_build_object('id',v_device.id,'customer_id',v_device.customer_id,'device_label',v_device.device_label,'is_active',v_device.is_active,'last_seen_at',v_device.last_seen_at,'created_at',v_device.created_at,'updated_at',v_device.updated_at);
end;
$$;

-- Request/review responses are also sanitized so requested_device_key_hash never leaves the DB boundary.
drop function if exists public.request_customer_device_change(text,text,text);
create function public.request_customer_device_change(p_device_key_hash text,p_device_label text default null,p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid:=public.current_organization_id(); v_customer uuid:=public.current_customer_id(); v_request public.device_change_requests%rowtype; v_current uuid;
begin
  if auth.uid() is null or v_customer is null or v_org is null then raise exception using errcode='42501',message='device change access required'; end if;
  if p_device_key_hash is null or pg_catalog.length(pg_catalog.btrim(p_device_key_hash))<32 or pg_catalog.length(pg_catalog.btrim(p_device_key_hash))>256 then raise exception using errcode='22023',message='invalid device key'; end if;
  select id into v_current from public.customer_devices where organization_id=v_org and customer_id=v_customer and is_active limit 1;
  if exists(select 1 from public.device_change_requests where organization_id=v_org and customer_id=v_customer and status='pending') then raise exception using errcode='40901',message='pending device change already exists'; end if;
  insert into public.device_change_requests(organization_id,customer_id,current_device_id,requested_device_key_hash,requested_device_label,reason)
  values(v_org,v_customer,v_current,pg_catalog.btrim(p_device_key_hash),nullif(pg_catalog.btrim(p_device_label),''),nullif(pg_catalog.btrim(p_reason),'')) returning * into v_request;
  return pg_catalog.jsonb_build_object('id',v_request.id,'customer_id',v_request.customer_id,'current_device_id',v_request.current_device_id,'requested_device_label',v_request.requested_device_label,'status',v_request.status,'reviewed_by',v_request.reviewed_by,'reviewed_at',v_request.reviewed_at,'reason',v_request.reason,'created_at',v_request.created_at);
end;
$$;

drop function if exists public.review_device_change_request(uuid,boolean,text);
create function public.review_device_change_request(p_request_id uuid,p_approve boolean,p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_org uuid:=public.current_organization_id(); v_request public.device_change_requests%rowtype;
begin
  if auth.uid() is null or v_org is null or not public.is_staff() then raise exception using errcode='42501',message='device review access required'; end if;
  select * into v_request from public.device_change_requests where id=p_request_id and organization_id=v_org and status='pending' for update;
  if not found then raise exception using errcode='P0002',message='device change request not found'; end if;
  if p_approve then
    update public.customer_devices set is_active=false,updated_at=pg_catalog.now() where organization_id=v_org and customer_id=v_request.customer_id and is_active;
    insert into public.customer_devices(organization_id,customer_id,device_key_hash,device_label,is_active,last_seen_at,updated_at)
    values(v_org,v_request.customer_id,v_request.requested_device_key_hash,v_request.requested_device_label,true,pg_catalog.now(),pg_catalog.now())
    on conflict (organization_id,customer_id,device_key_hash) do update set is_active=true,last_seen_at=pg_catalog.now(),updated_at=pg_catalog.now();
  end if;
  update public.device_change_requests set status=case when p_approve then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=pg_catalog.now(),reason=coalesce(nullif(pg_catalog.btrim(p_reason),''),reason) where id=v_request.id returning * into v_request;
  return pg_catalog.jsonb_build_object('id',v_request.id,'customer_id',v_request.customer_id,'current_device_id',v_request.current_device_id,'requested_device_label',v_request.requested_device_label,'status',v_request.status,'reviewed_by',v_request.reviewed_by,'reviewed_at',v_request.reviewed_at,'reason',v_request.reason,'created_at',v_request.created_at);
end;
$$;

revoke all on function public.bind_customer_device(text,text) from public, anon;
revoke all on function public.request_customer_device_change(text,text,text) from public, anon;
revoke all on function public.review_device_change_request(uuid,boolean,text) from public, anon;
grant execute on function public.bind_customer_device(text,text) to authenticated;
grant execute on function public.request_customer_device_change(text,text,text) to authenticated;
grant execute on function public.review_device_change_request(uuid,boolean,text) to authenticated;

-- 3) Notification trigger is internal-only: authenticated clients cannot invoke it directly.
alter function public.notify_order_status_change() set search_path = '';
revoke all on function public.notify_order_status_change() from public, authenticated, anon;

-- 4) Remove obsolete four-argument catalog overload; keep the canonical warehouse-aware contract.
drop function if exists public.get_catalog(text,uuid,integer,integer);

-- 5) Fail closed for every remaining public SECURITY DEFINER function.
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef loop
    execute format('alter function %s set search_path = ''''', r.signature);
  end loop;
end;
$$;
