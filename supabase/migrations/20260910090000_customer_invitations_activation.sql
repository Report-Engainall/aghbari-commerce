create table if not exists public.customer_invitations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete cascade,
  email text not null,
  token_hash text not null unique,
  expires_at timestamptz not null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  invited_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint customer_invitations_email_check check (position('@' in email) > 1),
  constraint customer_invitations_state_check check (not (accepted_at is not null and revoked_at is not null))
);
create index if not exists customer_invitations_company_status_idx on public.customer_invitations(company_id,created_at desc);
create index if not exists customer_invitations_customer_status_idx on public.customer_invitations(company_id,customer_id,created_at desc);
alter table public.customer_invitations enable row level security;
drop policy if exists customer_invitations_staff_select on public.customer_invitations;
create policy customer_invitations_staff_select on public.customer_invitations for select to authenticated using (company_id=public.current_company_id() and exists(select 1 from public.company_memberships cm where cm.company_id=customer_invitations.company_id and cm.user_id=auth.uid() and cm.is_active and cm.role in ('owner','admin','sales')));

create or replace function public.create_customer_invitation(p_customer_id uuid,p_email text,p_expires_hours integer default 72)
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare v_company uuid; v_token text; v_id uuid; v_expires timestamptz; v_email text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  v_company:=public.current_company_id(); if v_company is null then raise exception 'COMPANY_NOT_FOUND'; end if;
  if not exists(select 1 from public.company_memberships cm where cm.company_id=v_company and cm.user_id=auth.uid() and cm.is_active and cm.role in ('owner','admin','sales')) then raise exception 'NOT_AUTHORIZED'; end if;
  if not exists(select 1 from public.customers c where c.id=p_customer_id and c.company_id=v_company) then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  v_email:=lower(trim(coalesce(p_email,''))); if length(v_email)<5 or length(v_email)>320 or position('@' in v_email)<=1 then raise exception 'INVALID_EMAIL'; end if;
  if p_expires_hours is null or p_expires_hours<1 or p_expires_hours>168 then raise exception 'INVALID_EXPIRY'; end if;
  update public.customer_invitations set revoked_at=coalesce(revoked_at,now()) where company_id=v_company and customer_id=p_customer_id and accepted_at is null and revoked_at is null;
  v_token:=encode(gen_random_bytes(32),'base64url'); v_expires:=now()+make_interval(hours=>p_expires_hours);
  insert into public.customer_invitations(company_id,customer_id,email,token_hash,expires_at,invited_by) values(v_company,p_customer_id,v_email,encode(digest(v_token,'sha256'),'hex'),v_expires,auth.uid()) returning id into v_id;
  insert into public.audit_logs(company_id,action,entity_type,entity_id,new_value,source) values(v_company,'customer_invitation_created','customer_invitation',v_id,jsonb_build_object('customer_id',p_customer_id,'email',v_email,'expires_at',v_expires),'admin_invite');
  return jsonb_build_object('id',v_id,'token',v_token,'expires_at',v_expires,'email',v_email);
end $$;
revoke all on function public.create_customer_invitation(uuid,text,integer) from public;
grant execute on function public.create_customer_invitation(uuid,text,integer) to authenticated;

create or replace function public.revoke_customer_invitation(p_invitation_id uuid)
returns boolean language plpgsql security definer set search_path=public,pg_catalog as $$
declare v_company uuid; v_updated integer;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  v_company:=public.current_company_id();
  if not exists(select 1 from public.company_memberships cm where cm.company_id=v_company and cm.user_id=auth.uid() and cm.is_active and cm.role in ('owner','admin')) then raise exception 'NOT_AUTHORIZED'; end if;
  update public.customer_invitations set revoked_at=now() where id=p_invitation_id and company_id=v_company and accepted_at is null and revoked_at is null;
  get diagnostics v_updated=row_count;
  if v_updated=1 then insert into public.audit_logs(company_id,action,entity_type,entity_id,source) values(v_company,'customer_invitation_revoked','customer_invitation',p_invitation_id,'admin_invite'); end if;
  return v_updated=1;
end $$;
revoke all on function public.revoke_customer_invitation(uuid) from public;
grant execute on function public.revoke_customer_invitation(uuid) to authenticated;

create or replace function public.accept_customer_invitation(p_token text)
returns public.customers language plpgsql security definer set search_path=public,pg_catalog as $$
declare v_inv public.customer_invitations; v_uid uuid; v_email text; v_customer public.customers;
begin
  v_uid:=auth.uid(); if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  v_email:=lower(trim(coalesce(auth.jwt()->>'email',''))); if length(trim(coalesce(p_token,'')))<32 then raise exception 'INVALID_INVITATION'; end if;
  select ci.* into v_inv from public.customer_invitations ci where ci.token_hash=encode(digest(trim(p_token),'sha256'),'hex') for update;
  if not found or v_inv.revoked_at is not null or v_inv.accepted_at is not null or v_inv.expires_at<=now() then raise exception 'INVITATION_INVALID_OR_EXPIRED'; end if;
  if v_email<>lower(v_inv.email) then raise exception 'INVITATION_EMAIL_MISMATCH'; end if;
  if exists(select 1 from public.profiles p where p.id=v_uid) then raise exception 'ACCOUNT_ALREADY_LINKED'; end if;
  select c.* into v_customer from public.customers c where c.id=v_inv.customer_id and c.company_id=v_inv.company_id for update;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  insert into public.profiles(id,organization_id,customer_id,role) values(v_uid,v_inv.company_id,v_customer.id,'customer');
  update public.customer_invitations set accepted_at=now() where id=v_inv.id;
  insert into public.audit_logs(company_id,action,entity_type,entity_id,new_value,source) values(v_inv.company_id,'customer_invitation_accepted','customer_invitation',v_inv.id,jsonb_build_object('user_id',v_uid,'customer_id',v_customer.id),'customer_activation');
  return v_customer;
end $$;
revoke all on function public.accept_customer_invitation(text) from public;
grant execute on function public.accept_customer_invitation(text) to authenticated;
