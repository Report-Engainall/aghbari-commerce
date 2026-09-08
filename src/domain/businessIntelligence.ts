import type { CustomerOrderSummary } from '../services/customerOrders';

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

export interface StatusBreakdown {
  status: string;
  count: number;
  value: number;
}

export function buildBusinessSnapshot(orders: CustomerOrderSummary[]): BusinessSnapshot {
  const orderCount = orders.length;
  const grossValue = orders.reduce((sum, order) => sum + Number(order.total || 0), 0);
  const pendingCount = orders.filter((order) => order.status === 'pending').length;
  const activeFulfillmentCount = orders.filter((order) => ['confirmed', 'preparing', 'ready'].includes(order.status)).length;
  const completedCount = orders.filter((order) => order.status === 'completed').length;
  const cancelledCount = orders.filter((order) => order.status === 'cancelled').length;
  return {
    orderCount,
    grossValue,
    averageOrderValue: orderCount ? grossValue / orderCount : 0,
    pendingCount,
    activeFulfillmentCount,
    completedCount,
    cancelledCount,
    completionRate: orderCount ? completedCount / orderCount : 0,
    cancellationRate: orderCount ? cancelledCount / orderCount : 0,
  };
}

export function buildStatusBreakdown(orders: CustomerOrderSummary[]): StatusBreakdown[] {
  const map = new Map<string, { count: number; value: number }>();
  for (const order of orders) {
    const current = map.get(order.status) ?? { count: 0, value: 0 };
    current.count += 1;
    current.value += Number(order.total || 0);
    map.set(order.status, current);
  }
  return [...map.entries()]
    .map(([status, metrics]) => ({ status, ...metrics }))
    .sort((a, b) => b.value - a.value);
}
