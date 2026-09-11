import { useEffect, useMemo, useState } from 'react';
import { formatMoney } from './domain/pricing';
import { getCustomerOrders, type CustomerOrderSummary } from './services/customerOrders';

export default function CustomerDashboard({ cartCount, online }: { cartCount: number; online: boolean }) {
  const [orders, setOrders] = useState<CustomerOrderSummary[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => { let cancelled = false; if (!online) { setLoading(false); return; } setLoading(true); void getCustomerOrders(20).then((items) => { if (!cancelled) setOrders(items); }).catch(() => { if (!cancelled) setOrders([]); }).finally(() => { if (!cancelled) setLoading(false); }); return () => { cancelled = true; }; }, [online]);
  const metrics = useMemo(() => ({ orders: orders.length, pending: orders.filter((order) => order.status === 'pending').length, completed: orders.filter((order) => order.status === 'completed').length, value: orders.reduce((sum, order) => sum + Number(order.total || 0), 0) }), [orders]);
  return <section className="portal-card customer-dashboard" id="customer-dashboard"><div className="section-heading"><div><span className="eyebrow">لوحة العميل</span><h2>ملخص حسابك</h2></div><span>{loading ? 'جارٍ التحديث…' : online ? 'متصل بالبيانات المباشرة' : 'دون اتصال'}</span></div><div className="metric-grid"><div><small>الطلبات الظاهرة</small><strong>{loading ? '…' : metrics.orders}</strong></div><div><small>قيد المراجعة</small><strong>{loading ? '…' : metrics.pending}</strong></div><div><small>الطلبات المكتملة</small><strong>{loading ? '…' : metrics.completed}</strong></div><div><small>قيمة الطلبات</small><strong>{loading ? '…' : formatMoney(metrics.value)}</strong></div><div><small>أصناف السلة</small><strong>{cartCount}</strong></div></div></section>;
}
