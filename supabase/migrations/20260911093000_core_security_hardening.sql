-- Day 1 core security hardening: payment idempotency + legacy RPC surface.
-- This migration targets the canonical company-scoped schema on main.

alter table public.payments
  add column if not exists idempotency_key text,
  add column if not exists idempotency_payload_hash text;

create unique index if not exists uq_payments_company_idempotency_key
  on public.payments(company_id, idempotency_key)
  where idempotency_key is not null;

-- The legacy five-argument payment command is no longer an application contract.
revoke all on function public.record_payment(uuid,numeric,text,uuid,text) from public, authenticated, anon;

drop function if exists public.record_payment(uuid,numeric,text,uuid,text,text);

create function public.record_payment(
  p_invoice_id uuid,
  p_amount numeric,
  p_method text,
  p_cash_account_id uuid default null,
  p_reference text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid := public.current_company_id();
  v_role text;
  v_invoice public.sales_invoices%rowtype;
  v_account public.cash_accounts%rowtype;
  v_paid numeric;
  v_remaining numeric;
  v_new_paid numeric;
  v_status text;
  v_payment_id uuid;
  v_existing public.payments%rowtype;
  v_key text := nullif(pg_catalog.btrim(p_idempotency_key), '');
  v_reference text := nullif(pg_catalog.btrim(p_reference), '');
  v_method text := lower(nullif(pg_catalog.btrim(coalesce(p_method, 'cash')), ''));
  v_payload_hash text;
begin
  if auth.uid() is null or v_company is null then
    raise exception using errcode='42501', message='authenticated company context required';
  end if;

  select cm.role into v_role
    from public.company_memberships cm
   where cm.company_id=v_company and cm.user_id=auth.uid() and cm.is_active
   limit 1;
  if v_role not in ('owner','admin','sales') then
    raise exception using errcode='42501', message='staff finance role required';
  end if;

  if v_key is null or pg_catalog.length(v_key) > 128 then
    raise exception using errcode='22023', message='payment idempotency key required';
  end if;
  if v_method not in ('cash','bank_transfer','card','other') then
    raise exception using errcode='22023', message='invalid payment method';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount::text in ('NaN','Infinity','-Infinity') then
    raise exception using errcode='22023', message='invalid_payment_amount';
  end if;
  if p_invoice_id is null then
    raise exception using errcode='22023', message='invoice id required';
  end if;

  v_payload_hash := pg_catalog.md5(
    pg_catalog.jsonb_build_object(
      'invoice_id', p_invoice_id,
      'amount', p_amount,
      'method', v_method,
      'cash_account_id', p_cash_account_id,
      'reference', v_reference
    )::text
  );

  -- Serialize retries/concurrent submissions for the same tenant + operation key.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_company::text || ':' || v_key, 0)
  );

  select * into v_existing
    from public.payments p
   where p.company_id=v_company and p.idempotency_key=v_key
   limit 1;

  if found then
    if v_existing.idempotency_payload_hash is distinct from v_payload_hash then
      raise exception using errcode='23505', message='payment idempotency key is bound to a different payload';
    end if;
    return pg_catalog.jsonb_build_object(
      'payment_id', v_existing.id,
      'invoice_id', v_existing.invoice_id,
      'idempotent_replay', true
    );
  end if;

  select * into v_invoice
    from public.sales_invoices
   where id=p_invoice_id and company_id=v_company
   for update;
  if not found then raise exception 'invoice_not_found'; end if;
  if v_invoice.status in ('void','cancelled','draft') then raise exception 'invoice_not_payable'; end if;

  v_paid := coalesce(v_invoice.paid_amount,0);
  v_remaining := greatest(coalesce(v_invoice.total,0)-v_paid,0);
  if p_amount > v_remaining then raise exception 'payment_exceeds_balance'; end if;

  if v_method='cash' then
    if p_cash_account_id is null then raise exception 'cash_account_required'; end if;
    select * into v_account
      from public.cash_accounts
     where id=p_cash_account_id and company_id=v_company
     for update;
    if not found then raise exception 'cash_account_not_found'; end if;
    if v_account.currency <> v_invoice.currency then raise exception 'payment_currency_mismatch'; end if;
    update public.cash_accounts
       set received=received+p_amount, updated_at=now()
     where id=v_account.id;
  elsif p_cash_account_id is not null then
    raise exception 'cash_account_not_allowed_for_non_cash_payment';
  end if;

  insert into public.payments(
    company_id,direction,customer_id,invoice_id,amount,payment_date,method,reference,currency,
    idempotency_key,idempotency_payload_hash
  ) values (
    v_company,'in',v_invoice.customer_id,v_invoice.id,p_amount,current_date,v_method,v_reference,
    v_invoice.currency,v_key,v_payload_hash
  ) returning id into v_payment_id;

  v_new_paid := v_paid+p_amount;
  v_status := case when v_new_paid>=coalesce(v_invoice.total,0) then 'paid' else 'partially_paid' end;
  update public.sales_invoices
     set paid_amount=v_new_paid,status=v_status
   where id=v_invoice.id;

  insert into public.audit_logs(company_id,action,entity_type,entity_id,new_value,source)
  values(v_company,'payment_recorded','payment',v_payment_id,
    pg_catalog.jsonb_build_object('invoice_id',v_invoice.id,'amount',p_amount,'new_paid_amount',v_new_paid,'status',v_status),
    'finance');

  return pg_catalog.jsonb_build_object(
    'payment_id',v_payment_id,
    'invoice_id',v_invoice.id,
    'paid_amount',v_new_paid,
    'remaining_balance',greatest(v_invoice.total-v_new_paid,0),
    'status',v_status,
    'idempotent_replay',false
  );
exception
  when unique_violation then
    select * into v_existing
      from public.payments p
     where p.company_id=v_company and p.idempotency_key=v_key
     limit 1;
    if found and v_existing.idempotency_payload_hash = v_payload_hash then
      return pg_catalog.jsonb_build_object(
        'payment_id',v_existing.id,
        'invoice_id',v_existing.invoice_id,
        'idempotent_replay',true
      );
    end if;
    raise;
end;
$$;

revoke all on function public.record_payment(uuid,numeric,text,uuid,text,text) from public, anon;
grant execute on function public.record_payment(uuid,numeric,text,uuid,text,text) to authenticated;

-- Remove the obsolete four-argument catalog RPC if it exists; do not fail clean replay
-- when an environment has already removed it.
do $$
declare v_signature regprocedure := to_regprocedure('public.get_catalog(text,uuid,integer,integer)');
begin
  if v_signature is not null then
    execute format('revoke all on function %s from public, authenticated, anon', v_signature);
    execute format('drop function %s', v_signature);
  end if;
end;
$$;
