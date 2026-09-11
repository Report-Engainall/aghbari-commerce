import { useMemo } from 'react';
import { formatMoney } from './domain/pricing';
import type { CustomerOrderSummary } from './services/customerOrders';

export default function CustomerDashboard({ orders, cartCount, online }: { orders: CustomerOrderSummary[]; cartCount: number; online: boolean }) {
  const metrics = useMemo(() => ({
    orders: orders.length,
    pending: orders.filter((order) => order.status === 'pending').length,
    completed: orders.filter((order) => order.status === 'completed').length,
    value: orders.reduce((sum, order) => sum + Number(order.total || 0), 0),
  }), [orders]);
  return <section className="portal-card customer-dashboard" id="customer-dashboard"><div className="section-heading"><div><span className="eyebrow">لوحة العميل</span><h2>ملخص حسابك</h2></div><span>{online ? 'متصل بالبيانات المباشرة' : 'دون اتصال'}</span></div><div className="metric-grid"><div><small>الطلبات الظاهرة</small><strong>{metrics.orders}</strong></div><div><small>قيد المراجعة</small><strong>{metrics.pending}</strong></div><div><small>الطلبات المكتملة</small><strong>{metrics.completed}</strong></div><div><small>قيمة الطلبات</small><strong>{formatMoney(metrics.value)}</strong></div><div><small>أصناف السلة</small><strong>{cartCount}</strong></div></div></section>;
}
