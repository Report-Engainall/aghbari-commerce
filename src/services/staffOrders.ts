import type { OrderStatus } from '../domain/types';
import { requireSupabase } from '../lib/supabase';
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ORDER_STATUSES: ReadonlySet<string> = new Set(['draft', 'pending', 'confirmed', 'preparing', 'ready', 'completed', 'cancelled']);
export interface StaffOrderSummary { id: string; order_number: number; customer_id: string; customer_name: string; warehouse_id: string; status: OrderStatus; total: number; currency: string; created_at: string; updated_at: string; }
export function assertStaffOrderSummary(value: unknown): StaffOrderSummary {
  if (!value || typeof value !== 'object') throw new Error('استجابة الطلب التشغيلي غير صالحة. لم يتم إثبات نجاح العملية.');
  const item = value as Record<string, unknown>;
  const id = item.id;
  const customerId = item.customer_id;
  const warehouseId = item.warehouse_id;
  if (typeof id !== 'string' || !UUID_PATTERN.test(id)) throw new Error('معرّف الطلب غير صالح. لم يتم إثبات نجاح العملية.');
  if (typeof customerId !== 'string' || !UUID_PATTERN.test(customerId)) throw new Error('معرّف العميل غير صالح. لم يتم إثبات نجاح العملية.');
  if (typeof warehouseId !== 'string' || !UUID_PATTERN.test(warehouseId)) throw new Error('معرّف المستودع غير صالح. لم يتم إثبات نجاح العملية.');
  const orderNumber = item.order_number;
  if (typeof orderNumber !== 'number' || !Number.isSafeInteger(orderNumber) || orderNumber <= 0) throw new Error('رقم الطلب التشغيلي غير صالح. لم يتم إثبات نجاح العملية.');
  const status = item.status;
  if (typeof status !== 'string' || !ORDER_STATUSES.has(status)) throw new Error('حالة الطلب التشغيلي غير صالحة. لم يتم إثبات نجاح العملية.');
  const total = item.total;
  if (typeof total !== 'number' || !Number.isFinite(total) || total < 0) throw new Error('إجمالي الطلب التشغيلي غير صالح. لم يتم إثبات نجاح العملية.');
  const currency = item.currency;
  if (typeof currency !== 'string' || !/^[A-Z]{3}$/.test(currency)) throw new Error('عملة الطلب التشغيلي غير صالحة. لم يتم إثبات نجاح العملية.');
  const customerName = item.customer_name;
  if (typeof customerName !== 'string' || !customerName.trim()) throw new Error('اسم العميل في الطلب غير صالح. لم يتم إثبات نجاح العملية.');
  const createdAt = item.created_at;
  if (typeof createdAt !== 'string' || !createdAt.trim() || Number.isNaN(Date.parse(createdAt))) throw new Error('تاريخ إنشاء الطلب غير صالح. لم يتم إثبات نجاح العملية.');
  const updatedAt = item.updated_at;
  if (typeof updatedAt !== 'string' || !updatedAt.trim() || Number.isNaN(Date.parse(updatedAt))) throw new Error('تاريخ تحديث الطلب غير صالح. لم يتم إثبات نجاح العملية.');
  return { id, order_number: orderNumber, customer_id: customerId, customer_name: customerName, warehouse_id: warehouseId, status: status as OrderStatus, total, currency, created_at: createdAt, updated_at: updatedAt };
}
export async function getStaffOrders(limit = 50): Promise<StaffOrderSummary[]> { const safeLimit = Math.min(Math.max(Math.trunc(limit), 1), 100); const { data, error } = await requireSupabase().from('orders').select('id,order_number,customer_id,warehouse_id,status,total,currency,created_at,updated_at,customers(name)').order('created_at', { ascending: false }).limit(safeLimit); if (error) throw error; return (data ?? []).map((row) => { const item = row as typeof row & { customers?: { name?: string } | null }; return assertStaffOrderSummary({ id: item.id, order_number: Number(item.order_number), customer_id: item.customer_id, customer_name: item.customers?.name ?? 'عميل غير معروف', warehouse_id: item.warehouse_id, status: item.status, total: typeof item.total === 'number' ? item.total : Number(item.total), currency: item.currency, created_at: item.created_at, updated_at: item.updated_at }); }); }
export async function transitionOrder(orderId: string, toStatus: OrderStatus): Promise<StaffOrderSummary> { if (typeof orderId !== 'string' || !UUID_PATTERN.test(orderId)) throw new Error('معرّف الطلب غير صالح.'); if (typeof toStatus !== 'string' || !ORDER_STATUSES.has(toStatus)) throw new Error('حالة انتقال الطلب غير صالحة.'); const { data, error } = await requireSupabase().rpc('transition_order', { p_order_id: orderId, p_to_status: toStatus }); if (error) throw error; return assertStaffOrderSummary(data as unknown); }
