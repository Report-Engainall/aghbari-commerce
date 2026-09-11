-- Coherent security/reliability hardening for the a306 candidate.
-- This migration is intentionally source-only until the coherent fix set is reviewed,
-- then replayed on Clean Branch and promoted as one candidate.

-- Payment idempotency contract.
alter table public.payments
  add column if not exists idempotency_key text,
  add column if not exists idempotency_payload_hash text;

create unique index if not exists payments_org_idempotency_key_uidx
  on public.payments (organization_id, idempotency_key)
  where idempotency_key is not null;

revoke all on function public.record_payment(uuid, numeric, public.payment_method, uuid, text) from public, authenticated, anon;
drop function if exists public.record_payment(uuid, numeric, public.payment_method, uuid, text);

create or replace function public.record_payment(
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
  v_actor uuid := auth.uid();
  v_invoice public.operational_invoices%rowtype;
  v_account public.cash_accounts%rowtype;
  v_payment public.payments%rowtype;
  v_existing public.payments%rowtype;
  v_paid numeric;
  v_key text := nullif(pg_catalog.btrim(p_idempotency_key), '');
  v_reference text := nullif(pg_catalog.btrim(p_reference), '');
  v_payload_hash text;
begin
  if v_org is null or v_actor is null or v_role not in ('owner','admin','sales') then
    raise exception using errcode = '42501';
  end if;

  if v_key is null or pg_catalog.length(v_key) > 128 then
    raise exception 'مفتاح العملية مطلوب وغير صالح.' using errcode = '22023';
  end if;

  v_payload_hash := pg_catalog.md5(
    pg_catalog.jsonb_build_object(
      'invoice_id', p_invoice_id,
      'amount', p_amount,
      'method', p_method::text,
      'cash_account_id', p_cash_account_id,
      'reference', v_reference,
      'actor_id', v_actor
    )::text
  );

  pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_org::text || ':' || v_key, 0));

  select * into v_existing
    from public.payments
   where organization_id = v_org
     and idempotency_key = v_key
   limit 1;

  if found then
    if v_existing.idempotency_payload_hash is distinct from v_payload_hash then
      raise exception 'مفتاح العملية مستخدم لطلب مختلف.' using errcode = '23505';
    end if;
    return v_existing;
  end if;

  select * into v_invoice
    from public.operational_invoices
   where id = p_invoice_id
     and organization_id = v_org
   for update;

  if not found or p_amount is null or p_amount <= 0 then
    raise exception using errcode = '22023';
  end if;

  select pg_catalog.coalesce(pg_catalog.sum(amount), 0)
    into v_paid
    from public.payments
   where organization_id = v_org
     and invoice_id = v_invoice.id;

  if p_amount > v_invoice.total - v_paid then
    raise exception using errcode = '22003';
  end if;

  if p_method = 'cash' and p_cash_account_id is null then
    raise exception using errcode = '22023';
  end if;

  if p_cash_account_id is not null then
    select * into v_account
      from public.cash_accounts
     where id = p_cash_account_id
       and organization_id = v_org
       and is_active
     for update;
    if not found or v_account.currency <> v_invoice.currency then
      raise exception using errcode = '22023';
    end if;
  end if;

  insert into public.payments(
    organization_id,
    invoice_id,
    cash_account_id,
    amount,
    method,
    reference,
    actor_id,
    idempotency_key,
    idempotency_payload_hash
  ) values (
    v_org,
    v_invoice.id,
    p_cash_account_id,
    p_amount,
    p_method,
    v_reference,
    v_actor,
    v_key,
    v_payload_hash
  ) returning * into v_payment;

  if p_cash_account_id is not null then
    insert into public.cash_transactions(
      organization_id,
      cash_account_id,
      direction,
      amount,
      source_type,
      source_id,
      actor_id
    ) values (
      v_org,
      p_cash_account_id,
      'in',
      p_amount,
      'payment',
      v_payment.id,
      v_actor
    );
  end if;

  update public.operational_invoices
     set status = case when v_paid + p_amount >= total then 'paid' else 'partially_paid' end,
         updated_at = now()
   where id = v_invoice.id;

  return v_payment;
exception
  when unique_violation then
    select * into v_existing
      from public.payments
     where organization_id = v_org
       and idempotency_key = v_key
     limit 1;
    if found and v_existing.idempotency_payload_hash = v_payload_hash then
      return v_existing;
    end if;
    raise;
end;
$$;

grant execute on function public.record_payment(uuid, numeric, public.payment_method, uuid, text, text) to authenticated;

