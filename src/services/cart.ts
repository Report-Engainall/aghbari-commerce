import { requireSupabase } from '../lib/supabase';
import { MAX_ORDER_QUANTITY_PER_LINE } from '../domain/order';
import { drainOfflineOperations, enqueueOfflineOperation, OFFLINE_CART_REMOVE_ITEM, OFFLINE_CART_SET_ITEM, type OfflineOperation } from './offlineQueue';

export interface CartItem { product_id: string; sku: string; name: string; unit: string; quantity: number; authorized_price: number | null; currency: string; }
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type OfflineCartPayload = { productId: string; quantity?: number };
function assertCartItem(value: unknown): CartItem {
  if (!value || typeof value !== 'object') throw new Error('استجابة السلة غير صالحة.');
  const item = value as Partial<CartItem>;
  const quantity = item.quantity;
  if (typeof item.product_id !== 'string' || !UUID_PATTERN.test(item.product_id) || typeof item.sku !== 'string' || item.sku.trim() === '' || typeof item.name !== 'string' || item.name.trim() === '' || typeof item.unit !== 'string' || item.unit.trim() === '' || typeof item.currency !== 'string' || item.currency.trim() === '' || typeof quantity !== 'number' || !Number.isSafeInteger(quantity) || quantity < 1 || quantity > MAX_ORDER_QUANTITY_PER_LINE || (item.authorized_price !== null && item.authorized_price !== undefined && (typeof item.authorized_price !== 'number' || !Number.isFinite(item.authorized_price) || item.authorized_price < 0))) throw new Error('استجابة السلة تحتوي بيانات غير صالحة.');
  return { product_id: item.product_id, sku: item.sku, name: item.name, unit: item.unit, quantity, authorized_price: item.authorized_price == null ? null : item.authorized_price, currency: item.currency };
}
function isOfflineCartPayload(payload: unknown): payload is OfflineCartPayload { if (!payload || typeof payload !== 'object') return false; const value = payload as OfflineCartPayload; if (typeof value.productId !== 'string' || !UUID_PATTERN.test(value.productId)) return false; return value.quantity === undefined || (Number.isInteger(value.quantity) && value.quantity >= 1 && value.quantity <= MAX_ORDER_QUANTITY_PER_LINE); }
async function currentUserId(): Promise<string> { const { data, error } = await requireSupabase().auth.getSession(); if (error) throw error; const userId = data.session?.user.id; if (!userId || !UUID_PATTERN.test(userId)) throw new Error('هوية المستخدم مطلوبة للعملية غير المتصلة.'); return userId; }
async function replayCartOperation(operation: OfflineOperation): Promise<void> { if (!isOfflineCartPayload(operation.payload)) throw new Error('بيانات عملية السلة غير المتصلة غير صالحة.'); const client = requireSupabase(); const payload = operation.payload; if (operation.type === OFFLINE_CART_SET_ITEM) { const { error } = await client.rpc('set_cart_item', { p_product_id: payload.productId, p_quantity: payload.quantity }); if (error) throw error; return; } if (operation.type === OFFLINE_CART_REMOVE_ITEM) { const { error } = await client.rpc('remove_cart_item', { p_product_id: payload.productId }); if (error) throw error; return; } throw new Error('نوع عملية غير متوقع في طابور السلة.'); }
export async function syncOfflineCart() { const userId = await currentUserId(); return drainOfflineOperations(replayCartOperation, userId); }
export async function getCart() { const { data, error } = await requireSupabase().rpc('get_cart'); if (error) throw error; if (!Array.isArray(data)) throw new Error('استجابة السلة غير صالحة.'); return data.map(assertCartItem); }
export async function setCartItem(productId: string, quantity: number) { if (!productId) throw new Error('المنتج مطلوب.'); if (!UUID_PATTERN.test(productId.trim())) throw new Error('معرّف المنتج غير صالح.'); if (!Number.isInteger(quantity) || quantity < 1 || quantity > MAX_ORDER_QUANTITY_PER_LINE) throw new Error(`الكمية يجب أن تكون بين 1 و${MAX_ORDER_QUANTITY_PER_LINE}.`); if (typeof navigator !== 'undefined' && navigator.onLine === false) { await enqueueOfflineOperation(await currentUserId(), OFFLINE_CART_SET_ITEM, { productId: productId.trim(), quantity }); return; } const { error } = await requireSupabase().rpc('set_cart_item', { p_product_id: productId.trim(), p_quantity: quantity }); if (error) throw error; }
export async function setCartItems(items: Array<{ productId: string; quantity: number }>) {
  if (!Array.isArray(items) || items.length < 1 || items.length > 200) throw new Error('يجب تحديد من 1 إلى 200 صنف.');
  const seen = new Set<string>();
  const payload = items.map((item) => {
    if (!item || !UUID_PATTERN.test(item.productId?.trim() ?? '')) throw new Error('معرّف منتج غير صالح.');
    if (seen.has(item.productId)) throw new Error('لا يمكن تكرار المنتج في عملية السلة الجماعية.');
    seen.add(item.productId);
    if (!Number.isSafeInteger(item.quantity) || item.quantity < 1 || item.quantity > MAX_ORDER_QUANTITY_PER_LINE) throw new Error(`الكمية يجب أن تكون بين 1 و${MAX_ORDER_QUANTITY_PER_LINE}.`);
    return { product_id: item.productId.trim(), quantity: item.quantity };
  });
  if (typeof navigator !== 'undefined' && navigator.onLine === false) throw new Error('الطلب السريع من Excel يحتاج اتصالًا بالخادم.');
  const { data, error } = await requireSupabase().rpc('set_cart_items', { p_items: payload });
  if (error) throw error;
  if (!Array.isArray(data)) throw new Error('استجابة السلة الجماعية غير صالحة.');
  return data.map(assertCartItem);
}
export async function removeCartItem(productId: string) { if (!productId) throw new Error('المنتج مطلوب.'); if (!UUID_PATTERN.test(productId.trim())) throw new Error('معرّف المنتج غير صالح.'); if (typeof navigator !== 'undefined' && navigator.onLine === false) { await enqueueOfflineOperation(await currentUserId(), OFFLINE_CART_REMOVE_ITEM, { productId: productId.trim() }); return; } const { error } = await requireSupabase().rpc('remove_cart_item', { p_product_id: productId.trim() }); if (error) throw error; }
export async function clearCart() { const { error } = await requireSupabase().rpc('clear_cart'); if (error) throw error; }
