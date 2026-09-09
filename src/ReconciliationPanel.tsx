import { useEffect, useState } from 'react';
import { supabase } from './lib/supabase';

type UserRole = 'owner' | 'admin' | 'sales' | 'warehouse' | 'viewer';
interface Dataset { id: string; source_name: string; source_fingerprint: string; status: string; }

export default function ReconciliationPanel({ role }: { role: UserRole }) {
  const [datasets, setDatasets] = useState<Dataset[]>([]);
  const [warehouses, setWarehouses] = useState<{ id: string; name: string }[]>([]);
  const [datasetId, setDatasetId] = useState('');
  const [warehouseId, setWarehouseId] = useState('');
  const [reconciliationId, setReconciliationId] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const canPreview = ['owner', 'admin', 'warehouse'].includes(role);
  const canMutate = ['owner', 'admin'].includes(role);

  useEffect(() => {
    if (!supabase || !canPreview) return;
    void Promise.all([
      supabase.from('onyx_datasets').select('id,source_name,source_fingerprint,status').in('status', ['processed', 'validated']).order('created_at', { ascending: false }).limit(50),
      supabase.from('warehouses').select('id,name').eq('is_active', true).order('created_at'),
    ]).then(([d, w]) => {
      if (d.error) throw d.error;
      if (w.error) throw w.error;
      setDatasets((d.data ?? []) as Dataset[]);
      setWarehouses((w.data ?? []) as { id: string; name: string }[]);
    }).catch((e) => setError(e instanceof Error ? e.message : 'تعذر تحميل بيانات المصالحة.'));
  }, [canPreview]);

  async function callRpc(name: string, args: Record<string, unknown>, success: string) {
    if (!supabase) return;
    setBusy(true); setError(null); setMessage(null);
    try {
      const { data, error: rpcError } = await supabase.rpc(name, args);
      if (rpcError) throw rpcError;
      if (name === 'create_inventory_reconciliation') setReconciliationId(String(data));
      setMessage(success);
    } catch (e) { setError(e instanceof Error ? e.message : 'تعذر تنفيذ المصالحة.'); }
    finally { setBusy(false); }
  }

  if (!canPreview) return null;
  return <section className="admin-card" id="reconciliation-admin" style={{ marginTop: 18 }}>
    <div className="section-heading"><div><span className="eyebrow">Onyx → Live</span><h3>مصالحـة المخزون الآمنة</h3></div><small>المقارنة أولًا، والتعديل المباشر ممنوع.</small></div>
    <div className="admin-grid">
      <label>مجموعة Onyx<select aria-label="مجموعة بيانات Onyx" value={datasetId} onChange={(e) => setDatasetId(e.target.value)}><option value="">اختر مجموعة بيانات</option>{datasets.map((d) => <option key={d.id} value={d.id}>{d.source_name} · {d.status}</option>)}</select></label>
      <label>المستودع<select aria-label="مستودع المصالحة" value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)}><option value="">اختر المستودع</option>{warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}</select></label>
    </div>
    <button disabled={busy || !datasetId || !warehouseId} onClick={() => void callRpc('create_inventory_reconciliation', { p_dataset_id: datasetId, p_warehouse_id: warehouseId }, 'تم إنشاء المقارنة والمعاينة. إذا ظهرت تعارضات فلن يسمح النظام بالاعتماد.')}>Compare + Preview</button>
    {reconciliationId && <div style={{ marginTop: 12 }}><strong>معرّف المصالحة:</strong> {reconciliationId}
      {canMutate && <div className="status-actions" style={{ marginTop: 8 }}>
        <button disabled={busy} onClick={() => void callRpc('approve_inventory_reconciliation', { p_reconciliation_id: reconciliationId }, 'تم اعتماد المعاينة للتنفيذ.')}>Approval</button>
        <button disabled={busy} onClick={() => void callRpc('apply_inventory_reconciliation', { p_reconciliation_id: reconciliationId }, 'تم تطبيق المصالحة داخل معاملة واحدة وتسجيل الدليل.')}>Apply</button>
        <button disabled={busy} onClick={() => void callRpc('rollback_inventory_reconciliation', { p_reconciliation_id: reconciliationId }, 'تمت استعادة الحالة السابقة وتسجيل حركة التراجع.')}>Rollback</button>
      </div>}
    </div>}
    {error && <div className="error-banner" role="alert">{error}</div>}
    {message && <div className="success" role="status">{message}</div>}
  </section>;
}
