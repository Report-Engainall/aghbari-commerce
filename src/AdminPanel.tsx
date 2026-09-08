import { useCallback, useEffect, useMemo, useState } from 'react';
import type { CustomerTier, OrderStatus } from './domain/types';
import { formatMoney } from './domain/pricing';
import { adjustInventory, createCategory, setProductPrice, upsertProduct } from './services/admin';
import { commitProductImport, stageProductImport } from './services/importExcel';
import { getCategories, type CategoryOption } from './services/categories';
import { uploadProductImage } from './services/imagePipeline';
import { getStaffOrders, transitionOrder, type StaffOrderSummary } from './services/staffOrders';
import { supabase } from './lib/supabase';
import PurchasingPanel from './PurchasingPanel';
import ExportPanel from './ExportPanel';
import CustomerPanel from './CustomerPanel';
import InventoryPanel from './InventoryPanel';
import FinancePanel from './FinancePanel';

interface StaffProduct { id: string; sku: string; name: string; unit: string; }
interface Warehouse { id: string; name: string; }
type UserRole = 'owner' | 'admin' | 'sales' | 'warehouse' | 'viewer';
const tiers: CustomerTier[] = ['retail', 'wholesale', 'distributor'];
const STAFF_ROLES = new Set<UserRole>(['owner', 'admin', 'sales', 'warehouse']);
const STATUS_LABELS: Record<OrderStatus, string> = { draft: 'مسودة', pending: 'قيد المراجعة', confirmed: 'مؤكد', preparing: 'قيد التجهيز', ready: 'جاهز', completed: 'مكتمل', cancelled: 'ملغي' };

function allowedNextStatuses(status: OrderStatus, role: UserRole): OrderStatus[] {
  if (status === 'pending' && ['owner', 'admin', 'sales'].includes(role)) return ['confirmed', 'cancelled'];
  if (status === 'confirmed' && ['owner', 'admin', 'warehouse'].includes(role)) return ['preparing', 'cancelled'];
  if (status === 'preparing' && ['owner', 'admin', 'warehouse'].includes(role)) return ['ready', 'cancelled'];
  if (status === 'ready' && ['owner', 'admin', 'warehouse', 'sales'].includes(role)) return ['completed'];
  return [];
}

