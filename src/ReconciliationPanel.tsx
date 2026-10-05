import { useEffect, useState } from 'react';
import { supabase } from './lib/supabase';

type UserRole = 'owner' | 'admin' | 'sales' | 'warehouse' | 'viewer';
interface Dataset { id: string; source_name: string; source_fingerprint: string; status: string; }
interface ReconLine { product_name: string; sku: string; expected: number; counted: number | null; delta: number | null; }
const STATUS_LABELS: Record<string, string> = { open: 'مفتوحة', approved: 'معتمدة', applied: 'مطبقة', rolled_back: 'مراجعة', cancelled: 'ملغاة' };

export default function ReconciliationPanel({ role }: { role: UserRole }) {
  const [datasets, setDatasets] = useState<Dataset[]>([]);
  const [warehouses, setWarehouses] = useState<{ id: string; name: string }[]>([]);
  const [datasetId, setDatasetId] = useState('');
  const [warehouseId, setWarehouseId] = useState('');
  const [reconciliationId, setReconciliationId] = useState('');
  const [preview, setPreview] = useState<ReconLine[]>([]);
  const [reconStatus, setReconStatus] = useState<string>('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
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
    }).catch((e) => setError(e instanceof Error ? e.message : 'تعذر تحميل بيانات المصالحة.')).finally(() => setLoading(false));
  }, [canPreview]);

  async function loadPreview(reconId: string) {
    if (!supabase) return;
    try {
      const { data: reconData, error: reconErr } = await supabase
        .from('inventory_reconciliations').select('status').eq('id', reconId).maybeSingle();
      if (reconErr) throw reconErr;
      setReconStatus(reconData?.status ?? 'open');
      const { data: lines, error: linesErr } = await supabase
        .from('inventory_reconciliation_lines')
        .select('product_id,expected_quantity,counted_quantity,delta')
        .eq('reconciliation_id', reconId)
        .order('delta', { ascending: false })
        .limit(200);
      if (linesErr) throw linesErr;
      const productIds = (lines ?? []).map((l) => l.product_id);
      if (!productIds.length) { setPreview([]); return; }
      const { data: productRows, error: productErr } = await supabase
        .from('products').select('id,name,sku').in('id', productIds);
      if (productErr) throw productErr;
      const productMap = new Map((productRows ?? []).map((p) => [p.id, p]));
      setPreview((lines ?? []).map((l) => {
        const p = productMap.get(l.product_id);
        return { product_name: p?.name ?? l.product_id, sku: p?.sku ?? '', expected: Number(l.expected_quantity), counted: l.counted_quantity !== null ? Number(l.counted_quantity) : null, delta: l.delta !== null ? Number(l.delta) : null };
      }));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'تعذر تحميل المعاينة.');
    }
  }

  async function callRpc(name: string, args: Record<string, unknown>, success: string) {
    if (!supabase) return;
    setBusy(true); setError(null); setMessage(null);
    try {
      const { data, error: rpcError } = await supabase.rpc(name, args);
      if (rpcError) throw rpcError;
      if (name === 'create_inventory_reconciliation') {
        setReconciliationId(String(data));
        setMessage(success);
        await loadPreview(String(data));
      } else if (name === 'approve_inventory_reconciliation') {
        setReconStatus('approved');
        setMessage(success);
      } else if (name === 'apply_inventory_reconciliation') {
        setReconStatus('applied');
        setMessage(success);
        setPreview([]);
      } else if (name === 'rollback_inventory_reconciliation') {
        setReconStatus('rolled_back');
        setMessage(success);
      } else {
        setMessage(success);
      }
    } catch (e) { setError(e instanceof Error ? e.message : 'تعذر تنفيذ المصالحة.'); }
    finally { setBusy(false); }
  }

  if (!canPreview) return <div className="admin-card"><p className="access-denied">لا تملك صلاحية الوصول إلى مصالحة المخزون.</p></div>;
  return <section className="admin-card" id="reconciliation-admin" style={{ marginTop: 18 }}>
    <div className="section-heading"><div><span className="eyebrow">Onyx → Live</span><h3>مصالحـة المخزون الآمنة</h3></div><small>{loading ? 'جارٍ التحميل…' : 'المقارنة أولًا، والتعديل المباشر ممنوع.'}</small></div>
    {loading ? <div className="loading-state">جارٍ تحميل البيانات…</div> : <>
    <div className="admin-grid">
      <label>مجموعة Onyx<select aria-label="مجموعة بيانات Onyx" value={datasetId} onChange={(e) => setDatasetId(e.target.value)}><option value="">اختر مجموعة بيانات</option>{datasets.map((d) => <option key={d.id} value={d.id}>{d.source_name} · {d.status}</option>)}</select></label>
      <label>المستودع<select aria-label="مستودع المصالحة" value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)}><option value="">اختر المستودع</option>{warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}</select></label>
    </div>
    <button disabled={busy || !datasetId || !warehouseId} onClick={() => void callRpc('create_inventory_reconciliation', { p_dataset_id: datasetId, p_warehouse_id: warehouseId }, 'تم إنشاء المقارنة والمعاينة. إذا ظهرت تعارضات فلن يسمح النظام بالاعتماد.')}>مقارنة ومعاينة</button>
    {reconciliationId && <div style={{ marginTop: 12 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
        <strong>معرّف المصالحة:</strong> <span>{reconciliationId}</span>
        {reconStatus && <span className={`status status-${reconStatus === 'applied' ? 'completed' : reconStatus === 'approved' ? 'confirmed' : reconStatus === 'rolled_back' ? 'cancelled' : 'pending'}`}>{STATUS_LABELS[reconStatus] ?? reconStatus}</span>}
      </div>
      {preview.length > 0 && <div className="recon-preview" style={{ marginTop: 12 }}>
        <h4>الفروقات المكتشفة ({preview.length})</h4>
        <div className="cart-lines">{preview.slice(0, 50).map((line, i) => <article className="cart-line" key={i}>
          <div><strong>{line.product_name}</strong><small>{line.sku}</small></div>
          <div><strong>{line.counted ?? '—'}</strong><small>متوقع: {line.expected}{line.delta !== null && ` · فرق: ${line.delta > 0 ? '+' : ''}${line.delta}`}</small></div>
        </article>)}</div>
      </div>}
      {reconciliationId && preview.length === 0 && reconStatus === 'open' && <small style={{ display: 'block', marginTop: 8 }}>لا توجد فروقات في هذه المقارنة.</small>}
      {canMutate && <div className="status-actions" style={{ marginTop: 8 }}>
        <button disabled={busy || reconStatus !== 'open'} onClick={() => void callRpc('approve_inventory_reconciliation', { p_reconciliation_id: reconciliationId }, 'تم اعتماد المعاينة للتنفيذ.')}>اعتماد</button>
        <button disabled={busy || reconStatus !== 'approved'} onClick={() => void callRpc('apply_inventory_reconciliation', { p_reconciliation_id: reconciliationId }, 'تم تطبيق المصالحة داخل معاملة واحدة وتسجيل الدليل.')}>تطبيق</button>
        <button disabled={busy || reconStatus !== 'applied'} onClick={() => void callRpc('rollback_inventory_reconciliation', { p_reconciliation_id: reconciliationId }, 'تمت استعادة الحالة السابقة وتسجيل حركة التراجع.')}>تراجع</button>
      </div>}
    </div>}
    </>}
    {error && <div className="error-banner" role="alert">{error}</div>}
    {message && <div className="success" role="status">{message}</div>}
  </section>;
}
