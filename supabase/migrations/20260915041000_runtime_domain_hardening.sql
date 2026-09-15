-- Runtime hardening discovered by exact clean-source pgTAP replay.
-- Fixes real function defects, pins SECURITY DEFINER search_path, closes public/anon execute,
-- and adds the missing operational FK indexes required by the current schema contract.

ALTER FUNCTION public.create_order(text,uuid,jsonb) SET search_path='';
ALTER FUNCTION public.record_payment(uuid,numeric,public.payment_method,uuid,text) SET search_path='';
ALTER FUNCTION public.record_expense(uuid,uuid,text,numeric,text,text,date) SET search_path='';
ALTER FUNCTION public.create_purchase_order(uuid,uuid,text,jsonb,text,text) SET search_path='';
ALTER FUNCTION public.receive_purchase_order(uuid,text,jsonb,text) SET search_path='';

-- PostgreSQL has no isfinite(numeric); bounded numeric checks already provide the finite/range guard.
CREATE OR REPLACE FUNCTION public.record_expense(
  p_branch_id uuid,p_cash_account_id uuid,p_category text,p_amount numeric,p_currency text DEFAULT 'YER',p_description text DEFAULT NULL,p_expense_date date DEFAULT current_date
)
RETURNS public.expenses LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_org uuid:=public.current_organization_id();
  v_role public.user_role:=public.current_role();
  v_account public.cash_accounts%rowtype;
  v_expense public.expenses%rowtype;
  v_balance numeric(18,2);
BEGIN
  IF v_org IS NULL OR v_role NOT IN ('owner','admin') THEN RAISE EXCEPTION USING errcode='42501',message='expense access required'; END IF;
  IF nullif(trim(p_category),'') IS NULL OR p_amount IS NULL OR p_amount<=0 OR p_amount>9007199254740991 THEN RAISE EXCEPTION USING errcode='22023',message='expense category and positive amount are required'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.branches b WHERE b.id=p_branch_id AND b.organization_id=v_org AND b.is_active) THEN RAISE EXCEPTION USING errcode='P0002',message='branch not found'; END IF;
  SELECT * INTO v_account FROM public.cash_accounts a WHERE a.id=p_cash_account_id AND a.organization_id=v_org AND a.is_active FOR UPDATE;
  IF NOT FOUND OR v_account.currency<>upper(trim(coalesce(p_currency,''))) THEN RAISE EXCEPTION USING errcode='22023',message='cash account currency mismatch'; END IF;
  SELECT v_account.opening_balance + coalesce(sum(CASE WHEN t.direction='in' THEN t.amount WHEN t.direction='out' THEN -t.amount ELSE 0 END),0)
    INTO v_balance
  FROM public.cash_transactions t
  WHERE t.organization_id=v_org AND t.cash_account_id=v_account.id;
  IF v_balance<p_amount THEN RAISE EXCEPTION USING errcode='22003',message='expense exceeds available cash balance'; END IF;
  INSERT INTO public.expenses(organization_id,branch_id,cash_account_id,category,amount,currency,description,expense_date,actor_id)
  VALUES(v_org,p_branch_id,p_cash_account_id,trim(p_category),p_amount,upper(trim(p_currency)),nullif(trim(p_description),''),coalesce(p_expense_date,current_date),auth.uid()) RETURNING * INTO v_expense;
  INSERT INTO public.cash_transactions(organization_id,cash_account_id,direction,amount,source_type,source_id,note,actor_id)
  VALUES(v_org,p_cash_account_id,'out',p_amount,'expense',v_expense.id,v_expense.category,auth.uid());
  INSERT INTO public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata)
  VALUES(v_org,auth.uid(),'expense.create','expense',v_expense.id,'success',jsonb_build_object('amount',p_amount,'category',v_expense.category));
  INSERT INTO public.outbox_events(organization_id,aggregate_type,aggregate_id,event_type,payload)
  VALUES(v_org,'expense',v_expense.id,'expense.posted',jsonb_build_object('expense_id',v_expense.id,'amount',p_amount));
  RETURN v_expense;
END; $$;

CREATE OR REPLACE FUNCTION public.record_payment(
  p_invoice_id uuid,p_amount numeric,p_method public.payment_method,p_cash_account_id uuid DEFAULT NULL,p_reference text DEFAULT NULL
)
RETURNS public.payments LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_org uuid:=public.current_organization_id();
  v_role public.user_role:=public.current_role();
  v_invoice public.operational_invoices%rowtype;
  v_account public.cash_accounts%rowtype;
  v_paid numeric(18,2);
  v_payment public.payments%rowtype;
