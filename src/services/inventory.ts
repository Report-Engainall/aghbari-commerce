import { requireSupabase } from '../lib/supabase';

export interface LowStockRow { warehouse_id: string; warehouse_name: string; product_id: string; sku: string; product_name: string; current_quantity: number; min_quantity: number; reorder_quantity: number; }
export interface StockCountSession { id: string; organization_id: string; warehouse_id: string; status: 'open' | 'completed' | 'cancelled'; idempotency_key: string; started_by: string | null; started_at: string; completed_at: string | null; notes: string | null; }
export interface StockCountLine { id: string; session_id: string; product_id: string; expected_quantity: number; counted_quantity: number | null; completed_quantity: number | null; variance: number | null; counted_at: string | null; }

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_LINES = 200;
const MAX_QUANTITY = 1_000_000;

function requireUuid(value: string, field: string): string { const normalized = value.trim(); if (!UUID_PATTERN.test(normalized)) throw new Error(`${field} غير صالح.`); return normalized; }
function requireIdempotencyKey(value: string): string { const normalized = value.trim(); if (normalized.length < 16 || normalized.length > 200) throw new Error('مفتاح منع التكرار يجب أن يكون بين 16 و200 حرف.'); return normalized; }
function requireFiniteNonNegative(value: number, field: string): number { if (!Number.isSafeInteger(value) || value < 0 || value > MAX_QUANTITY) throw new Error(`${field} يجب أن يكون عددًا صحيحًا غير سالب وضمن الحد المسموح.`); return value; }
function requirePositiveQuantity(value: number): number { if (!Number.isSafeInteger(value) || value <= 0 || value > MAX_QUANTITY) throw new Error(`كمية المخزون يجب أن تكون عددًا صحيحًا بين 1 و${MAX_QUANTITY}.`); return value; }

export function validateInventoryTransferInput(sourceWarehouseId: string, destinationWarehouseId: string, idempotencyKey: string, lines: Array<{ productId: string; quantity: number }>): void {
  requireUuid(sourceWarehouseId, 'المخزن المصدر'); requireUuid(destinationWarehouseId, 'المخزن الوجهة');
  if (sourceWarehouseId.trim() === destinationWarehouseId.trim()) throw new Error('لا يمكن نقل المخزون إلى نفس المخزن.');
  requireIdempotencyKey(idempotencyKey);
  if (!Array.isArray(lines) || lines.length < 1 || lines.length > MAX_LINES) throw new Error(`يجب أن يحتوي التحويل على 1 إلى ${MAX_LINES} أصناف.`);
  const products = new Set<string>();
  for (const line of lines) { const productId = requireUuid(line.productId, 'المنتج'); if (products.has(productId)) throw new Error('لا يمكن تكرار المنتج في تحويل المخزون.'); products.add(productId); requirePositiveQuantity(line.quantity); }
}
export function validateStockThresholdInput(warehouseId: string, productId: string, minQuantity: number, reorderQuantity: number, maxQuantity?: number | null): void {
  requireUuid(warehouseId, 'المخزن'); requireUuid(productId, 'المنتج'); requireFiniteNonNegative(minQuantity, 'الحد الأدنى'); requirePositiveQuantity(reorderQuantity);
  if (maxQuantity !== undefined && maxQuantity !== null) { requireFiniteNonNegative(maxQuantity, 'الحد الأقصى'); if (maxQuantity < minQuantity) throw new Error('الحد الأقصى لا يمكن أن يكون أقل من الحد الأدنى.'); }
}
export async function transferInventory(sourceWarehouseId: string, destinationWarehouseId: string, idempotencyKey: string, lines: Array<{ productId: string; quantity: number }>, notes?: string) { validateInventoryTransferInput(sourceWarehouseId, destinationWarehouseId, idempotencyKey, lines); const { data, error } = await requireSupabase().rpc('transfer_inventory', { p_source_warehouse_id: sourceWarehouseId.trim(), p_destination_warehouse_id: destinationWarehouseId.trim(), p_idempotency_key: idempotencyKey.trim(), p_lines: lines.map((line) => ({ product_id: line.productId.trim(), quantity: line.quantity })), p_notes: notes?.trim() || null }); if (error) throw error; return data; }
export async function setStockThreshold(warehouseId: string, productId: string, minQuantity: number, reorderQuantity: number, maxQuantity?: number | null) { validateStockThresholdInput(warehouseId, productId, minQuantity, reorderQuantity, maxQuantity); const { data, error } = await requireSupabase().rpc('set_stock_threshold', { p_warehouse_id: warehouseId.trim(), p_product_id: productId.trim(), p_min_quantity: minQuantity, p_reorder_quantity: reorderQuantity, p_max_quantity: maxQuantity ?? null }); if (error) throw error; return data; }
export async function getLowStock() { const { data, error } = await requireSupabase().rpc('get_low_stock'); if (error) throw error; return (data ?? []) as LowStockRow[]; }
export async function startStockCount(warehouseId: string, idempotencyKey: string, notes?: string) { requireUuid(warehouseId, 'المخزن'); requireIdempotencyKey(idempotencyKey); const { data, error } = await requireSupabase().rpc('start_stock_count', { p_warehouse_id: warehouseId.trim(), p_idempotency_key: idempotencyKey.trim(), p_notes: notes?.trim() || null }); if (error) throw error; return data as StockCountSession; }
export async function getOpenStockCount() { const { data, error } = await requireSupabase().from('stock_count_sessions').select('*').eq('status', 'open').order('started_at', { ascending: false }).limit(1).maybeSingle(); if (error) throw error; return (data ?? null) as StockCountSession | null; }
export async function getStockCountLines(sessionId: string) { requireUuid(sessionId, 'جلسة الجرد'); const { data, error } = await requireSupabase().from('stock_count_lines').select('id,session_id,product_id,expected_quantity,counted_quantity,completed_quantity,variance,counted_at').eq('session_id', sessionId.trim()).order('product_id'); if (error) throw error; return (data ?? []) as StockCountLine[]; }
export async function setStockCountLine(sessionId: string, productId: string, countedQuantity: number) { requireUuid(sessionId, 'جلسة الجرد'); requireUuid(productId, 'المنتج'); requireFiniteNonNegative(countedQuantity, 'الكمية المعدودة'); const { data, error } = await requireSupabase().rpc('set_stock_count_line', { p_session_id: sessionId.trim(), p_product_id: productId.trim(), p_counted_quantity: countedQuantity }); if (error) throw error; return data as StockCountLine; }
export async function completeStockCount(sessionId: string) { requireUuid(sessionId, 'جلسة الجرد'); const { data, error } = await requireSupabase().rpc('complete_stock_count', { p_session_id: sessionId.trim() }); if (error) throw error; return data as { status: string; session_id: string; adjusted_lines: number }; }