-- Device security response contracts: never return device_key_hash/requested_device_key_hash.
drop function if exists public.bind_customer_device(text, text);
create function public.bind_customer_device(p_device_key_hash text, p_device_label text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := public.current_organization_id();
  v_customer uuid := public.current_customer_id();
  v_device public.customer_devices;
begin
  if auth.uid() is null or v_customer is null or v_org is null then raise exception 'غير مصرح.'; end if;
  if p_device_key_hash is null or pg_catalog.length(pg_catalog.btrim(p_device_key_hash)) < 32 or pg_catalog.length(pg_catalog.btrim(p_device_key_hash)) > 256 then raise exception 'معرف الجهاز غير صالح.'; end if;
  if exists (select 1 from public.customer_devices where organization_id = v_org and customer_id = v_customer and is_active and device_key_hash <> pg_catalog.btrim(p_device_key_hash)) then raise exception 'الحساب مرتبط بجهاز آخر. يلزم طلب تغيير الجهاز.'; end if;
  insert into public.customer_devices(organization_id, customer_id, device_key_hash, device_label, is_active, last_seen_at, updated_at)
  values(v_org, v_customer, pg_catalog.btrim(p_device_key_hash), nullif(pg_catalog.btrim(p_device_label), ''), true, now(), now())
  on conflict (organization_id, customer_id, device_key_hash) do update set last_seen_at = now(), updated_at = now(), is_active = true
  returning * into v_device;
  return pg_catalog.jsonb_build_object('id', v_device.id, 'customer_id', v_device.customer_id, 'device_label', v_device.device_label, 'is_active', v_device.is_active, 'last_seen_at', v_device.last_seen_at);
end;
$$;
grant execute on function public.bind_customer_device(text, text) to authenticated;

revoke all on function public.request_customer_device_change(text, text, text) from public, authenticated, anon;
drop function if exists public.request_customer_device_change(text, text, text);
create function public.request_customer_device_change(p_device_key_hash text, p_device_label text default null, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := public.current_organization_id();
  v_customer uuid := public.current_customer_id();
  v_request public.device_change_requests;
  v_current uuid;
begin
  if auth.uid() is null or v_customer is null or v_org is null then raise exception 'غير مصرح.'; end if;
  if p_device_key_hash is null or pg_catalog.length(pg_catalog.btrim(p_device_key_hash)) < 32 or pg_catalog.length(pg_catalog.btrim(p_device_key_hash)) > 256 then raise exception 'معرف الجهاز غير صالح.'; end if;
  select id into v_current from public.customer_devices where organization_id = v_org and customer_id = v_customer and is_active limit 1;
  if exists (select 1 from public.device_change_requests where organization_id = v_org and customer_id = v_customer and status = 'pending') then raise exception 'يوجد طلب تغيير جهاز قيد المراجعة.'; end if;
  insert into public.device_change_requests(organization_id, customer_id, current_device_id, requested_device_key_hash, requested_device_label, reason)
  values(v_org, v_customer, v_current, pg_catalog.btrim(p_device_key_hash), nullif(pg_catalog.btrim(p_device_label), ''), nullif(pg_catalog.btrim(p_reason), ''))
  returning * into v_request;
  return pg_catalog.jsonb_build_object('id', v_request.id, 'customer_id', v_request.customer_id, 'current_device_id', v_request.current_device_id, 'requested_device_label', v_request.requested_device_label, 'status', v_request.status, 'reason', v_request.reason, 'created_at', v_request.created_at);
end;
$$;
grant execute on function public.request_customer_device_change(text, text, text) to authenticated;

revoke all on function public.review_device_change_request(uuid, boolean, text) from public, authenticated, anon;
drop function if exists public.review_device_change_request(uuid, boolean, text);
create function public.review_device_change_request(p_request_id uuid, p_approve boolean, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := public.current_organization_id();
  v_request public.device_change_requests;
  v_status text;
  v_reviewed_at timestamptz;
  v_reason text;
begin
  if auth.uid() is null or v_org is null or not public.is_staff() then raise exception 'غير مصرح.'; end if;
  select * into v_request from public.device_change_requests where id = p_request_id and organization_id = v_org and status = 'pending' for update;
  if not found then raise exception 'طلب تغيير الجهاز غير موجود أو تمت معالجته.'; end if;
  if p_approve then
    update public.customer_devices set is_active = false, updated_at = now() where organization_id = v_org and customer_id = v_request.customer_id and is_active;
    insert into public.customer_devices(organization_id, customer_id, device_key_hash, device_label, is_active, last_seen_at, updated_at)
    values(v_org, v_request.customer_id, v_request.requested_device_key_hash, v_request.requested_device_label, true, now(), now())
    on conflict (organization_id, customer_id, device_key_hash) do update set is_active = true, last_seen_at = now(), updated_at = now();
  end if;
  update public.device_change_requests set status = case when p_approve then 'approved' else 'rejected' end, reviewed_by = auth.uid(), reviewed_at = now(), reason = coalesce(nullif(pg_catalog.btrim(p_reason), ''), reason) where id = v_request.id
  returning status, reviewed_at, reason into v_status, v_reviewed_at, v_reason;
  return pg_catalog.jsonb_build_object('id', v_request.id, 'customer_id', v_request.customer_id, 'current_device_id', v_request.current_device_id, 'requested_device_label', v_request.requested_device_label, 'status', v_status, 'reviewed_by', auth.uid(), 'reviewed_at', v_reviewed_at, 'reason', v_reason);
end;
$$;
grant execute on function public.review_device_change_request(uuid, boolean, text) to authenticated;

-- Trigger-only function: authenticated callers must not be able to invoke it as an RPC.
revoke all on function public.notify_order_status_change() from public, authenticated, anon;
create or replace function public.notify_order_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.to_status is distinct from old.to_status then
    insert into public.notifications(organization_id, customer_id, kind, title, body, entity_type, entity_id)
    select new.organization_id, o.customer_id, 'order', 'تحديث حالة الطلب', 'تم تحديث الطلب رقم ' || o.order_number::text || ' إلى: ' || new.to_status::text || '.', 'order', o.id
    from public.orders o where o.id = new.order_id;
  end if;
  return new;
end;
$$;

-- Remove the obsolete four-argument catalog RPC. The five-argument warehouse-bound
-- RPC is the canonical application contract.
revoke all on function public.get_catalog(text, uuid, integer, integer) from public, authenticated, anon;
drop function public.get_catalog(text, uuid, integer, integer);