export default function AdminPanel({ role }: { role: UserRole }) {
  const [products, setProducts] = useState<StaffProduct[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [categories, setCategories] = useState<CategoryOption[]>([]);
  const [orders, setOrders] = useState<StaffOrderSummary[]>([]);
  const [ordersLoading, setOrdersLoading] = useState(false);
  const [product, setProduct] = useState({ sku: '', name: '', unit: 'كرتون', categoryId: '', description: '' });
  const [category, setCategory] = useState({ name: '', slug: '', parentId: '' });
  const [selectedProduct, setSelectedProduct] = useState('');
  const [tier, setTier] = useState<CustomerTier>('wholesale');
  const [price, setPrice] = useState('');
  const [warehouseId, setWarehouseId] = useState('');
  const [delta, setDelta] = useState('');
  const [reason, setReason] = useState('');
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [importFile, setImportFile] = useState<File | null>(null);
  const [importJobId, setImportJobId] = useState<string | null>(null);
  const [importPreview, setImportPreview] = useState<{ rows: number; invalid: number } | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const reload = useCallback(async () => {
    if (!supabase) return;
    setOrdersLoading(true);
    try {
      const [{ data: productRows, error: productError }, { data: warehouseRows, error: warehouseError }, categoryRows, orderRows] = await Promise.all([
        supabase.from('products').select('id,sku,name,unit').eq('status', 'active').order('name').limit(200),
        supabase.from('warehouses').select('id,name').eq('is_active', true).order('created_at'),
        getCategories(), getStaffOrders(50)
      ]);
      if (productError) throw productError;
      if (warehouseError) throw warehouseError;
      setProducts((productRows ?? []) as StaffProduct[]); setCategories(categoryRows); setOrders(orderRows);
      const nextWarehouses = (warehouseRows ?? []) as Warehouse[]; setWarehouses(nextWarehouses);
      if (!warehouseId && nextWarehouses[0]) setWarehouseId(nextWarehouses[0].id);
    } finally { setOrdersLoading(false); }
  }, [warehouseId]);

  useEffect(() => { void reload().catch((e) => setError(e instanceof Error ? e.message : 'تعذر تحميل مركز التحكم.')); }, [reload]);

  async function run(action: () => Promise<unknown>, success: string) {
    setBusy(true); setError(null); setMessage(null);
    try { await action(); setMessage(success); await reload(); }
    catch (e) { setError(e instanceof Error ? e.message : 'تعذر تنفيذ العملية.'); }
    finally { setBusy(false); }
  }

  async function uploadImage() {
    if (!selectedProduct || !imageFile) return;
    await run(async () => { await uploadProductImage(selectedProduct, imageFile); setImageFile(null); }, 'تم رفع الصورة ومعالجتها وتسجيلها بأمان.');
  }

  async function stageImport() {
    if (!importFile) return;
    setBusy(true); setError(null); setMessage(null); setImportJobId(null); setImportPreview(null);
    try {
      const result = await stageProductImport(importFile);
      setImportPreview({ rows: result.rows.length, invalid: result.diagnostics.length });
      if (result.jobId) { setImportJobId(result.jobId); setMessage('تمت المعاينة والتحقق على الخادم. يمكنك اعتماد الاستيراد الذري.'); }
      else setError('الملف يحتوي أخطاء ويجب إصلاحها قبل الاستيراد.');
    } catch (e) { setError(e instanceof Error ? e.message : 'تعذر تجهيز ملف الاستيراد.'); }
    finally { setBusy(false); }
  }

  async function commitImport() {
    if (!importJobId || !warehouseId) return;
    await run(async () => { const result = await commitProductImport(importJobId, warehouseId); setImportJobId(null); setImportFile(null); setImportPreview(null); return result; }, 'تم اعتماد الاستيراد بالكامل وتسجيل أثر المخزون والتدقيق.');
  }

  async function changeOrderStatus(orderId: string, status: OrderStatus) {
    await run(async () => transitionOrder(orderId, status), `تم تحديث حالة الطلب إلى: ${STATUS_LABELS[status]}.`);
  }

  const canCatalog = role === 'owner' || role === 'admin' || role === 'sales';
  const canCategory = role === 'owner' || role === 'admin';
  const canInventory = role === 'owner' || role === 'admin' || role === 'warehouse';
  const canOrderWorkflow = STAFF_ROLES.has(role);
  const canFinance = ['owner', 'admin', 'sales'].includes(role);

  const operational = useMemo(() => {
    const pending = orders.filter((order) => order.status === 'pending').length;
    const preparing = orders.filter((order) => order.status === 'preparing' || order.status === 'confirmed').length;
    const ready = orders.filter((order) => order.status === 'ready').length;
    const completed = orders.filter((order) => order.status === 'completed').length;
    const cancelled = orders.filter((order) => order.status === 'cancelled').length;
    const value = orders.reduce((sum, order) => sum + Number(order.total || 0), 0);
    return { pending, preparing, ready, completed, cancelled, value };
  }, [orders]);

  const sections = useMemo(() => [
    canCatalog && ['catalog-admin', 'المنتجات والأسعار'],
    canInventory && ['inventory-admin', 'المخزون والتوريد'],
    canOrderWorkflow && ['orders-admin', 'الطلبات'],
    canFinance && ['finance-admin', 'المالية'],
    canCatalog && ['customers-admin', 'العملاء'],
  ].filter(Boolean) as [string, string][], [canCatalog, canInventory, canOrderWorkflow, canFinance]);

  return <section className="admin-panel" id="account">
    <div className="section-heading"><div><span className="eyebrow">إدارة التشغيل</span><h2>مركز التحكم</h2></div><span>الصلاحيات تُفرض على الخادم أيضًا</span></div>

    <div className="command-overview" aria-label="ملخص التشغيل">
      <article className="command-stat command-stat-primary"><span>الطلبات قيد المراجعة</span><strong>{operational.pending}</strong><small>{operational.pending ? 'تحتاج إجراءً الآن' : 'لا توجد طلبات معلقة'}</small></article>
      <article className="command-stat"><span>قيد التجهيز</span><strong>{operational.preparing}</strong><small>مؤكد أو قيد التجهيز</small></article>
      <article className="command-stat"><span>جاهز للتسليم</span><strong>{operational.ready}</strong><small>بانتظار الإكمال</small></article>
      <article className="command-stat"><span>مكتمل</span><strong>{operational.completed}</strong><small>من الطلبات الظاهرة</small></article>
      <article className="command-stat"><span>قيمة الطلبات</span><strong>{formatMoney(operational.value)}</strong><small>{operational.cancelled} ملغي</small></article>
    </div>

    {sections.length > 0 && <nav className="command-nav" aria-label="أقسام مركز التحكم">{sections.map(([id, label]) => <a key={id} href={`#${id}`}>{label}</a>)}</nav>}

    <div className="admin-grid" id="catalog-admin">
      {canCatalog && <form className="admin-card" onSubmit={(e) => { e.preventDefault(); void run(() => upsertProduct({ sku: product.sku, name: product.name, unit: product.unit, categoryId: product.categoryId || null, description: product.description || null }), 'تم حفظ المنتج.'); }}>
        <h3>منتج جديد</h3><input aria-label="SKU" placeholder="SKU" value={product.sku} onChange={(e) => setProduct({ ...product, sku: e.target.value })} required />
        <input aria-label="اسم المنتج" placeholder="اسم المنتج" value={product.name} onChange={(e) => setProduct({ ...product, name: e.target.value })} required />
        <input aria-label="الوحدة" placeholder="الوحدة" value={product.unit} onChange={(e) => setProduct({ ...product, unit: e.target.value })} required />
        <select aria-label="تصنيف المنتج" value={product.categoryId} onChange={(e) => setProduct({ ...product, categoryId: e.target.value })}><option value="">بدون تصنيف</option>{categories.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select>
        <textarea aria-label="وصف المنتج" placeholder="وصف المنتج (اختياري)" value={product.description} onChange={(e) => setProduct({ ...product, description: e.target.value })} rows={3} />
        <button disabled={busy}>حفظ المنتج</button>
      </form>}
      {canCategory && <form className="admin-card" onSubmit={(e) => { e.preventDefault(); void run(() => createCategory(category.name.trim(), category.slug.trim(), category.parentId || null), 'تم إنشاء التصنيف.'); }}>
        <h3>تصنيف جديد</h3><input aria-label="اسم التصنيف" placeholder="اسم التصنيف" value={category.name} onChange={(e) => setCategory({ ...category, name: e.target.value })} required />
        <input aria-label="معرف التصنيف" placeholder="slug مثل rice" value={category.slug} onChange={(e) => setCategory({ ...category, slug: e.target.value })} required pattern="[a-z0-9]+(?:-[a-z0-9]+)*" />
        <select aria-label="التصنيف الأب" value={category.parentId} onChange={(e) => setCategory({ ...category, parentId: e.target.value })}><option value="">تصنيف رئيسي</option>{categories.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select>
        <button disabled={busy}>حفظ التصنيف</button>
      </form>}
      {canCatalog && <form className="admin-card" onSubmit={(e) => { e.preventDefault(); if (!selectedProduct || !price) return; void run(() => setProductPrice(selectedProduct, tier, Number(price)), 'تم تحديث السعر الفعّال.'); }}>
        <h3>تسعير حسب الفئة</h3><select aria-label="المنتج" value={selectedProduct} onChange={(e) => setSelectedProduct(e.target.value)} required><option value="">اختر منتجًا</option>{products.map((p) => <option key={p.id} value={p.id}>{p.name} · {p.sku}</option>)}</select>
        <select aria-label="تصنيف العميل" value={tier} onChange={(e) => setTier(e.target.value as CustomerTier)}>{tiers.map((item) => <option key={item} value={item}>{item}</option>)}</select>
        <input aria-label="السعر" type="number" min="0" step="0.01" placeholder="السعر" value={price} onChange={(e) => setPrice(e.target.value)} required /><button disabled={busy}>اعتماد السعر</button>
      </form>}
      {canCatalog && <form className="admin-card" onSubmit={(e) => { e.preventDefault(); void uploadImage(); }}>
        <h3>صورة المنتج</h3><select aria-label="منتج الصورة" value={selectedProduct} onChange={(e) => setSelectedProduct(e.target.value)} required><option value="">اختر منتجًا</option>{products.map((p) => <option key={p.id} value={p.id}>{p.name} · {p.sku}</option>)}</select>
        <input aria-label="صورة المنتج" type="file" accept="image/jpeg,image/png,image/webp" onChange={(e) => setImageFile(e.target.files?.[0] ?? null)} required /><small>يتم التحويل إلى WebP وضغط الصورة قبل التخزين.</small><button disabled={busy || !selectedProduct || !imageFile}>رفع الصورة</button>
      </form>}
      {canCatalog && <form className="admin-card" onSubmit={(e) => { e.preventDefault(); void stageImport(); }}>
        <h3>استيراد Excel آمن</h3><input aria-label="ملف المنتجات" type="file" accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" onChange={(e) => { setImportFile(e.target.files?.[0] ?? null); setImportJobId(null); setImportPreview(null); }} required />
        {importPreview && <small>الصفوف: {importPreview.rows} · الأخطاء: {importPreview.invalid}</small>}{!importJobId ? <button disabled={busy || !importFile}>رفع ومعاينة</button> : <button disabled={busy || !warehouseId} onClick={(e) => { e.preventDefault(); void commitImport(); }}>اعتماد الاستيراد الذري</button>}
      </form>}
    </div>

    <div id="orders-admin">
      {canOrderWorkflow && <div className="cart-panel"><div className="section-heading"><div><span className="eyebrow">التشغيل</span><h2>إدارة الطلبات</h2></div><span>{orders.length} طلبات</span></div>{ordersLoading ? <div className="cart-empty">جارٍ تحميل الطلبات…</div> : !orders.length ? <div className="cart-empty">لا توجد طلبات تشغيلية بعد.</div> : <div className="cart-lines">{orders.map((order) => <article className="cart-line" key={order.id}><div><strong>طلب #{order.order_number}</strong><small>العميل: {order.customer_name}</small></div><div><strong>{formatMoney(order.total)} {order.currency}</strong><small>الحالة: {STATUS_LABELS[order.status]}</small></div><div className="status-actions">{allowedNextStatuses(order.status, role).map((next) => <button key={next} disabled={busy} onClick={() => void changeOrderStatus(order.id, next)} aria-label={`تحويل الطلب ${order.order_number} إلى ${STATUS_LABELS[next]}`}>{STATUS_LABELS[next]}</button>)}</div></article>)}</div>}</div>}
    </div>

    {error && <div className="error-banner" role="alert">{error}</div>}{message && <div className="success" role="status">{message}</div>}
    <div id="inventory-admin">{canInventory && <InventoryPanel role={role} />}</div>
    <div>{canInventory && <PurchasingPanel role={role} />}</div>
    <div id="finance-admin">{canFinance && <FinancePanel role={role} />}</div>
    <div id="customers-admin">{canCatalog && <CustomerPanel role={role} />}</div>
    {canInventory && <ExportPanel role={role} />}

    {canInventory && <form className="admin-card" style={{ marginTop: 18 }} onSubmit={(e) => { e.preventDefault(); if (!selectedProduct || !warehouseId || !delta) return; void run(() => adjustInventory(warehouseId, selectedProduct, Number(delta), reason.trim()), 'تم تعديل المخزون وتسجيل الحركة.'); }}>
      <h3>تسوية مخزون سريعة</h3><select aria-label="المستودع" value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)} required><option value="">اختر المستودع</option>{warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}</select>
      <select aria-label="المنتج" value={selectedProduct} onChange={(e) => setSelectedProduct(e.target.value)} required><option value="">اختر المنتج</option>{products.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}</select>
      <input aria-label="التغيير" type="number" step="1" placeholder="+ أو - الكمية" value={delta} onChange={(e) => setDelta(e.target.value)} required /><input aria-label="سبب التعديل" placeholder="سبب التعديل" value={reason} onChange={(e) => setReason(e.target.value)} required /><button disabled={busy}>تسجيل الحركة</button>
    </form>}
  </section>;
}
