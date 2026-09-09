-- Defense in depth: child records must belong to the exact same organization as their dataset.
alter table public.onyx_datasets add constraint onyx_datasets_id_org_key unique (id, organization_id);
alter table public.onyx_dataset_rows add constraint onyx_rows_dataset_org_fk foreign key (dataset_id, organization_id) references public.onyx_datasets(id, organization_id) on delete cascade;
alter table public.onyx_analysis_runs add constraint onyx_analysis_dataset_org_fk foreign key (dataset_id, organization_id) references public.onyx_datasets(id, organization_id) on delete cascade;
