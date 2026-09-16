import { requireSupabase } from '../lib/supabase';
import type { OrderStatus } from '../domain/types';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const STATUSES = new Set<OrderStatus>(['draft', 'pending', 'confirmed', 'preparing', 'ready', 'completed', 'cancelled']);

export interface AdminOrderDetail {
  id: string;
  order_number: number;
  customer_id: string;
  customer_name: string;
  warehouse_id: string;
  status: OrderStatus;
  currency: string;
  subtotal: number;
  total: number;
  created_at: string;
  updated_at: string;
}

export interface AdminOrderLine {
  id: string;
  product_id: string;
  sku: string;
  product_name: string;
  unit: string;
  quantity: number;
  unit_price: number;
  line_total: number;
}

export interface AdminOrderStatusEvent {
  id: string;
  from_status: OrderStatus | null;
  to_status: OrderStatus;
  created_at: string;
}

function numberOf(value: unknown, label: string) {
  const n = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(n)) throw new Error(`${label} غير صالح.`);
  return n;
}

function assertUuid(value: unknown, label: string): string {
  if (typeof value !== 'string' || !UUID.test(value)) throw new Error(`${label} غير صالح.`);
  return value;
}

export async function getAdminOrderDetail(orderId: string) {
  assertUuid(orderId, 'معرّف الطلب');
  const client = requireSupabase();
  const { data: order, error: orderError } = await client
    .from('orders')
    .select('id,order_number,customer_id,warehouse_id,status,currency,subtotal,total,created_at,updated_at,customers(name)')
    .eq('id', orderId)
    .single();
  if (orderError) throw orderError;
  if (!order || !STATUSES.has(order.status as OrderStatus)) throw new Error('الطلب غير صالح.');

  const [{ data: lines, error: linesError }, { data: history, error: historyError }] = await Promise.all([
    client.from('order_items').select('id,product_id,quantity,unit_price,line_total,products:products(sku,name,unit)').eq('order_id', orderId).order('created_at'),
    client.from('order_status_history').select('id,from_status,to_status,created_at').eq('order_id', orderId).order('created_at', { ascending: true }),
  ]);
  if (linesError) throw linesError;
  if (historyError) throw historyError;

  const customer = Array.isArray(order.customers) ? order.customers[0] : order.customers;
  const detail: AdminOrderDetail = {
    id: assertUuid(order.id, 'معرّف الطلب'),
    order_number: numberOf(order.order_number, 'رقم الطلب'),
    customer_id: assertUuid(order.customer_id, 'معرّف العميل'),
    customer_name: customer && typeof customer === 'object' && typeof customer.name === 'string' ? customer.name : 'عميل غير معروف',
    warehouse_id: assertUuid(order.warehouse_id, 'معرّف المستودع'),
    status: order.status as OrderStatus,
    currency: String(order.currency),
    subtotal: numberOf(order.subtotal, 'الإجمالي الفرعي'),
    total: numberOf(order.total, 'الإجمالي'),
    created_at: String(order.created_at),
    updated_at: String(order.updated_at),
  };

  const safeLines: AdminOrderLine[] = (lines ?? []).map((item) => {
    const product = Array.isArray(item.products) ? item.products[0] ?? null : item.products ?? null;
    if (!product || typeof product !== 'object') throw new Error('بيانات منتج الطلب غير مكتملة.');
    return {
      id: assertUuid(item.id, 'معرّف سطر الطلب'),
      product_id: assertUuid(item.product_id, 'معرّف المنتج'),
      sku: String(product.sku),
      product_name: String(product.name),
      unit: String(product.unit),
      quantity: numberOf(item.quantity, 'الكمية'),
      unit_price: numberOf(item.unit_price, 'سعر الوحدة'),
      line_total: numberOf(item.line_total, 'إجمالي السطر'),
    };
  });

  const safeHistory: AdminOrderStatusEvent[] = (history ?? []).map((item) => {
    if (!STATUSES.has(item.to_status as OrderStatus) || (item.from_status !== null && !STATUSES.has(item.from_status as OrderStatus))) throw new Error('سجل حالة الطلب غير صالح.');
    return { id: assertUuid(item.id, 'معرّف سجل الحالة'), from_status: item.from_status, to_status: item.to_status, created_at: String(item.created_at) };
  });

  return { order: detail, lines: safeLines, history: safeHistory };
}
