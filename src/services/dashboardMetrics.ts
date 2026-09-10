import { requireSupabase } from '../lib/supabase';

export interface StaffDashboardMetrics {
  orders_total: number;
  orders_pending: number;
  orders_confirmed: number;
  orders_preparing: number;
  orders_ready: number;
  orders_completed: number;
  orders_cancelled: number;
  completed_sales: number;
  active_customers: number;
  active_products: number;
  available_stock: number;
  receivables_issued: number;
}

function finiteNonNegative(value: unknown, field: string): number {
  const number = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(number) || number < 0) throw new Error(`مؤشر ${field} غير صالح.`);
  return number;
}

export function assertStaffDashboardMetrics(value: unknown): StaffDashboardMetrics {
  if (!value || typeof value !== 'object') throw new Error('استجابة مؤشرات التشغيل غير صالحة.');
  const row = value as Record<string, unknown>;
  return {
    orders_total: finiteNonNegative(row.orders_total, 'الطلبات'),
    orders_pending: finiteNonNegative(row.orders_pending, 'الطلبات المعلقة'),
    orders_confirmed: finiteNonNegative(row.orders_confirmed, 'الطلبات المؤكدة'),
    orders_preparing: finiteNonNegative(row.orders_preparing, 'الطلبات قيد التجهيز'),
    orders_ready: finiteNonNegative(row.orders_ready, 'الطلبات الجاهزة'),
    orders_completed: finiteNonNegative(row.orders_completed, 'الطلبات المكتملة'),
    orders_cancelled: finiteNonNegative(row.orders_cancelled, 'الطلبات الملغاة'),
    completed_sales: finiteNonNegative(row.completed_sales, 'المبيعات المكتملة'),
    active_customers: finiteNonNegative(row.active_customers, 'العملاء'),
    active_products: finiteNonNegative(row.active_products, 'المنتجات'),
    available_stock: finiteNonNegative(row.available_stock, 'المخزون'),
    receivables_issued: finiteNonNegative(row.receivables_issued, 'الذمم'),
  };
}

export async function getStaffDashboardMetrics(): Promise<StaffDashboardMetrics> {
  const { data, error } = await requireSupabase().rpc('get_staff_dashboard_metrics');
  if (error) throw error;
  const row = Array.isArray(data) ? data[0] : data;
  return assertStaffDashboardMetrics(row);
}
