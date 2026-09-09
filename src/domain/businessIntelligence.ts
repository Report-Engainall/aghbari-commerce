import type { CustomerOrderSummary } from '../services/customerOrders';

type IntelligenceOrder = CustomerOrderSummary & { customer_id?: string };

export interface BusinessSnapshot {
  orderCount: number;
  grossValue: number;
  averageOrderValue: number;
  pendingCount: number;
  activeFulfillmentCount: number;
  completedCount: number;
  cancelledCount: number;
  completionRate: number;
  cancellationRate: number;
}

export interface StatusBreakdown { status: string; count: number; value: number; }
export type BusinessSignalKind = 'pending_backlog' | 'cancellation_rate' | 'repeat_customer' | 'customer_concentration';
export interface BusinessSignal {
  kind: BusinessSignalKind;
  severity: 'info' | 'warning' | 'critical';
  title: string;
  detail: string;
  evidence: { orderCount: number; customerCount: number; grossValue: number };
}

function finiteMoney(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
}

export function buildBusinessSnapshot(orders: CustomerOrderSummary[]): BusinessSnapshot {
  const orderCount = orders.length;
  const grossValue = orders.reduce((sum, order) => sum + finiteMoney(order.total), 0);
  const pendingCount = orders.filter((order) => order.status === 'pending').length;
  const activeFulfillmentCount = orders.filter((order) => ['confirmed', 'preparing', 'ready'].includes(order.status)).length;
  const completedCount = orders.filter((order) => order.status === 'completed').length;
  const cancelledCount = orders.filter((order) => order.status === 'cancelled').length;
  return { orderCount, grossValue, averageOrderValue: orderCount ? grossValue / orderCount : 0, pendingCount, activeFulfillmentCount, completedCount, cancelledCount, completionRate: orderCount ? completedCount / orderCount : 0, cancellationRate: orderCount ? cancelledCount / orderCount : 0 };
}

export function buildStatusBreakdown(orders: CustomerOrderSummary[]): StatusBreakdown[] {
  const map = new Map<string, { count: number; value: number }>();
  for (const order of orders) {
    const current = map.get(order.status) ?? { count: 0, value: 0 };
    current.count += 1;
    current.value += finiteMoney(order.total);
    map.set(order.status, current);
  }
  return [...map.entries()].map(([status, metrics]) => ({ status, ...metrics })).sort((a, b) => b.value - a.value);
}

/** Deterministic evidence layer; AI may explain these signals but cannot invent their source metrics. */
export function buildBusinessSignals(orders: IntelligenceOrder[]): BusinessSignal[] {
  const snapshot = buildBusinessSnapshot(orders);
  const customerTotals = new Map<string, number>();
  for (const order of orders) {
    const customerKey = order.customer_id ?? `order:${order.id}`;
    customerTotals.set(customerKey, (customerTotals.get(customerKey) ?? 0) + finiteMoney(order.total));
  }
  const customerCount = customerTotals.size;
  const evidence = { orderCount: snapshot.orderCount, customerCount, grossValue: snapshot.grossValue };
  const signals: BusinessSignal[] = [];
  if (snapshot.pendingCount >= 5 || (snapshot.orderCount > 0 && snapshot.pendingCount / snapshot.orderCount >= 0.25)) signals.push({ kind: 'pending_backlog', severity: snapshot.pendingCount >= 10 ? 'critical' : 'warning', title: 'تراكم طلبات قيد المراجعة', detail: `${snapshot.pendingCount} من ${snapshot.orderCount} طلبًا ما زالت قيد المراجعة.`, evidence });
  if (snapshot.cancelledCount >= 3 || (snapshot.orderCount > 0 && snapshot.cancellationRate >= 0.1)) signals.push({ kind: 'cancellation_rate', severity: snapshot.cancellationRate >= 0.2 ? 'critical' : 'warning', title: 'معدل الإلغاء يحتاج مراجعة', detail: `${snapshot.cancelledCount} طلبًا ملغيًا من إجمالي ${snapshot.orderCount}.`, evidence });
  if (orders.length > customerCount) signals.push({ kind: 'repeat_customer', severity: 'info', title: 'وجود عملاء متكررين', detail: `${orders.length - customerCount} طلبًا إضافيًا فوق أول طلب لكل عميل ضمن البيانات الحالية.`, evidence });
  const topCustomerValue = Math.max(0, ...customerTotals.values());
  if (snapshot.grossValue > 0 && customerCount > 1 && topCustomerValue / snapshot.grossValue >= 0.5) signals.push({ kind: 'customer_concentration', severity: 'warning', title: 'تركيز مرتفع في قيمة المبيعات', detail: 'عميل واحد يمثل 50% أو أكثر من قيمة الطلبات ضمن العينة الحالية.', evidence });
  return signals;
}
