import { requireSupabase } from '../lib/supabase';
import type { OrderStatus } from '../domain/types';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const STATUSES = new Set<OrderStatus>(['draft','pending','confirmed','preparing','ready','completed','cancelled']);

export interface CustomerOrderDetail { id: string; order_number: number; status: OrderStatus; currency: string; subtotal: number; total: number; created_at: string; updated_at: string; }
export interface CustomerOrderLine { id: string; product_id: string; quantity: number; unit_price: number; line_total: number; product: { sku: string; name: string; unit: string } | null; }
export interface CustomerOrderStatusEvent { id: string; from_status: OrderStatus | null; to_status: OrderStatus; created_at: string; }

function numberOf(value: unknown, label: string) { const n = typeof value === 'number' ? value : Number(value); if (!Number.isFinite(n)) throw new Error(`${label} غير صالح.`); return n; }

export async function getCustomerOrderDetail(orderId: string) {
  if (!UUID.test(orderId)) throw new Error('معرّف الطلب غير صالح.');
  const client = requireSupabase();
  const { data: order, error: orderError } = await client.from('orders').select('id,order_number,status,currency,subtotal,total,created_at,updated_at').eq('id', orderId).single();
  if (orderError) throw orderError;
  if (!STATUSES.has(order.status as OrderStatus)) throw new Error('حالة الطلب غير صالحة.');
  const [{ data: lines, error: linesError }, { data: history, error: historyError }] = await Promise.all([
    client.from('order_items').select('id,product_id,quantity,unit_price,line_total,products:products(sku,name,unit)').eq('order_id', orderId).order('created_at'),
    client.from('order_status_history').select('id,from_status,to_status,created_at').eq('order_id', orderId).order('created_at', { ascending: true })
  ]);
  if (linesError) throw linesError;
  if (historyError) throw historyError;
  const detail: CustomerOrderDetail = { id: order.id, order_number: numberOf(order.order_number, 'رقم الطلب'), status: order.status, currency: order.currency, subtotal: numberOf(order.subtotal, 'الإجمالي الفرعي'), total: numberOf(order.total, 'الإجمالي'), created_at: order.created_at, updated_at: order.updated_at };
  const safeLines: CustomerOrderLine[] = (lines ?? []).map((item) => { const product = Array.isArray(item.products) ? item.products[0] ?? null : item.products ?? null; return { id: item.id, product_id: item.product_id, quantity: numberOf(item.quantity, 'الكمية'), unit_price: numberOf(item.unit_price, 'سعر الوحدة'), line_total: numberOf(item.line_total, 'إجمالي السطر'), product: product && typeof product === 'object' ? { sku: String(product.sku), name: String(product.name), unit: String(product.unit) } : null }; });
  const safeHistory: CustomerOrderStatusEvent[] = (history ?? []).map((item) => { if (!STATUSES.has(item.to_status as OrderStatus) || (item.from_status !== null && !STATUSES.has(item.from_status as OrderStatus))) throw new Error('سجل حالة الطلب غير صالح.'); return { id: item.id, from_status: item.from_status, to_status: item.to_status, created_at: item.created_at }; });
  return { order: detail, lines: safeLines, history: safeHistory };
}
