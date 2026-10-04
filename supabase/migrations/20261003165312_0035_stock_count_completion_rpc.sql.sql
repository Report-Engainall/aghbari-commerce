/*
# Stock Count Completion RPC

## Purpose
Creates the `stock_count_sessions` and `stock_count_lines` tables (if they don't
already exist) and the `complete_stock_count` SECURITY DEFINER function that
closes an open stock-count session, computes variances, adjusts inventory
balances, and writes auditable inventory movements.

## New Tables
1. `stock_count_sessions` — header for a physical inventory count per warehouse.
   - `id` (uuid PK)
   - `organization_id` (uuid FK → organizations)
   - `warehouse_id` (uuid FK → warehouses)
   - `idempotency_key` (text, unique per org)
   - `status` (enum: open / completed)
   - `started_by` (uuid FK → auth.users)
   - `notes` (text, nullable)
   - `created_at`, `updated_at` (timestamptz)

2. `stock_count_lines` — one row per product in a count session.
   - `id` (uuid PK)
   - `organization_id` (uuid FK → organizations)
   - `session_id` (uuid FK → stock_count_sessions, cascade delete)
   - `product_id` (uuid FK → products)
   - `expected_quantity` (integer, not null)
   - `counted_quantity` (integer, nullable until counted)
   - `variance` (integer, nullable, set at completion)
   - `counted_at` (timestamptz, nullable)
   - `created_at`, `updated_at` (timestamptz)

## New Function
- `complete_stock_count(p_session_id uuid)` — SECURITY DEFINER, locks the session
  row, verifies every line has been counted, sets status='completed', computes
  variance per line, updates `inventory_balances` to the counted quantity, and
  inserts `inventory_movements` rows for non-zero variances. Returns
  `{ status, session_id, adjusted_lines }`.

## Security
- RLS enabled on both tables.
- SELECT policies scoped to staff within the same organization.
- No direct INSERT/UPDATE/DELETE policies — mutations go through RPCs only.
- `complete_stock_count` executable by `authenticated` only.
*/

-- ── Enum ──────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE t.typname = 'stock_count_status' AND n.nspname = 'public'
  ) THEN
    CREATE TYPE public.stock_count_status AS ENUM ('open', 'completed');
  END IF;
END $$;

-- ── Tables ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.stock_count_sessions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  warehouse_id     uuid NOT NULL REFERENCES public.warehouses(id) ON DELETE RESTRICT,
  idempotency_key  text NOT NULL,
  status           public.stock_count_status NOT NULL DEFAULT 'open',
  started_by       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  notes            text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, idempotency_key)
);

CREATE TABLE IF NOT EXISTS public.stock_count_lines (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  session_id       uuid NOT NULL REFERENCES public.stock_count_sessions(id) ON DELETE CASCADE,
  product_id       uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  expected_quantity integer NOT NULL DEFAULT 0,
  counted_quantity  integer,
  variance          integer,
  counted_at        timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (session_id, product_id)
);

CREATE INDEX IF NOT EXISTS stock_count_lines_session_idx
  ON public.stock_count_lines(session_id);
CREATE INDEX IF NOT EXISTS stock_count_sessions_org_warehouse_idx
  ON public.stock_count_sessions(organization_id, warehouse_id);

-- ── RLS ───────────────────────────────────────────────────────────
ALTER TABLE public.stock_count_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_count_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "stock_count_sessions_read_staff" ON public.stock_count_sessions;
CREATE POLICY "stock_count_sessions_read_staff"
  ON public.stock_count_sessions FOR SELECT
  TO authenticated
  USING (organization_id = public.current_organization_id() AND public.is_staff());

DROP POLICY IF EXISTS "stock_count_lines_read_staff" ON public.stock_count_lines;
CREATE POLICY "stock_count_lines_read_staff"
  ON public.stock_count_lines FOR SELECT
  TO authenticated
  USING (organization_id = public.current_organization_id() AND public.is_staff());

-- ── complete_stock_count function ────────────────────────────────
CREATE OR REPLACE FUNCTION public.complete_stock_count(
  p_session_id uuid
)
RETURNS TABLE(status text, session_id uuid, adjusted_lines integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org       uuid := public.current_organization_id();
  v_role      public.user_role := public.current_role();
  v_session   public.stock_count_sessions%rowtype;
  v_adjusted  integer := 0;
  v_line      record;
  v_existing  integer;
BEGIN
  IF v_org IS NULL OR v_role NOT IN ('owner','admin','warehouse') THEN
    RAISE EXCEPTION USING errcode='42501', message='stock count access required';
  END IF;

  -- Lock the session so no line can be updated concurrently.
  SELECT * INTO v_session
  FROM public.stock_count_sessions
  WHERE id = p_session_id AND organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode='P0002', message='stock count not found';
  END IF;

  IF v_session.status <> 'open' THEN
    RAISE EXCEPTION USING errcode='22023', message='stock count is not open';
  END IF;

  -- Every line must have been counted.
  IF EXISTS (
    SELECT 1 FROM public.stock_count_lines
    WHERE session_id = p_session_id AND counted_quantity IS NULL
  ) THEN
    RAISE EXCEPTION USING errcode='22023', message='all stock count lines must be counted before completion';
  END IF;

  -- Close the session.
  UPDATE public.stock_count_sessions
  SET status = 'completed', updated_at = now()
  WHERE id = p_session_id;

  -- Process each line: compute variance, adjust balance, write movement.
  FOR v_line IN
    SELECT product_id, expected_quantity, counted_quantity
    FROM public.stock_count_lines
    WHERE session_id = p_session_id
  LOOP
    UPDATE public.stock_count_lines
    SET variance = v_line.counted_quantity - v_line.expected_quantity,
        updated_at = now()
    WHERE session_id = p_session_id AND product_id = v_line.product_id;

    IF v_line.counted_quantity <> v_line.expected_quantity THEN
      -- Upsert inventory_balances to the counted quantity.
      SELECT quantity INTO v_existing
      FROM public.inventory_balances
      WHERE warehouse_id = v_session.warehouse_id AND product_id = v_line.product_id
        AND organization_id = v_org;

      IF FOUND THEN
        UPDATE public.inventory_balances
        SET quantity = v_line.counted_quantity, updated_at = now()
        WHERE warehouse_id = v_session.warehouse_id AND product_id = v_line.product_id
          AND organization_id = v_org;
      ELSE
        INSERT INTO public.inventory_balances(organization_id, warehouse_id, product_id, quantity)
        VALUES (v_org, v_session.warehouse_id, v_line.product_id, v_line.counted_quantity);
      END IF;

      INSERT INTO public.inventory_movements(
        organization_id, warehouse_id, product_id, delta, source_type, source_id, actor_id
      ) VALUES (
        v_org, v_session.warehouse_id, v_line.product_id,
        v_line.counted_quantity - v_line.expected_quantity,
        'stock_count', p_session_id, auth.uid()
      );

      v_adjusted := v_adjusted + 1;
    END IF;
  END LOOP;

  INSERT INTO public.audit_events(
    organization_id, actor_id, action, target_type, target_id, result, metadata
  ) VALUES (
    v_org, auth.uid(), 'stock_count.complete', 'stock_count', p_session_id, 'success',
    jsonb_build_object('adjusted_lines', v_adjusted)
  );

  RETURN QUERY SELECT 'completed'::text, p_session_id, v_adjusted;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_stock_count(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_stock_count(uuid) TO authenticated;
