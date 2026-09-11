create or replace function public.update_customer(p_customer_id uuid,p_name text,p_phone text,p_tier public.customer_tier)
returns public.customers
language plpgsql
security definer
set search_path=''
as $$
declare
  v_org uuid:=public.current_organization_id();
  v_role public.user_role:=public.current_role();
  v_customer public.customers%rowtype;
  v_name text:=nullif(pg_catalog.btrim(p_name),'');
  v_phone text:=nullif(pg_catalog.btrim(p_phone),'');
begin
  if v_org is null or v_role not in ('owner','admin','sales') then raise exception using errcode='42501'; end if;
  if v_name is null or pg_catalog.length(v_name)>200 or (v_phone is not null and pg_catalog.length(v_phone)>50) then raise exception 'بيانات العميل غير صالحة.' using errcode='22023'; end if;
  select * into v_customer from public.customers where id=p_customer_id and organization_id=v_org for update;
  if not found then raise exception using errcode='P0002'; end if;
  update public.customers set name=v_name,phone=v_phone,tier=coalesce(p_tier,tier),updated_at=now() where id=v_customer.id returning * into v_customer;
  return v_customer;
end;
$$;
revoke all on function public.update_customer(uuid,text,text,public.customer_tier) from public,anon;
grant execute on function public.update_customer(uuid,text,text,public.customer_tier) to authenticated;
