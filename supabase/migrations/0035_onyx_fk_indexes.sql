create index if not exists onyx_rows_org_idx on public.onyx_dataset_rows (organization_id);
create index if not exists onyx_rows_dataset_org_idx on public.onyx_dataset_rows (dataset_id, organization_id);
create index if not exists onyx_analysis_dataset_org_idx on public.onyx_analysis_runs (dataset_id, organization_id);
create index if not exists onyx_analysis_dataset_idx on public.onyx_analysis_runs (dataset_id);
create index if not exists onyx_analysis_created_by_idx on public.onyx_analysis_runs (created_by);
create index if not exists onyx_datasets_created_by_idx on public.onyx_datasets (created_by);