BEGIN
  IF v_org IS NULL OR v_role NOT IN ('owner','admin','sales') THEN RAISE EXCEPTION USING errcode='42501',message='payment access required'; END IF;
  IF p_amount IS NULL OR p_amount<=0 OR p_amount>9007199254740991 THEN RAISE EXCEPTION USING errcode='22023',message='payment amount must be positive'; END IF;
  SELECT * INTO v_invoice FROM public.operational_invoices i WHERE i.id=p_invoice_id AND i.organization_id=v_org FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002',message='invoice not found'; END IF;
  IF v_invoice.status='void' THEN RAISE EXCEPTION USING errcode='22023',message='void invoice cannot receive payment'; END IF;
  SELECT coalesce(sum(p.amount),0) INTO v_paid FROM public.payments p WHERE p.organization_id=v_org AND p.invoice_id=v_invoice.id;
  IF p_amount > v_invoice.total-v_paid THEN RAISE EXCEPTION USING errcode='22003',message='payment exceeds invoice balance'; END IF;
  IF p_method='cash' THEN
    IF p_cash_account_id IS NULL THEN RAISE EXCEPTION USING errcode='22023',message='cash account required for cash payment'; END IF;
    SELECT * INTO v_account FROM public.cash_accounts a WHERE a.id=p_cash_account_id AND a.organization_id=v_org AND a.is_active FOR UPDATE;
    IF NOT FOUND OR v_account.currency<>v_invoice.currency THEN RAISE EXCEPTION USING errcode='22023',message='cash account mismatch'; END IF;
  ELSIF p_cash_account_id IS NOT NULL THEN
    SELECT * INTO v_account FROM public.cash_accounts a WHERE a.id=p_cash_account_id AND a.organization_id=v_org AND a.is_active FOR UPDATE;
    IF NOT FOUND OR v_account.currency<>v_invoice.currency THEN RAISE EXCEPTION USING errcode='22023',message='cash account mismatch'; END IF;
  END IF;
  INSERT INTO public.payments(organization_id,invoice_id,cash_account_id,amount,method,reference,actor_id)
  VALUES(v_org,v_invoice.id,p_cash_account_id,p_amount,p_method,nullif(trim(p_reference),''),auth.uid()) RETURNING * INTO v_payment;
  IF p_cash_account_id IS NOT NULL THEN
    INSERT INTO public.cash_transactions(organization_id,cash_account_id,direction,amount,source_type,source_id,note,actor_id)
    VALUES(v_org,p_cash_account_id,'in',p_amount,'payment',v_payment.id,nullif(trim(p_reference),''),auth.uid());
  END IF;
  SELECT coalesce(sum(p.amount),0) INTO v_paid FROM public.payments p WHERE p.organization_id=v_org AND p.invoice_id=v_invoice.id;
  UPDATE public.operational_invoices i
  SET status=CASE WHEN v_paid>=i.total THEN 'paid'::public.invoice_status ELSE 'partially_paid'::public.invoice_status END,updated_at=now()
  WHERE i.id=v_invoice.id AND i.organization_id=v_org;
  INSERT INTO public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata)
  VALUES(v_org,auth.uid(),'payment.create','payment',v_payment.id,'success',jsonb_build_object('invoice_id',v_invoice.id,'amount',p_amount,'method',p_method));
  INSERT INTO public.outbox_events(organization_id,aggregate_type,aggregate_id,event_type,payload)
  VALUES(v_org,'operational_invoice',v_invoice.id,'payment.received',jsonb_build_object('invoice_id',v_invoice.id,'payment_id',v_payment.id,'amount',p_amount));
  RETURN v_payment;
END; $$;

