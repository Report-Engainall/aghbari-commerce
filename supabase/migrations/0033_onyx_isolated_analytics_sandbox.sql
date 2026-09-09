-- Onyx analytical sandbox: isolated from operational commerce tables.
-- No FK is intentionally created to products, orders, inventory, customers, or prices.
create table if not exists public.onyx_datasets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  source_name text not null check (length(trim(source_name)) between 1 and 255),
  source_fingerprint text not null check (length(trim(source_fingerprint)) between 32 and 128),
  status text not null default 'staged' check (status in ('staged','validated','processed','failed','archived')),
  quality_score numeric(5,2) check (quality_score is null or (quality_score >= 0 and quality_score <= 100)),
  total_rows integer not null default 0 check (total_rows >= 0),
  valid_rows integer not null default 0 check (valid_rows >= 0),
  invalid_rows integer not null default 0 check (invalid_rows >= 0),
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, source_fingerprint)
);

create table if not exists public.onyx_dataset_rows (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  dataset_id uuid not null references public.onyx_datasets(id) on delete cascade,
  row_number integer not null check (row_number > 0),
  normalized_data jsonb not null default '{}'::jsonb,
  status text not null default 'valid' check (status in ('valid','invalid','warning')),
  diagnostics jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  unique (dataset_id, row_number)
);

create table if not exists public.onyx_analysis_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  dataset_id uuid not null references public.onyx_datasets(id) on delete cascade,
  status text not null default 'queued' check (status in ('queued','running','completed','failed')),
  result jsonb not null default '{}'::jsonb,
  evidence jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists onyx_datasets_org_created_idx on public.onyx_datasets (organization_id, created_at desc);
create index if not exists onyx_rows_dataset_row_idx on public.onyx_dataset_rows (dataset_id, row_number);
create index if not exists onyx_analysis_org_created_idx on public.onyx_analysis_runs (organization_id, created_at desc);

alter table public.onyx_datasets enable row level security;
alter table public.onyx_dataset_rows enable row level security;
alter table public.onyx_analysis_runs enable row level security;

create policy "onyx_datasets_staff_org" on public.onyx_datasets
  for all to authenticated
  using (organization_id = public.current_organization_id() and public.is_staff())
  with check (organization_id = public.current_organization_id() and public.is_staff());

create policy "onyx_rows_staff_org" on public.onyx_dataset_rows
  for all to authenticated
  using (organization_id = public.current_organization_id() and public.is_staff())
  with check (organization_id = public.current_organization_id() and public.is_staff());

create policy "onyx_analysis_staff_org" on public.onyx_analysis_runs
  for all to authenticated
  using (organization_id = public.current_organization_id() and public.is_staff())
  with check (organization_id = public.current_organization_id() and public.is_staff());

revoke all on public.onyx_datasets, public.onyx_dataset_rows, public.onyx_analysis_runs from anon;
revoke all on public.onyx_datasets, public.onyx_dataset_rows, public.onyx_analysis_runs from authenticated;
grant select, insert, update, delete on public.onyx_datasets, public.onyx_dataset_rows, public.onyx_analysis_runs to authenticated;
