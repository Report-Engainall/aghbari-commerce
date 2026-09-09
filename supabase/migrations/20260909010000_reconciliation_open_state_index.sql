-- Fast, tenant-scoped retrieval of actionable reconciliation records.
CREATE INDEX IF NOT EXISTS inventory_reconciliations_open_state_idx
  ON public.inventory_reconciliations (organization_id, status, created_at DESC)
  WHERE status IN ('preview', 'ready', 'failed');
