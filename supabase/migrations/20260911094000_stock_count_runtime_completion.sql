-- Day 1: complete the stock-count runtime contract used by the application.
-- The source already exposes start/set/complete commands; this migration closes the
-- missing runtime persistence and completion transaction without mutating history.

create table if not exists public.stock_count_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  warehouse_id uuid not null,
  status text not null default 'open' check (status in ('open','completed','cancelled')),
  idempotency_key text not null,
  started_by uuid references auth.users(id) on delete set null,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  notes text,
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (warehouse_id, organization_id) references public.warehouses(id, organization_id) on delete restrict
);
create index if not exists stock_count_sessions_open_idx on public.stock_count_sessions(organization_id, warehouse_id, started_at desc) where status='open';

create table if not exists public.stock_count_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  session_id uuid not null,
  product_id uuid not null,
  expected_quantity integer not null check (expected_quantity >= 0),
  counted_quantity integer check (counted_quantity is null or counted_quantity >= 0),
  completed_quantity integer check (completed_quantity is null or completed_quantity >= 0),
  variance integer,
  counted_at timestamptz,
  unique (session_id, product_id),
  unique (id, organization_id),
  foreign key (session_id, organization_id) references public.stock_count_sessions(id, organization_id) on delete cascade,
  foreign key (product_id, organization_id) references public.products(id, organization_id) on delete restrict
);
create index if not exists stock_count_lines_session_idx on public.stock_count_lines(organization_id, session_id, product_id);

alter table public.stock_count_sessions enable row level security;
alter table public.stock_count_lines enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='stock_count_sessions' and policyname='stock_count_sessions_staff_read') then
    create policy stock_count_sessions_staff_read on public.stock_count_sessions for select to authenticated using (organization_id=public.current_organization_id() and public.is_staff());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='stock_count_lines' and policyname='stock_count_lines_staff_read') then
    create policy stock_count_lines_staff_read on public.stock_count_lines for select to authenticated using (organization_id=public.current_organization_id() and public.is_staff());
  end if;
end $$;

create or replace function public.complete_stock_count(p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := public.current_organization_id();
  v_role public.user_role := public.current_role();
  v_session public.stock_count_sessions%rowtype;
  v_line public.stock_count_lines%rowtype;
  v_balance integer;
  v_variance integer;
  v_adjusted integer := 0;
  v_uncounted integer;
begin
  if auth.uid() is null or v_org is null or v_role not in ('owner','admin','warehouse') then
    raise exception using errcode='42501', message='stock count completion access required';
  end if;
  if p_session_id is null then raise exception using errcode='22023', message='stock count session id required'; end if;

  select * into v_session
    from public.stock_count_sessions
   where id=p_session_id and organization_id=v_org
   for update;
  if not found then raise exception using errcode='P0002', message='stock count not found'; end if;
  if v_session.status='completed' then
    return pg_catalog.jsonb_build_object('status','completed','session_id',v_session.id,'adjusted_lines',
      (select count(*) from public.stock_count_lines where organization_id=v_org and session_id=v_session.id and variance is distinct from 0));
  end if;
  if v_session.status<>'open' then raise exception using errcode='22023', message='stock count is not open'; end if;

  select count(*) into v_uncounted
    from public.stock_count_lines
   where organization_id=v_org and session_id=v_session.id and counted_quantity is null;
  if v_uncounted>0 then
    raise exception using errcode='55006', message='stock count has uncounted lines';
  end if;

  -- Deterministic row locking prevents concurrent stock mutations from overwriting
  -- the count result while the adjustment is being posted.
  for v_line in
    select * from public.stock_count_lines
     where organization_id=v_org and session_id=v_session.id
     order by product_id
     for update
  loop
    insert into public.inventory_balances(organization_id,warehouse_id,product_id,quantity)
    values(v_org,v_session.warehouse_id,v_line.product_id,0)
    on conflict (warehouse_id,product_id) do nothing;

    select quantity into v_balance
      from public.inventory_balances
     where organization_id=v_org and warehouse_id=v_session.warehouse_id and product_id=v_line.product_id
     for update;

    v_variance := v_line.counted_quantity - coalesce(v_balance,0);

    update public.inventory_balances
       set quantity=v_line.counted_quantity, updated_at=pg_catalog.now()
     where organization_id=v_org and warehouse_id=v_session.warehouse_id and product_id=v_line.product_id;

    update public.stock_count_lines
       set completed_quantity=v_line.counted_quantity,
           variance=v_line.counted_quantity-v_line.expected_quantity
     where id=v_line.id and organization_id=v_org;

    if v_variance<>0 then
      insert into public.inventory_movements(organization_id,warehouse_id,product_id,delta,source_type,source_id,actor_id)
      values(v_org,v_session.warehouse_id,v_line.product_id,v_variance,'stock_count',v_session.id,auth.uid());
      v_adjusted := v_adjusted + 1;
    end if;
  end loop;

  update public.stock_count_sessions
     set status='completed', completed_at=pg_catalog.now()
   where id=v_session.id and organization_id=v_org;

  insert into public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata)
  values(v_org,auth.uid(),'stock_count.complete','stock_count',v_session.id,'success',
    pg_catalog.jsonb_build_object('warehouse_id',v_session.warehouse_id,'adjusted_lines',v_adjusted));
  insert into public.outbox_events(organization_id,aggregate_type,aggregate_id,event_type,payload)
  values(v_org,'stock_count',v_session.id,'inventory.stock_count_completed',
    pg_catalog.jsonb_build_object('session_id',v_session.id,'warehouse_id',v_session.warehouse_id,'adjusted_lines',v_adjusted));

  return pg_catalog.jsonb_build_object('status','completed','session_id',v_session.id,'adjusted_lines',v_adjusted);
end;
$$;

revoke all on function public.complete_stock_count(uuid) from public, anon;
grant execute on function public.complete_stock_count(uuid) to authenticated;
