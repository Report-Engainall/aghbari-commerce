-- Re-sequenced tenant relational guards.
-- The duplicate 0013 filename is removed; these guards are applied once after
-- the current company-based schema reconciliation migrations.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.branches'::regclass AND conname='branches_id_company_unique') THEN
    ALTER TABLE public.branches ADD CONSTRAINT branches_id_company_unique UNIQUE (id, company_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.categories'::regclass AND conname='categories_id_company_unique') THEN
    ALTER TABLE public.categories ADD CONSTRAINT categories_id_company_unique UNIQUE (id, company_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.warehouses'::regclass AND conname='warehouses_id_company_unique') THEN
    ALTER TABLE public.warehouses ADD CONSTRAINT warehouses_id_company_unique UNIQUE (id, company_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.products'::regclass AND conname='products_id_company_unique') THEN
    ALTER TABLE public.products ADD CONSTRAINT products_id_company_unique UNIQUE (id, company_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.customers'::regclass AND conname='customers_id_company_unique') THEN
    ALTER TABLE public.customers ADD CONSTRAINT customers_id_company_unique UNIQUE (id, company_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.orders'::regclass AND conname='orders_id_company_unique') THEN
    ALTER TABLE public.orders ADD CONSTRAINT orders_id_company_unique UNIQUE (id, company_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.order_items'::regclass AND conname='order_items_id_company_unique') THEN
    ALTER TABLE public.order_items ADD CONSTRAINT order_items_id_company_unique UNIQUE (id, company_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.order_status_history'::regclass AND conname='order_status_history_id_company_unique') THEN
    ALTER TABLE public.order_status_history ADD CONSTRAINT order_status_history_id_company_unique UNIQUE (id, company_id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.warehouses'::regclass AND conname='warehouses_branch_company_fk') THEN
    ALTER TABLE public.warehouses ADD CONSTRAINT warehouses_branch_company_fk
      FOREIGN KEY (branch_id, company_id) REFERENCES public.branches (id, company_id) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.categories'::regclass AND conname='categories_parent_company_fk') THEN
    ALTER TABLE public.categories ADD CONSTRAINT categories_parent_company_fk
      FOREIGN KEY (parent_id, company_id) REFERENCES public.categories (id, company_id) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.products'::regclass AND conname='products_category_company_fk') THEN
    ALTER TABLE public.products ADD CONSTRAINT products_category_company_fk
      FOREIGN KEY (category_id, company_id) REFERENCES public.categories (id, company_id) ON DELETE RESTRICT;
  END IF;
END $$;

-- Storage policy is deliberately fail-closed and scoped to the current company/product.
DROP POLICY IF EXISTS product_media_select ON storage.objects;
DROP POLICY IF EXISTS product_media_insert ON storage.objects;
DROP POLICY IF EXISTS product_media_update ON storage.objects;
DROP POLICY IF EXISTS product_media_delete ON storage.objects;

CREATE POLICY product_media_select ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id='product-media'
  AND array_length(string_to_array(name,'/'),1)=3
  AND split_part(name,'/',1)=public.current_company_id()::text
  AND split_part(name,'/',3) ~* '^[^/]+\\.(webp|png|jpe?g)$'
  AND EXISTS (SELECT 1 FROM public.products p WHERE p.id::text=split_part(name,'/',2) AND p.company_id=public.current_company_id() AND p.is_active)
);

CREATE POLICY product_media_insert ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id='product-media'
  AND public.is_staff()
  AND array_length(string_to_array(name,'/'),1)=3
  AND split_part(name,'/',1)=public.current_company_id()::text
  AND split_part(name,'/',3) ~* '^[^/]+\\.(webp|png|jpe?g)$'
  AND EXISTS (SELECT 1 FROM public.products p WHERE p.id::text=split_part(name,'/',2) AND p.company_id=public.current_company_id())
);

CREATE POLICY product_media_update ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id='product-media'
  AND public.is_staff()
  AND array_length(string_to_array(name,'/'),1)=3
  AND split_part(name,'/',1)=public.current_company_id()::text
  AND split_part(name,'/',3) ~* '^[^/]+\\.(webp|png|jpe?g)$'
  AND EXISTS (SELECT 1 FROM public.products p WHERE p.id::text=split_part(name,'/',2) AND p.company_id=public.current_company_id())
)
WITH CHECK (
  bucket_id='product-media'
  AND public.is_staff()
  AND array_length(string_to_array(name,'/'),1)=3
  AND split_part(name,'/',1)=public.current_company_id()::text
  AND split_part(name,'/',3) ~* '^[^/]+\\.(webp|png|jpe?g)$'
  AND EXISTS (SELECT 1 FROM public.products p WHERE p.id::text=split_part(name,'/',2) AND p.company_id=public.current_company_id())
);

CREATE POLICY product_media_delete ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id='product-media'
  AND public.is_staff()
  AND array_length(string_to_array(name,'/'),1)=3
  AND split_part(name,'/',1)=public.current_company_id()::text
  AND split_part(name,'/',3) ~* '^[^/]+\\.(webp|png|jpe?g)$'
  AND EXISTS (SELECT 1 FROM public.products p WHERE p.id::text=split_part(name,'/',2) AND p.company_id=public.current_company_id())
);

COMMENT ON CONSTRAINT warehouses_branch_company_fk ON public.warehouses IS 'Warehouse branch must belong to the same company as the warehouse.';
COMMENT ON CONSTRAINT categories_parent_company_fk ON public.categories IS 'Category hierarchy cannot reference a parent from another company.';
COMMENT ON CONSTRAINT products_category_company_fk ON public.products IS 'Product category must belong to the same company as the product.';