-- Recreate create_order with the product status reference explicitly qualified.
CREATE OR REPLACE FUNCTION public.create_order(p_idempotency_key text,p_warehouse_id uuid,p_lines jsonb)
RETURNS TABLE(order_id uuid,order_number bigint,status public.order_status,total numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_org uuid:=public.current_organization_id(); v_customer uuid:=public.current_customer_id(); v_order public.orders%rowtype; v_line jsonb; v_product uuid; v_qty integer; v_price numeric(18,2); v_tier public.customer_tier; v_currency text; v_subtotal numeric(18,2):=0; v_existing public.orders%rowtype; v_available integer;
BEGIN
  IF v_org IS NULL OR v_customer IS NULL THEN RAISE EXCEPTION USING errcode='42501',message='authenticated customer context required'; END IF;
  IF p_idempotency_key IS NULL OR length(trim(p_idempotency_key))<16 THEN RAISE EXCEPTION USING errcode='22023',message='invalid idempotency key'; END IF;
  IF p_lines IS NULL OR jsonb_typeof(p_lines)<>'array' OR jsonb_array_length(p_lines)=0 THEN RAISE EXCEPTION USING errcode='22023',message='order lines required'; END IF;
  SELECT c.tier INTO v_tier FROM public.customers c WHERE c.id=v_customer AND c.organization_id=v_org AND c.is_active;
  IF v_tier IS NULL THEN RAISE EXCEPTION USING errcode='42501',message='active customer required'; END IF;
  SELECT * INTO v_existing FROM public.orders o WHERE o.organization_id=v_org AND o.idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF v_existing.customer_id<>v_customer OR v_existing.warehouse_id<>p_warehouse_id THEN RAISE EXCEPTION USING errcode='40001',message='idempotency key payload conflict'; END IF;
    RETURN QUERY SELECT v_existing.id,v_existing.order_number,v_existing.status,v_existing.total; RETURN;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.warehouses w WHERE w.id=p_warehouse_id AND w.organization_id=v_org AND w.is_active) THEN RAISE EXCEPTION USING errcode='42501',message='warehouse not available'; END IF;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_product:=(v_line->>'product_id')::uuid; v_qty:=(v_line->>'quantity')::integer;
    IF v_qty IS NULL OR v_qty<=0 THEN RAISE EXCEPTION USING errcode='22023',message='invalid quantity'; END IF;
    SELECT pp.amount,pl.currency INTO v_price,v_currency FROM public.product_prices pp JOIN public.price_lists pl ON pl.id=pp.price_list_id WHERE pp.organization_id=v_org AND pp.product_id=v_product AND pl.organization_id=v_org AND pl.tier=v_tier AND pl.is_active AND pp.valid_from<=now() AND(pp.valid_to IS NULL OR pp.valid_to>now()) ORDER BY pp.valid_from DESC LIMIT 1;
    IF v_price IS NULL THEN RAISE EXCEPTION USING errcode='P0001',message='authorized price unavailable'; END IF;
    SELECT ib.quantity INTO v_available FROM public.inventory_balances ib WHERE ib.organization_id=v_org AND ib.warehouse_id=p_warehouse_id AND ib.product_id=v_product FOR UPDATE;
    IF NOT FOUND OR v_available<v_qty THEN RAISE EXCEPTION USING errcode='P0001',message='insufficient stock'; END IF;
    v_subtotal:=v_subtotal+(v_price*v_qty);
  END LOOP;
  INSERT INTO public.orders(organization_id,customer_id,warehouse_id,status,currency,subtotal,total,idempotency_key,created_by)
  VALUES(v_org,v_customer,p_warehouse_id,'pending',coalesce(v_currency,'YER'),v_subtotal,v_subtotal,p_idempotency_key,auth.uid()) RETURNING * INTO v_order;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_product:=(v_line->>'product_id')::uuid; v_qty:=(v_line->>'quantity')::integer;
    SELECT pp.amount INTO v_price FROM public.product_prices pp JOIN public.price_lists pl ON pl.id=pp.price_list_id WHERE pp.organization_id=v_org AND pp.product_id=v_product AND pl.organization_id=v_org AND pl.tier=v_tier AND pl.is_active AND pp.valid_from<=now() AND(pp.valid_to IS NULL OR pp.valid_to>now()) ORDER BY pp.valid_from DESC LIMIT 1;
    UPDATE public.inventory_balances ib SET quantity=ib.quantity-v_qty,updated_at=now() WHERE ib.organization_id=v_org AND ib.warehouse_id=p_warehouse_id AND ib.product_id=v_product AND ib.quantity>=v_qty;
    IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0001',message='inventory changed; retry order'; END IF;
    INSERT INTO public.inventory_movements(organization_id,warehouse_id,product_id,delta,source_type,source_id,actor_id) VALUES(v_org,p_warehouse_id,v_product,-v_qty,'order',v_order.id,auth.uid());
    INSERT INTO public.order_items(organization_id,order_id,product_id,quantity,unit_price,pricing_tier) VALUES(v_org,v_order.id,v_product,v_qty,v_price,v_tier);
  END LOOP;
  INSERT INTO public.order_status_history(organization_id,order_id,from_status,to_status,actor_id) VALUES(v_org,v_order.id,NULL,'pending',auth.uid());
  INSERT INTO public.outbox_events(organization_id,aggregate_type,aggregate_id,event_type,payload) VALUES(v_org,'order',v_order.id,'order.created',jsonb_build_object('order_id',v_order.id,'order_number',v_order.order_number));
  INSERT INTO public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) VALUES(v_org,auth.uid(),'order.create','order',v_order.id,'success',jsonb_build_object('order_number',v_order.order_number));
  RETURN QUERY SELECT v_order.id,v_order.order_number,v_order.status,v_order.total;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO v_existing FROM public.orders o WHERE o.organization_id=v_org AND o.idempotency_key=p_idempotency_key;
  IF FOUND THEN RETURN QUERY SELECT v_existing.id,v_existing.order_number,v_existing.status,v_existing.total; ELSE RAISE; END IF;
