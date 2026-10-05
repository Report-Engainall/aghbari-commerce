import { useCallback, useEffect, useState } from 'react';
import { supabase } from './lib/supabase';
import { completeStockCount, getLowStock, getOpenStockCount, getStockCountLines, setStockCountLine, setStockThreshold, startStockCount, transferInventory, type LowStockRow, type StockCountLine, type StockCountSession } from './services/inventory';

type UserRole = 'owner' | 'admin' | 'sales' | 'warehouse' | 'viewer';
interface Product { id: string; sku: string; name: string; }
interface Warehouse { id: string; name: string; }

export default function InventoryPanel({ role }: { role: UserRole }) {
  const canUse = ['owner','admin','warehouse'].includes(role);
  const [products, setProducts] = useState<Product[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [lowStock, setLowStock] = useState<LowStockRow[]>([]);
  const [stockCount, setStockCount] = useState<StockCountSession | null>(null);
  const [stockLines, setStockLines] = useState<StockCountLine[]>([]);
  const [countWarehouse, setCountWarehouse] = useState('');
  const [countNotes, setCountNotes] = useState('');
  const [source, setSource] = useState('');
  const [destination, setDestination] = useState('');
  const [productId, setProductId] = useState('');
  const [quantity, setQuantity] = useState('1');
  const [notes, setNotes] = useState('');
  const [thresholdWarehouse, setThresholdWarehouse] = useState('');
  const [thresholdProduct, setThresholdProduct] = useState('');
  const [minQuantity, setMinQuantity] = useState('0');
  const [reorderQuantity, setReorderQuantity] = useState('1');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const reload = useCallback(async () => {
    if (!supabase || !canUse) return;
    const [productResult, warehouseResult, lowRows, openCount] = await Promise.all([
      supabase.from('products').select('id,sku,name').eq('status','active').order('name').limit(500),
      supabase.from('warehouses').select('id,name').eq('is_active',true).order('created_at'),
      getLowStock(),
      getOpenStockCount()
    ]);
    const { data: productRows, error: productError } = productResult;
    const { data: warehouseRows, error: warehouseError } = warehouseResult;
    if (productError) throw productError;
    if (warehouseError) throw warehouseError;
    const nextWarehouses = (warehouseRows ?? []) as Warehouse[];
    setProducts((productRows ?? []) as Product[]); setWarehouses(nextWarehouses); setLowStock(lowRows); setStockCount(openCount);
    if (openCount) setStockLines(await getStockCountLines(openCount.id));
    else setStockLines([]);
    if (!source && nextWarehouses[0]) setSource(nextWarehouses[0].id);
    if (!destination && nextWarehouses[1]) setDestination(nextWarehouses[1].id);
    if (!countWarehouse && nextWarehouses[0]) setCountWarehouse(nextWarehouses[0].id);
    if (!thresholdWarehouse && nextWarehouses[0]) setThresholdWarehouse(nextWarehouses[0].id);
    if (!productId && productRows?.[0]) setProductId(productRows[0].id);
    if (!thresholdProduct && productRows?.[0]) setThresholdProduct(productRows[0].id);
  }, [canUse, countWarehouse, destination, productId, source, thresholdWarehouse, thresholdProduct]);

  useEffect(() => { void reload().then(() => setLoading(false)).catch((e) => { setError(e instanceof Error ? e.message : 'تعذر تحميل المخزون.'); setLoading(false); }); }, [reload]);

  async function run(action: () => Promise<unknown>, success: string) {
    setBusy(true); setError(null); setMessage(null);
    try { await action(); setMessage(success); await reload(); }
    catch (e) { setError(e instanceof Error ? e.message : 'تعذر تنفيذ العملية.'); }
    finally { setBusy(false); }
  }

  if (!canUse) return <div className="admin-card"><p className="access-denied">لا تملك صلاحية الوصول إلى إدارة المخزون.</p></div>;
  const makeKey = (prefix: string) => `agh-${prefix}-${crypto.randomUUID()}`;
  const productName = new Map(products.map((p) => [p.id, `${p.name} · ${p.sku}`]));
  const countCompleted = stockLines.filter((line) => line.counted_quantity !== null).length;

  return <div className="cart-panel" id="inventory">
    <div className="section-heading"><div><span className="eyebrow">المخزون</span><h2>النقل والجرد والتنبيهات التشغيلية</h2></div><span>{loading?'جارٍ التحميل…':`${lowStock.length} أصناف منخفضة`}</span></div>
    <div className="admin-grid">
      <form className="admin-card" onSubmit={(e) => { e.preventDefault(); void run(() => transferInventory(source,destination,makeKey('transfer'),[{productId,quantity:Number(quantity)}],notes), 'تم نقل المخزون ذريًا وتسجيل الحركتين.'); }}>
        <h3>تحويل بين المستودعات</h3>
        <select aria-label="المستودع المصدر" value={source} onChange={(e) => setSource(e.target.value)} required><option value="">من المستودع</option>{warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}</select>
        <select aria-label="المستودع الوجهة" value={destination} onChange={(e) => setDestination(e.target.value)} required><option value="">إلى المستودع</option>{warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}</select>
        <select aria-label="منتج التحويل" value={productId} onChange={(e) => setProductId(e.target.value)} required><option value="">اختر المنتج</option>{products.map((p) => <option key={p.id} value={p.id}>{p.name} · {p.sku}</option>)}</select>
        <input aria-label="كمية التحويل" type="number" min="1" max="100000" step="1" value={quantity} onChange={(e) => setQuantity(e.target.value)} required />
        <input aria-label="ملاحظات التحويل" placeholder="ملاحظة (اختياري)" value={notes} onChange={(e) => setNotes(e.target.value)} />
        <button disabled={busy || !source || !destination || source === destination}>تنفيذ التحويل</button>
      </form>

      <form className="admin-card" onSubmit={(e) => { e.preventDefault(); void run(() => setStockThreshold(thresholdWarehouse,thresholdProduct,Number(minQuantity),Number(reorderQuantity)), 'تم حفظ حد إعادة الطلب.'); }}>
        <h3>حد إعادة الطلب</h3>
        <select aria-label="مستودع الحد" value={thresholdWarehouse} onChange={(e) => setThresholdWarehouse(e.target.value)} required><option value="">اختر المستودع</option>{warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}</select>
        <select aria-label="منتج الحد" value={thresholdProduct} onChange={(e) => setThresholdProduct(e.target.value)} required><option value="">اختر المنتج</option>{products.map((p) => <option key={p.id} value={p.id}>{p.name} · {p.sku}</option>)}</select>
        <input aria-label="الحد الأدنى" type="number" min="0" step="1" value={minQuantity} onChange={(e) => setMinQuantity(e.target.value)} required />
        <input aria-label="كمية إعادة الطلب" type="number" min="1" step="1" value={reorderQuantity} onChange={(e) => setReorderQuantity(e.target.value)} required />
        <button disabled={busy}>حفظ الحد</button>
      </form>

      <div className="admin-card">
        <h3>جرد مخزون فعلي</h3>
        {!stockCount ? <form onSubmit={(e) => { e.preventDefault(); void run(() => startStockCount(countWarehouse,makeKey('stock-count'),countNotes), 'بدأت جلسة الجرد وتم أخذ لقطة الكميات المتوقعة.'); }}>
          <select aria-label="مستودع الجرد" value={countWarehouse} onChange={(e) => setCountWarehouse(e.target.value)} required><option value="">اختر المستودع</option>{warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}</select>
          <input aria-label="ملاحظات الجرد" placeholder="ملاحظة الجرد (اختياري)" value={countNotes} onChange={(e) => setCountNotes(e.target.value)} />
          <small>لا يتم تعديل الرصيد عند البدء؛ التسوية تحدث فقط بعد اكتمال العد واعتماده.</small>
          <button disabled={busy || !countWarehouse}>بدء الجرد</button>
        </form> : <div>
          <div className="section-heading"><span>{countCompleted} / {stockLines.length} تم عدّه</span><button disabled={busy || countCompleted !== stockLines.length} onClick={() => void run(() => completeStockCount(stockCount.id), 'اكتمل الجرد وتمت تسوية الفروقات وتسجيلها.')} >اعتماد الجرد</button></div>
          <div className="cart-lines">{stockLines.map((line) => <label className="cart-line" key={line.id}><div><strong>{productName.get(line.product_id) ?? line.product_id}</strong><small>المتوقع عند بدء الجرد: {line.expected_quantity}</small></div><input aria-label={`الكمية المعدودة ${productName.get(line.product_id) ?? line.product_id}`} type="number" min="0" step="1" value={line.counted_quantity ?? ''} onChange={(e) => { const value = e.target.value; setStockLines((current) => current.map((item) => item.id === line.id ? { ...item, counted_quantity: value === '' ? null : Number(value) } : item)); }} onBlur={() => { if (line.counted_quantity !== null) void run(() => setStockCountLine(stockCount.id,line.product_id,line.counted_quantity!), 'تم حفظ العد.'); }} /></label>)}</div>
        </div>}
      </div>

      <div className="admin-card"><h3>الأصناف التي تحتاج إجراء</h3>{loading ? <div className="loading-state">جارٍ التحميل…</div> : !lowStock.length ? <small>لا توجد أصناف تحت حدود إعادة الطلب.</small> : <div className="cart-lines">{lowStock.slice(0,20).map((row) => <article className="cart-line" key={`${row.warehouse_id}:${row.product_id}`}><div><strong>{row.product_name}</strong><small>{row.sku} · {row.warehouse_name}</small></div><div><strong>{row.current_quantity}</strong><small>الحد {row.min_quantity} · إعادة {row.reorder_quantity}</small></div></article>)}</div>}</div>
    </div>
    {error && <div className="error-banner" role="alert">{error}</div>}{message && <div className="success" role="status">{message}</div>}
  </div>;
}
