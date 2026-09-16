import { useState } from 'react';
import { formatMoney } from './domain/pricing';
import type { CustomerOrderSummary } from './services/customerOrders';
import { getCustomerOrderDetail, type CustomerOrderStatusEvent } from './services/customerOrderDetails';

const labels: Record<CustomerOrderStatusEvent['to_status'], string> = { draft: 'مسودة', pending: 'قيد المراجعة', confirmed: 'مؤكد', preparing: 'قيد التجهيز', ready: 'جاهز', completed: 'مكتمل', cancelled: 'ملغي' };

export default function CustomerOrderDetailPanel({ orders }: { orders: CustomerOrderSummary[] }) {
  const [selected, setSelected] = useState<string | null>(null);
  const [detail, setDetail] = useState<Awaited<ReturnType<typeof getCustomerOrderDetail>> | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function open(orderId: string) {
    setSelected(orderId); setBusy(true); setError(null); setDetail(null);
    try { setDetail(await getCustomerOrderDetail(orderId)); } catch (e) { setError(e instanceof Error ? e.message : 'تعذر تحميل تفاصيل الطلب.'); } finally { setBusy(false); }
  }

  return <section className="portal-card" id="order-details"><div className="section-heading"><div><span className="eyebrow">تفاصيل الطلب</span><h2>المسار الكامل للطلب</h2></div></div>
    {!orders.length ? <div className="empty-state">ستظهر تفاصيل الطلبات هنا بعد إنشاء أول طلب.</div> : <div className="portal-list">{orders.slice(0, 10).map((order) => <button className="portal-row portal-row-button" key={order.id} onClick={() => void open(order.id)}><div><strong>طلب #{order.order_number}</strong><small>{new Date(order.created_at).toLocaleString('ar-YE')}</small></div><div><strong>{formatMoney(order.total, order.currency)}</strong><span className="status">{labels[order.status]}</span></div></button>)}</div>}
    {busy && <div className="loading-state">جارٍ تحميل تفاصيل الطلب وسجل حالته…</div>}
    {error && <div className="error-banner" role="alert">{error}</div>}
    {selected && detail && <div className="detail-box"><div className="section-heading"><div><span className="eyebrow">طلب #{detail.order.order_number}</span><h3>تفاصيل الطلب</h3></div><button onClick={() => { setSelected(null); setDetail(null); }}>إغلاق</button></div><div className="portal-list">{detail.lines.map((line) => <article className="portal-row" key={line.id}><div><strong>{line.product?.name ?? 'منتج غير متاح'}</strong><small>{line.product?.sku ?? line.product_id} · {line.quantity} {line.product?.unit ?? ''}</small></div><span>{formatMoney(line.line_total, detail.order.currency)}</span></article>)}<div className="cart-total"><span>الإجمالي</span><strong>{formatMoney(detail.order.total, detail.order.currency)}</strong></div></div><div className="status-timeline"><h3>سجل الحالة</h3>{detail.history.map((event) => <div className="timeline-row" key={event.id}><span>{new Date(event.created_at).toLocaleString('ar-YE')}</span><strong>{labels[event.to_status]}</strong></div>)}</div></div>}
  </section>;
}
