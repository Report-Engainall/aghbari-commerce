import { useCallback, useEffect, useMemo, useState } from 'react';
import type { CustomerTier } from './domain/types';
import { getCategories, type CategoryOption } from './services/categories';
import { getCatalog, type CatalogItem } from './services/catalog';
import { setProductPrice, upsertProduct } from './services/admin';

type UserRole = 'owner' | 'admin' | 'sales' | 'warehouse' | 'viewer';
const PAGE_SIZE = 15;
const TIERS: CustomerTier[] = ['retail', 'wholesale', 'distributor'];
const TIER_LABELS: Record<CustomerTier, string> = { retail: 'تجزئة', wholesale: 'جملة', distributor: 'موزع' };

export default function ProductCatalogPanel({ role }: { role: UserRole }) {
  const canManage = role === 'owner' || role === 'admin';
  const canPrice = ['owner', 'admin', 'sales'].includes(role);
  const [products, setProducts] = useState<CatalogItem[]>([]);
  const [categories, setCategories] = useState<CategoryOption[]>([]);
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState<'all' | 'active' | 'inactive'>('all');
  const [page, setPage] = useState(1);
  const [editing, setEditing] = useState<CatalogItem | null>(null);
  const [priceProduct, setPriceProduct] = useState('');
  const [priceTier, setPriceTier] = useState<CustomerTier>('wholesale');
  const [price, setPrice] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const reload = useCallback(async () => {
    const [rows, nextCategories] = await Promise.all([getCatalog('', null, 500, 0), getCategories()]);
    setProducts(rows);
    setCategories(nextCategories);
  }, []);
  useEffect(() => { void reload().catch((e) => setError(e instanceof Error ? e.message : 'تعذر تحميل المنتجات.')); }, [reload]);

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return products.filter((product) => {
      const matches = !needle || `${product.name} ${product.sku} ${product.unit}`.toLowerCase().includes(needle);
      const matchesStatus = status === 'all' || product.status === status;
      return matches && matchesStatus;
    });
  }, [products, query, status]);
  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const visible = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);
  useEffect(() => { if (page > pageCount) setPage(pageCount); }, [page, pageCount]);

  async function run(action: () => Promise<unknown>, success: string) {
    setBusy(true); setError(null); setMessage(null);
    try { await action(); setMessage(success); await reload(); }
    catch (e) { setError(e instanceof Error ? e.message : 'تعذر تنفيذ العملية.'); }
    finally { setBusy(false); }
  }

  if (!canManage && !canPrice) return null;
  return <div className="cart-panel" id="product-catalog-admin">
    <div className="section-heading"><div><span className="eyebrow">الكتالوج</span><h2>إدارة المنتجات والأسعار</h2></div><span>{filtered.length} من {products.length} منتجًا</span></div>
    <div className="admin-filters">
      <input aria-label="بحث المنتجات" placeholder="بحث بالاسم أو SKU أو الوحدة" value={query} onChange={(e) => { setQuery(e.target.value); setPage(1); }} />
      <select aria-label="حالة المنتج" value={status} onChange={(e) => { setStatus(e.target.value as typeof status); setPage(1); }}><option value="all">كل الحالات</option><option value="active">نشط</option><option value="inactive">متوقف</option></select>
    </div>
    {!visible.length ? <div className="cart-empty">لا توجد منتجات مطابقة.</div> : <div className="cart-lines">{visible.map((product) => <article className="cart-line" key={product.id}>
      <div><strong>{product.name}</strong><small>{product.sku} · {product.unit} · {product.status === 'inactive' ? 'متوقف' : 'نشط'}</small></div>
      <div className="status-actions">
        {canManage && <button type="button" disabled={busy} onClick={() => setEditing(product)}>تعديل</button>}
        {canManage && <button type="button" disabled={busy} onClick={() => void run(() => upsertProduct({ productId: product.id, sku: product.sku, name: product.name, unit: product.unit, categoryId: product.category_id ?? null, description: product.description ?? null, status: product.status === 'inactive' ? 'active' : 'inactive' }), product.status === 'inactive' ? 'تم تفعيل المنتج.' : 'تم إيقاف المنتج.')}>{product.status === 'inactive' ? 'تفعيل' : 'إيقاف'}</button>}
        {canPrice && <button type="button" disabled={busy} onClick={() => setPriceProduct(product.id)}>تسعير</button>}
      </div>
    </article>)}</div>}
    {filtered.length > PAGE_SIZE && <div className="pagination"><button type="button" disabled={page <= 1 || busy} onClick={() => setPage((v) => v - 1)}>السابق</button><span>صفحة {page} من {pageCount}</span><button type="button" disabled={page >= pageCount || busy} onClick={() => setPage((v) => v + 1)}>التالي</button></div>}

    {editing && <form className="admin-card" onSubmit={(e) => { e.preventDefault(); const current = editing; void run(() => upsertProduct({ productId: current.id, sku: current.sku, name: current.name, unit: current.unit, categoryId: current.category_id ?? null, description: current.description ?? null, status: current.status === 'inactive' ? 'inactive' : 'active' }), 'تم تحديث المنتج وتسجيل أثر العملية.'); setEditing(null); }}>
      <h3>تعديل المنتج</h3><input aria-label="SKU المنتج" value={editing.sku} onChange={(e) => setEditing({ ...editing, sku: e.target.value })} required maxLength={100} />
      <input aria-label="اسم المنتج" value={editing.name} onChange={(e) => setEditing({ ...editing, name: e.target.value })} required maxLength={200} />
      <input aria-label="وحدة المنتج" value={editing.unit} onChange={(e) => setEditing({ ...editing, unit: e.target.value })} required maxLength={50} />
      <select aria-label="تصنيف المنتج" value={editing.category_id ?? ''} onChange={(e) => setEditing({ ...editing, category_id: e.target.value || null })}><option value="">بدون تصنيف</option>{categories.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select>
      <textarea aria-label="وصف المنتج" value={editing.description ?? ''} onChange={(e) => setEditing({ ...editing, description: e.target.value })} rows={3} maxLength={2000} />
      <div><button disabled={busy}>حفظ التعديل</button><button type="button" disabled={busy} onClick={() => setEditing(null)}>إلغاء</button></div>
    </form>}

    {priceProduct && <form className="admin-card" onSubmit={(e) => { e.preventDefault(); const productId = priceProduct; void run(() => setProductPrice(productId, priceTier, Number(price)), 'تم اعتماد السعر الجديد.'); setPrice(''); setPriceProduct(''); }}>
      <h3>تحديث السعر الفعّال</h3><select aria-label="فئة السعر" value={priceTier} onChange={(e) => setPriceTier(e.target.value as CustomerTier)}>{TIERS.map((tier) => <option key={tier} value={tier}>{TIER_LABELS[tier]}</option>)}</select>
      <input aria-label="السعر" type="number" min="0" step="0.01" value={price} onChange={(e) => setPrice(e.target.value)} required placeholder="السعر" />
      <div><button disabled={busy}>اعتماد السعر</button><button type="button" disabled={busy} onClick={() => setPriceProduct('')}>إلغاء</button></div>
    </form>}
    {error && <div className="error-banner" role="alert">{error}</div>}{message && <div className="success" role="status">{message}</div>}
  </div>;
}
