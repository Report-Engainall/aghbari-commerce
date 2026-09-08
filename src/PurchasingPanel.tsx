import { useCallback, useEffect, useState } from 'react';
import { createPurchaseOrder, createSupplier, approvePurchaseOrder, receivePurchaseOrder, submitPurchaseOrder } from './services/purchasing';
import { supabase } from './lib/supabase';

type UserRole = 'owner' | 'admin' | 'sales' | 'warehouse' | 'viewer';
type Status = 'draft' | 'submitted' | 'approved' | 'partially_received' | 'received' | 'cancelled';
interface Product { id: string; sku: string; name: string; unit: string; }
interface Warehouse { id: string; name: string; }
interface Supplier { id: string; name: string; phone: string | null; }
interface PurchaseOrder { id: string; purchase_order_number: number; supplier_id: string; warehouse_id: string; status: Status; total: number; currency: string; }
interface PurchaseItem { id: string; purchase_order_id: string; product_id: string; quantity_ordered: number; quantity_received: number; unit_cost: number; }

const statusLabels: Record<Status, string> = {
  draft: 'مسودة', submitted: 'مرسل', approved: 'معتمد', partially_received: 'استلام جزئي', received: 'مستلم', cancelled: 'ملغي'
};

export default function PurchasingPanel({ role }: { role: UserRole }) {
  const canManage = role === 'owner' || role === 'admin' || role === 'warehouse';
  const canApprove = role === 'owner' || role === 'admin';
  const [products, setProducts] = useState<Product[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [suppliers, setSuppliers] = useState<Supplier[]>([]);
  const [orders, setOrders] = useState<PurchaseOrder[]>([]);
  const [items, setItems] = useState<PurchaseItem[]>([]);
  const [supplierName, setSupplierName] = useState('');
  const [supplierPhone, setSupplierPhone] = useState('');
  const [supplierAddress, setSupplierAddress] = useState('');
  const [supplierId, setSupplierId] = useState('');
  const [productId, setProductId] = useState('');
  const [warehouseId, setWarehouseId] = useState('');
  const [quantity, setQuantity] = useState('1');
  const [unitCost, setUnitCost] = useState('0');
  const [selectedOrderId, setSelectedOrderId] = useState('');
  const [receiveItemId, setReceiveItemId] = useState('');
  const [receiveQuantity, setReceiveQuantity] = useState('1');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!supabase || !canManage) return;
    const [{ data: productRows, error: productError }, { data: warehouseRows, error: warehouseError }, { data: supplierRows, error: supplierError }, { data: orderRows, error: orderError }, { data: itemRows, error: itemError }] = await Promise.all([
      supabase.from('products').select('id,sku,name,unit').eq('status', 'active').order('name').limit(500),
      supabase.from('warehouses').select('id,name').eq('is_active', true).order('created_at'),
      supabase.from('suppliers').select('id,name,phone').eq('is_active', true).order('name').limit(200),
      supabase.from('purchase_orders').select('id,purchase_order_number,supplier_id,warehouse_id,status,total,currency').order('created_at', { ascending: false }).limit(100),
      supabase.from('purchase_order_items').select('id,purchase_order_id,product_id,quantity_ordered,quantity_received,unit_cost').order('created_at')
    ]);
    if (productError) throw productError;
    if (warehouseError) throw warehouseError;
    if (supplierError) throw supplierError;
    if (orderError) throw orderError;
    if (itemError) throw itemError;
    setProducts((productRows ?? []) as Product[]); setWarehouses((warehouseRows ?? []) as Warehouse[]); setSuppliers((supplierRows ?? []) as Supplier[]);
    const nextOrders = (orderRows ?? []) as PurchaseOrder[]; setOrders(nextOrders); setItems((itemRows ?? []) as PurchaseItem[]);
    if (!warehouseId && warehouseRows?.[0]) setWarehouseId(warehouseRows[0].id);
    if (!supplierId && supplierRows?.[0]) setSupplierId(supplierRows[0].id);
    if (!productId && productRows?.[0]) setProductId(productRows[0].id);
    if (!selectedOrderId) setSelectedOrderId(nextOrders.find((o) => o.status === 'approved' || o.status === 'partially_received')?.id ?? '');
  }, [canManage, productId, selectedOrderId, supplierId, warehouseId]);

  useEffect(() => { void load().catch((e) => setError(e instanceof Error ? e.message : 'تعذر تحميل المشتريات.')); }, [load]);

  async function run(action: () => Promise<unknown>, success: string) {
    setBusy(true); setError(null); setMessage(null);
    try { await action(); setMessage(success); await load(); }
    catch (e) { setError(e instanceof Error ? e.message : 'تعذر تنفيذ العملية.'); }
    finally { setBusy(false); }
  }

  if (!canManage) return null;
  const selectedOrderItems = items.filter((item) => item.purchase_order_id === selectedOrderId && item.quantity_received < item.quantity_ordered);
  const supplierNameFor = (id: string) => suppliers.find((supplier) => supplier.id === id)?.name ?? 'مورد';
  const productNameFor = (id: string) => products.find((product) => product.id === id)?.name ?? id;
  const selectedReceiveItem = selectedOrderItems.find((item) => item.id === receiveItemId) ?? selectedOrderItems[0];

  return <div className="cart-panel" id="purchasing">
    <div className="section-heading"><div><span className="eyebrow">المشتريات والمستودع</span><h2>دورة التوريد</h2></div><span>{orders.length} أوامر شراء</span></div>
    <div className="admin-grid">
      <form className="admin-card" onSubmit={(e) => { e.preventDefault(); void run(() => createSupplier({ name: supplierName, phone: supplierPhone, address: supplierAddress }), 'تم إنشاء المورد وتسجيل أثر العملية.').then(() => { setSupplierName(''); setSupplierPhone(''); setSupplierAddress(''); }); }}>
        <h3>مورد جديد</h3>
        <input aria-label="اسم المورد" placeholder="اسم المورد" value={supplierName} onChange={(e) => setSupplierName(e.target.value)} required />
        <input aria-label="هاتف المورد" placeholder="الهاتف" value={supplierPhone} onChange={(e) => setSupplierPhone(e.target.value)} />
        <input aria-label="عنوان المورد" placeholder="العنوان" value={supplierAddress} onChange={(e) => setSupplierAddress(e.target.value)} />
        <button disabled={busy}>حفظ المورد</button>
      </form>

      <form className="admin-card" onSubmit={(e) => { e.preventDefault(); void run(async () => { await createPurchaseOrder({ supplierId, warehouseId, idempotencyKey: `agh-po-${crypto.randomUUID()}`, lines: [{ productId, quantity: Number(quantity), unitCost: Number(unitCost) }], currency: 'YER' }); }, 'تم إنشاء أمر الشراء.'); }}>
        <h3>أمر شراء جديد</h3>
        <select aria-label="المورد" value={supplierId} onChange={(e) => setSupplierId(e.target.value)} required><option value="">اختر المورد</option>{suppliers.map((supplier) => <option key={supplier.id} value={supplier.id}>{supplier.name}</option>)}</select>
        <select aria-label="مستودع الاستلام" value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)} required><option value="">اختر المستودع</option>{warehouses.map((warehouse) => <option key={warehouse.id} value={warehouse.id}>{warehouse.name}</option>)}</select>
        <select aria-label="منتج الشراء" value={productId} onChange={(e) => setProductId(e.target.value)} required><option value="">اختر المنتج</option>{products.map((product) => <option key={product.id} value={product.id}>{product.name} · {product.sku}</option>)}</select>
        <input aria-label="كمية الشراء" type="number" min="1" step="1" value={quantity} onChange={(e) => setQuantity(e.target.value)} required />
        <input aria-label="تكلفة الوحدة" type="number" min="0" step="0.01" value={unitCost} onChange={(e) => setUnitCost(e.target.value)} required />
        <button disabled={busy || !supplierId || !warehouseId || !productId}>إنشاء أمر شراء</button>
      </form>

      <div className="admin-card"><h3>اعتماد أوامر الشراء</h3>{orders.length === 0 ? <small>لا توجد أوامر شراء بعد.</small> : <div className="cart-lines">{orders.slice(0, 8).map((order) => <article className="cart-line" key={order.id}><div><strong>أمر #{order.purchase_order_number}</strong><small>{supplierNameFor(order.supplier_id)}</small></div><div><strong>{order.total} {order.currency}</strong><small>{statusLabels[order.status]}</small></div><div className="status-actions">{order.status === 'draft' && <button disabled={busy} onClick={() => void run(() => submitPurchaseOrder(order.id), 'تم إرسال أمر الشراء للاعتماد.')}>إرسال</button>}{canApprove && order.status === 'submitted' && <button disabled={busy} onClick={() => void run(() => approvePurchaseOrder(order.id), 'تم اعتماد أمر الشراء.')}>اعتماد</button>}</div></article>)}</div>}</div>

      <form className="admin-card" onSubmit={(e) => { e.preventDefault(); if (!selectedOrderId || !selectedReceiveItem) return; void run(() => receivePurchaseOrder({ purchaseOrderId: selectedOrderId, idempotencyKey: `agh-receive-${crypto.randomUUID()}`, lines: [{ purchaseOrderItemId: selectedReceiveItem.id, productId: selectedReceiveItem.product_id, quantity: Number(receiveQuantity) }] }), 'تم الاستلام وتحديث المخزون وتسجيل الحركة.'); }}>
        <h3>استلام البضاعة</h3>
        <select aria-label="أمر الشراء" value={selectedOrderId} onChange={(e) => { setSelectedOrderId(e.target.value); setReceiveItemId(''); }} required><option value="">اختر أمرًا معتمدًا</option>{orders.filter((order) => order.status === 'approved' || order.status === 'partially_received').map((order) => <option key={order.id} value={order.id}>#{order.purchase_order_number} · {supplierNameFor(order.supplier_id)}</option>)}</select>
        <select aria-label="صنف الاستلام" value={receiveItemId || selectedReceiveItem?.id || ''} onChange={(e) => setReceiveItemId(e.target.value)} required><option value="">اختر الصنف</option>{selectedOrderItems.map((item) => <option key={item.id} value={item.id}>{productNameFor(item.product_id)} · متبقٍ {item.quantity_ordered - item.quantity_received}</option>)}</select>
        <input aria-label="كمية الاستلام" type="number" min="1" max={selectedReceiveItem ? selectedReceiveItem.quantity_ordered - selectedReceiveItem.quantity_received : undefined} step="1" value={receiveQuantity} onChange={(e) => setReceiveQuantity(e.target.value)} required />
        <button disabled={busy || !selectedOrderId || !selectedReceiveItem}>تسجيل الاستلام</button>
      </form>
    </div>
    {error && <div className="error-banner" role="alert">{error}</div>}{message && <div className="success" role="status">{message}</div>}
  </div>;
}
