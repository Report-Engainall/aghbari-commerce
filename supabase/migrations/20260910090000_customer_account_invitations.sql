-- Customer account onboarding is invitation-based: staff create a one-time
-- bearer token for an existing customer, then the customer chooses a password.
-- No service-role credential is exposed to the browser.

create table if not exists public.customer_account_invites (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete cascade,
  email text not null,
  token_hash bytea not null,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (length(trim(email)) > 3),
  check (expires_at > created_at)
);

create unique index if not exists customer_account_invites_active_customer_idx
  on public.customer_account_invites(organization_id, customer_id)
  where used_at is null;
create index if not exists customer_account_invites_token_idx
  on public.customer_account_invites(token_hash)
  where used_at is null;
create index if not exists customer_account_invites_expiry_idx
  on public.customer_account_invites(expires_at)
  where used_at is null;

alter table public.customer_account_invites enable row level security;

-- Tokens are returned only by the security-definer command below; they are
-- never readable through a table SELECT policy.
create policy customer_account_invites_staff_read
  on public.customer_account_invites for select
  using (organization_id = public.current_organization_id() and public.current_role() in ('owner','admin'));

create or replace function public.create_customer_account_invite(
  p_customer_id uuid,
  p_email text,
  p_expires_hours integer default 72
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid;
  v_customer_name text;
  v_email text := lower(trim(p_email));
  v_token text := encode(gen_random_bytes(32), 'hex');
  v_id uuid;
begin
  if public.current_role() not in ('owner','admin') then
    raise exception 'غير مصرح بإنشاء دعوات الحساب.';
  end if;

  if p_customer_id is null or p_expires_hours is null or p_expires_hours not between 1 and 720 then
    raise exception 'بيانات دعوة الحساب غير صالحة.';
  end if;
  if v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'البريد الإلكتروني غير صالح.';
  end if;

  select c.organization_id, c.name
    into v_org, v_customer_name
    from public.customers c
   where c.id = p_customer_id
     and c.organization_id = public.current_organization_id()
     and c.is_active
   for update;

  if v_org is null then
    raise exception 'العميل غير موجود أو غير نشط.';
  end if;

  update public.customer_account_invites
     set used_at = now()
   where organization_id = v_org
     and customer_id = p_customer_id
     and used_at is null;

  insert into public.customer_account_invites (
    organization_id, customer_id, email, token_hash, expires_at, created_by
  ) values (
    v_org, p_customer_id, v_email, digest(v_token, 'sha256'),
    now() + make_interval(hours => p_expires_hours), auth.uid()
  ) returning id into v_id;

  insert into public.audit_events (
    organization_id, actor_id, action, target_type, target_id, result, metadata
  ) values (
    v_org, auth.uid(), 'customer_account_invite_created', 'customer', p_customer_id,
    'success', jsonb_build_object('invite_id', v_id, 'email', v_email, 'expires_at', now() + make_interval(hours => p_expires_hours))
  );

  return jsonb_build_object(
    'invite_id', v_id,
    'customer_id', p_customer_id,
    'customer_name', v_customer_name,
    'email', v_email,
    'token', v_token,
    'expires_at', now() + make_interval(hours => p_expires_hours)
  );
end;
$$;

revoke all on function public.create_customer_account_invite(uuid, text, integer) from public;
grant execute on function public.create_customer_account_invite(uuid, text, integer) to authenticated;

create or replace function public.accept_customer_account_invite(
  p_token text,
  p_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.customer_account_invites%rowtype;
  v_user_email text;
  v_profile public.profiles%rowtype;
begin
  if p_user_id is null or p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    raise exception 'دعوة الحساب غير صالحة.';
  end if;

  select u.email
    into v_user_email
    from auth.users u
   where u.id = p_user_id;
  if v_user_email is null then
    raise exception 'حساب المستخدم غير موجود.';
  end if;

  select *
    into v_invite
    from public.customer_account_invites
   where token_hash = digest(lower(trim(p_token)), 'sha256')
     and used_at is null
     and expires_at > now()
   for update;

  if v_invite.id is null then
    raise exception 'دعوة الحساب غير صالحة أو منتهية.';
  end if;
  if lower(trim(v_user_email)) <> v_invite.email then
    raise exception 'البريد الإلكتروني لا يطابق دعوة العميل.';
  end if;

  select * into v_profile from public.profiles where id = p_user_id for update;
  if v_profile.id is not null then
    if v_profile.organization_id <> v_invite.organization_id or
       v_profile.customer_id is distinct from v_invite.customer_id then
      raise exception 'حساب المستخدم مرتبط بجهة أو عميل آخر.';
    end if;
  else
    insert into public.profiles (id, organization_id, customer_id, role)
    values (p_user_id, v_invite.organization_id, v_invite.customer_id, 'viewer');
  end if;

  update public.customer_account_invites
     set used_at = now()
   where id = v_invite.id;

  insert into public.audit_events (
    organization_id, actor_id, action, target_type, target_id, result, metadata
  ) values (
    v_invite.organization_id, p_user_id, 'customer_account_invite_accepted', 'customer',
    v_invite.customer_id, 'success', jsonb_build_object('invite_id', v_invite.id)
  );

  return jsonb_build_object(
    'customer_id', v_invite.customer_id,
    'organization_id', v_invite.organization_id
  );
end;
$$;

revoke all on function public.accept_customer_account_invite(text, uuid) from public;
grant execute on function public.accept_customer_account_invite(text, uuid) to anon, authenticated;
