-- Re-sequenced tenant relational guards.
-- Kept as a late migration so the historical 0013 finance migration remains intact.
-- These constraints make tenant ownership explicit at every tenant-owned relationship boundary.

alter table public.branches add constraint branches_id_organization_unique unique (id, organization_id);
alter table public.categories add constraint categories_id_organization_unique unique (id, organization_id);
alter table public.warehouses add constraint warehouses_id_organization_unique unique (id, organization_id);
alter table public.products add constraint products_id_organization_unique unique (id, organization_id);
alter table public.customers add constraint customers_id_organization_unique unique (id, organization_id);
alter table public.price_lists add constraint price_lists_id_organization_unique unique (id, organization_id);
alter table public.carts add constraint carts_id_organization_unique unique (id, organization_id);
alter table public.orders add constraint orders_id_organization_unique unique (id, organization_id);
alter table public.order_items add constraint order_items_id_organization_unique unique (id, organization_id);
alter table public.order_status_history add constraint order_status_history_id_organization_unique unique (id, organization_id);

alter table public.warehouses add constraint warehouses_branch_org_fk foreign key (branch_id, organization_id) references public.branches (id, organization_id) on delete restrict;
alter table public.categories add constraint categories_parent_org_fk foreign key (parent_id, organization_id) references public.categories (id, organization_id) on delete restrict;
alter table public.products add constraint products_category_org_fk foreign key (category_id, organization_id) references public.categories (id, organization_id) on delete restrict;
alter table public.profiles add constraint profiles_customer_org_fk foreign key (customer_id, organization_id) references public.customers (id, organization_id) on delete restrict;

-- Product-media policies are fail-closed without ever casting attacker-controlled path fragments.
drop policy if exists product_media_select on storage.objects;
drop policy if exists product_media_insert on storage.objects;
drop policy if exists product_media_update on storage.objects;
drop policy if exists product_media_delete on storage.objects;

create policy product_media_select on storage.objects for select to authenticated
using (
  bucket_id = 'product-media'
  and array_length(string_to_array(name, '/'), 1) = 3
  and split_part(name, '/', 1) = public.current_organization_id()::text
  and split_part(name, '/', 3) ~* '^[^/]+\\.(webp|png|jpe?g)$'
  and exists (select 1 from public.products p where p.id::text=split_part(name,'/',2) and p.organization_id=public.current_organization_id() and p.status='active')
);

create policy product_media_insert on storage.objects for insert to authenticated
with check (
  bucket_id='product-media'
  and public.is_staff()
  and array_length(string_to_array(name, '/'), 1) = 3
  and split_part(name, '/', 1) = public.current_organization_id()::text
  and split_part(name, '/', 3) ~* '^[^/]+\\.(webp|png|jpe?g)$'
  and exists (select 1 from public.products p where p.id::text=split_part(name,'/',2) and p.organization_id=public.current_organization_id())
);

create policy product_media_update on storage.objects for update to authenticated
using (
  bucket_id='product-media'
  and public.is_staff()
  and array_length(string_to_array(name, '/'), 1) = 3
  and split_part(name, '/', 1) = public.current_organization_id()::text
  and split_part(name, '/', 3) ~* '^[^/]+\\.(webp|png|jpe?g)$'
  and exists (select 1 from public.products p where p.id::text=split_part(name,'/',2) and p.organization_id=public.current_organization_id())
)
with check (
  bucket_id='product-media'
  and public.is_staff()
  and array_length(string_to_array(name, '/'), 1) = 3
  and split_part(name, '/', 1) = public.current_organization_id()::text
  and split_part(name, '/', 3) ~* '^[^/]+\\.(webp|png|jpe?g)$'
  and exists (select 1 from public.products p where p.id::text=split_part(name,'/',2) and p.organization_id=public.current_organization_id())
);

create policy product_media_delete on storage.objects for delete to authenticated
using (
  bucket_id='product-media'
  and public.is_staff()
  and array_length(string_to_array(name, '/'), 1) = 3
  and split_part(name, '/', 1) = public.current_organization_id()::text
  and split_part(name, '/', 3) ~* '^[^/]+\\.(webp|png|jpe?g)$'
  and exists (select 1 from public.products p where p.id::text=split_part(name,'/',2) and p.organization_id=public.current_organization_id())
);

comment on constraint warehouses_branch_org_fk on public.warehouses is 'Warehouse branch must belong to the same organization as the warehouse.';
comment on constraint categories_parent_org_fk on public.categories is 'Category hierarchy cannot reference a parent from another organization.';
comment on constraint products_category_org_fk on public.products is 'Product category must belong to the same organization as the product.';
comment on constraint profiles_customer_org_fk on public.profiles is 'Authenticated profile cannot bind to a customer from another organization.';
