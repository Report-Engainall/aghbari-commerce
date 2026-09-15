begin;

create table public.brands (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  name text not null, slug text not null, is_active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(organization_id,slug)
);
create table public.store_banners (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  title text not null, image_url text, target_url text, sort_order integer not null default 0, is_visible boolean not null default true,
  starts_at timestamptz, ends_at timestamptz, created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.store_content (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  slug text not null, title text not null, body text not null default '', is_published boolean not null default false,
  created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(organization_id,slug)
);
create table public.customer_segments (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  name text not null, description text, criteria jsonb not null default '{}'::jsonb, is_active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(organization_id,name)
);

alter table public.brands enable row level security;
alter table public.store_banners enable row level security;
alter table public.store_content enable row level security;
alter table public.customer_segments enable row level security;

create policy brands_read on public.brands for select to authenticated using(organization_id=public.current_organization_id() and is_active);
create policy brands_write on public.brands for all to authenticated using(organization_id=public.current_organization_id() and public.current_role() in ('owner','admin')) with check(organization_id=public.current_organization_id() and public.current_role() in ('owner','admin'));
create policy banners_read on public.store_banners for select to authenticated using(organization_id=public.current_organization_id() and is_visible and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now()));
create policy banners_write on public.store_banners for all to authenticated using(organization_id=public.current_organization_id() and public.current_role() in ('owner','admin')) with check(organization_id=public.current_organization_id() and public.current_role() in ('owner','admin'));
create policy content_read on public.store_content for select to authenticated using(organization_id=public.current_organization_id() and is_published);
create policy content_write on public.store_content for all to authenticated using(organization_id=public.current_organization_id() and public.current_role() in ('owner','admin')) with check(organization_id=public.current_organization_id() and public.current_role() in ('owner','admin'));
create policy segments_read on public.customer_segments for select to authenticated using(organization_id=public.current_organization_id() and is_active and public.current_role() in ('owner','admin','sales'));
create policy segments_write on public.customer_segments for all to authenticated using(organization_id=public.current_organization_id() and public.current_role() in ('owner','admin','sales')) with check(organization_id=public.current_organization_id() and public.current_role() in ('owner','admin','sales'));

create or replace function public.is_staff() returns boolean language sql stable security definer set search_path=public as $$ select public.current_role() in ('owner','admin','sales','warehouse','employee'); $$;

commit;