END; $$;

-- Remove accidental default PUBLIC/anon execution from the public function surface.
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT p.oid::regprocedure AS fn FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon',r.fn);
  END LOOP;
END $$;

-- Required operational FK indexes (organization_id is included to preserve tenant-aware join paths).
CREATE INDEX IF NOT EXISTS cash_accounts_branch_org_fk_idx ON public.cash_accounts(branch_id,organization_id);
CREATE INDEX IF NOT EXISTS cash_transactions_account_org_fk_idx ON public.cash_transactions(cash_account_id,organization_id);
CREATE INDEX IF NOT EXISTS expenses_branch_org_fk_idx ON public.expenses(branch_id,organization_id);
CREATE INDEX IF NOT EXISTS expenses_cash_account_org_fk_idx ON public.expenses(cash_account_id,organization_id);
CREATE INDEX IF NOT EXISTS operational_invoice_items_invoice_org_fk_idx ON public.operational_invoice_items(invoice_id,organization_id);
CREATE INDEX IF NOT EXISTS operational_invoice_items_product_org_fk_idx ON public.operational_invoice_items(product_id,organization_id);
CREATE INDEX IF NOT EXISTS operational_invoice_items_org_fk_idx ON public.operational_invoice_items(organization_id);
CREATE INDEX IF NOT EXISTS operational_invoices_customer_org_fk_idx ON public.operational_invoices(customer_id,organization_id);
CREATE INDEX IF NOT EXISTS operational_invoices_order_org_fk_idx ON public.operational_invoices(order_id,organization_id);
CREATE INDEX IF NOT EXISTS operational_invoices_org_fk_idx ON public.operational_invoices(organization_id);
CREATE INDEX IF NOT EXISTS payments_cash_account_org_fk_idx ON public.payments(cash_account_id,organization_id);
CREATE INDEX IF NOT EXISTS payments_invoice_org_fk_idx ON public.payments(invoice_id,organization_id);
CREATE INDEX IF NOT EXISTS purchase_order_items_product_org_fk_idx ON public.purchase_order_items(product_id,organization_id);
CREATE INDEX IF NOT EXISTS purchase_order_items_purchase_order_org_fk_idx ON public.purchase_order_items(purchase_order_id,organization_id);
CREATE INDEX IF NOT EXISTS purchase_order_items_org_fk_idx ON public.purchase_order_items(organization_id);
CREATE INDEX IF NOT EXISTS purchase_orders_supplier_org_fk_idx ON public.purchase_orders(supplier_id,organization_id);
CREATE INDEX IF NOT EXISTS purchase_orders_warehouse_org_fk_idx ON public.purchase_orders(warehouse_id,organization_id);
CREATE INDEX IF NOT EXISTS purchase_orders_org_fk_idx ON public.purchase_orders(organization_id);
CREATE INDEX IF NOT EXISTS purchase_receipt_items_purchase_order_item_org_fk_idx ON public.purchase_receipt_items(purchase_order_item_id,organization_id);
CREATE INDEX IF NOT EXISTS purchase_receipt_items_receipt_org_fk_idx ON public.purchase_receipt_items(receipt_id,organization_id);
CREATE INDEX IF NOT EXISTS purchase_receipt_items_product_org_fk_idx ON public.purchase_receipt_items(product_id,organization_id);
CREATE INDEX IF NOT EXISTS purchase_receipt_items_org_fk_idx ON public.purchase_receipt_items(organization_id);
CREATE INDEX IF NOT EXISTS purchase_receipts_purchase_order_org_fk_idx ON public.purchase_receipts(purchase_order_id,organization_id);
CREATE INDEX IF NOT EXISTS purchase_receipts_warehouse_org_fk_idx ON public.purchase_receipts(warehouse_id,organization_id);
CREATE INDEX IF NOT EXISTS purchase_receipts_org_fk_idx ON public.purchase_receipts(organization_id);
