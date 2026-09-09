import { requireSupabase } from '../lib/supabase';

export type PurchaseOrderStatus = 'draft' | 'submitted' | 'approved' | 'partially_received' | 'received' | 'cancelled';
export interface PurchaseLineInput { productId: string; quantity: number; unitCost: number; }
export interface PurchaseOrderInput { supplierId: string; warehouseId: string; idempotencyKey: string; lines: PurchaseLineInput[]; currency?: string; notes?: string; }
export interface ReceiveLineInput { purchaseOrderItemId: string; productId: string; quantity: number; }
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CURRENCY_PATTERN = /^[A-Z]{3}$/;
const MAX_LINES = 200;
const MAX_QUANTITY = 10_000;

function requireUuid(value: string, field: string): string {
  const normalized = value.trim();
  if (!UUID_PATTERN.test(normalized)) throw new Error(`${field} غير صالح.`);
  return normalized;
}
function requireIdempotencyKey(value: string): string {
  const normalized = value.trim();
  if (normalized.length < 16 || normalized.length > 200) throw new Error('مفتاح منع التكرار يجب أن يكون بين 16 و200 حرف.');
  return normalized;
}
function requirePositiveQuantity(value: number, field: string): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > MAX_QUANTITY) throw new Error(`${field} يجب أن يكون عددًا صحيحًا بين 1 و${MAX_QUANTITY}.`);
  return value;
}
function requireCurrency(value: string): string {
  const normalized = value.trim().toUpperCase();
  if (!CURRENCY_PATTERN.test(normalized)) throw new Error('العملة يجب أن تكون رمزًا من ثلاثة أحرف.');
  return normalized;
}
export function validatePurchaseOrderInput(input: PurchaseOrderInput): void {
  requireUuid(input.supplierId, 'المورد'); requireUuid(input.warehouseId, 'المخزن'); requireIdempotencyKey(input.idempotencyKey);
  if (!Array.isArray(input.lines) || input.lines.length < 1 || input.lines.length > MAX_LINES) throw new Error(`يجب أن يحتوي أمر الشراء على 1 إلى ${MAX_LINES} أصناف.`);
  const products = new Set<string>();
  for (const line of input.lines) {
    const productId = requireUuid(line.productId, 'المنتج');
    if (products.has(productId)) throw new Error('لا يمكن تكرار المنتج في أمر الشراء.');
    products.add(productId); requirePositiveQuantity(line.quantity, 'الكمية');
    if (line.unitCost < 0 || !Number.isFinite(line.unitCost)) throw new Error('تكلفة الوحدة يجب أن تكون رقمًا غير سالب.');
  }
  if (input.currency !== undefined) requireCurrency(input.currency);
  if (input.notes !== undefined && input.notes.length > 2000) throw new Error('ملاحظات أمر الشراء طويلة جدًا.');
}
export function validateReceiveInput(input: { purchaseOrderId: string; idempotencyKey: string; lines: ReceiveLineInput[]; notes?: string }): void {
  requireUuid(input.purchaseOrderId, 'أمر الشراء'); requireIdempotencyKey(input.idempotencyKey);
  if (!Array.isArray(input.lines) || input.lines.length < 1 || input.lines.length > MAX_LINES) throw new Error(`يجب أن يحتوي الاستلام على 1 إلى ${MAX_LINES} أصناف.`);
  const items = new Set<string>();
  for (const line of input.lines) {
    const itemId = requireUuid(line.purchaseOrderItemId, 'بند أمر الشراء'); requireUuid(line.productId, 'المنتج');
    if (items.has(itemId)) throw new Error('لا يمكن تكرار بند أمر الشراء في الاستلام.');
    items.add(itemId); requirePositiveQuantity(line.quantity, 'كمية الاستلام');
  }
  if (input.notes !== undefined && input.notes.length > 2000) throw new Error('ملاحظات الاستلام طويلة جدًا.');
}
export async function createSupplier(input: { name: string; phone?: string; email?: string; address?: string; }) {
  const name = input.name.trim(); if (!name || name.length > 200) throw new Error('اسم المورد مطلوب وبحد أقصى 200 حرف.');
  if (input.email !== undefined && input.email.length > 320) throw new Error('البريد الإلكتروني طويل جدًا.');
  const client = requireSupabase(); const { data, error } = await client.rpc('create_supplier', { p_name: name, p_phone: input.phone?.trim() || null, p_email: input.email?.trim() || null, p_address: input.address?.trim() || null });
  if (error) throw error; return data;
}
export async function createPurchaseOrder(input: PurchaseOrderInput) {
  validatePurchaseOrderInput(input); const client = requireSupabase();
  const { data, error } = await client.rpc('create_purchase_order', { p_supplier_id: input.supplierId.trim(), p_warehouse_id: input.warehouseId.trim(), p_idempotency_key: input.idempotencyKey.trim(), p_lines: input.lines.map((line) => ({ product_id: line.productId.trim(), quantity: line.quantity, unit_cost: line.unitCost })), p_currency: input.currency?.trim().toUpperCase() ?? 'YER', p_notes: input.notes?.trim() || null });
  if (error) throw error; return data?.[0] ?? null;
}
export async function submitPurchaseOrder(purchaseOrderId: string) {
  const id = requireUuid(purchaseOrderId, 'أمر الشراء'); const { data, error } = await requireSupabase().rpc('submit_purchase_order', { p_purchase_order_id: id });
  if (error) throw error; return data;
}
export async function approvePurchaseOrder(purchaseOrderId: string) {
  const id = requireUuid(purchaseOrderId, 'أمر الشراء'); const { data, error } = await requireSupabase().rpc('approve_purchase_order', { p_purchase_order_id: id });
  if (error) throw error; return data;
}
export async function receivePurchaseOrder(input: { purchaseOrderId: string; idempotencyKey: string; lines: ReceiveLineInput[]; notes?: string; }) {
  validateReceiveInput(input); const client = requireSupabase();
  const { data, error } = await client.rpc('receive_purchase_order', { p_purchase_order_id: input.purchaseOrderId.trim(), p_idempotency_key: input.idempotencyKey.trim(), p_lines: input.lines.map((line) => ({ purchase_order_item_id: line.purchaseOrderItemId.trim(), product_id: line.productId.trim(), quantity: line.quantity })), p_notes: input.notes?.trim() || null });
  if (error) throw error; return data?.[0] ?? null;
}
