import { requireSupabase } from '../lib/supabase';
import type { CustomerTier } from '../domain/types';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CUSTOMER_TIERS = new Set<CustomerTier>(['retail', 'wholesale', 'distributor']);
const PRODUCT_STATUSES = new Set(['active', 'inactive']);

export interface StaffProductRecord { id: string; sku: string; name: string; unit: string; category_id: string | null; description: string | null; status: 'active' | 'inactive'; }

function assertUuid(value: string, operation: string) {
  const normalized = value.trim();
  if (!UUID_PATTERN.test(normalized)) throw new Error(`معرّف ${operation} غير صالح.`);
  return normalized;
}

function assertNonBlank(value: string, operation: string) {
  const normalized = value.trim();
  if (!normalized) throw new Error(`${operation} مطلوب.`);
  return normalized;
}

function assertFiniteMoney(value: number) {
  if (!Number.isFinite(value) || value < 0) throw new Error('السعر يجب أن يكون رقمًا غير سالب.');
  return value;
}

function assertInventoryDelta(value: number) {
  if (!Number.isSafeInteger(value) || value === 0) throw new Error('تغيير المخزون يجب أن يكون عددًا صحيحًا غير صفري.');
  return value;
}

export function assertCustomerTier(value: unknown): CustomerTier {
  if (typeof value !== 'string' || !CUSTOMER_TIERS.has(value as CustomerTier)) {
    throw new Error('فئة العميل غير مسموحة.');
  }
  return value as CustomerTier;
}

export function assertProductStatus(value: unknown): 'active' | 'inactive' {
  if (typeof value !== 'string' || !PRODUCT_STATUSES.has(value)) {
    throw new Error('حالة المنتج غير مسموحة.');
  }
  return value as 'active' | 'inactive';
}

export function assertEntityId(value: unknown, operation: string) {
  const id = value && typeof value === 'object' ? (value as { id?: unknown }).id : undefined;
  if (typeof id !== 'string' || !UUID_PATTERN.test(id)) {
    throw new Error(`استجابة ${operation} غير صالحة. لم يتم إثبات نجاح العملية.`);
  }
  return value;
}

export function assertMoney(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    throw new Error('استجابة تحديث السعر غير صالحة. لم يتم إثبات نجاح العملية.');
  }
  return value;
}

export function assertInventoryQuantity(value: unknown): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
    throw new Error('استجابة تعديل المخزون غير صالحة. لم يتم إثبات نجاح العملية.');
  }
  return value;
}

export async function getStaffProducts(limit = 500): Promise<StaffProductRecord[]> {
  const safeLimit = Number.isSafeInteger(limit) ? Math.min(Math.max(limit, 1), 1000) : 500;
  const { data, error } = await requireSupabase().from('products').select('id,sku,name,unit,category_id,description,status').order('name').limit(safeLimit);
  if (error) throw error;
  return (data ?? []).map((row) => ({
    id: assertUuid(row.id, 'المنتج'),
    sku: assertNonBlank(row.sku, 'SKU المنتج'),
    name: assertNonBlank(row.name, 'اسم المنتج'),
    unit: assertNonBlank(row.unit, 'وحدة المنتج'),
    category_id: row.category_id ? assertUuid(row.category_id, 'تصنيف المنتج') : null,
    description: row.description == null ? null : String(row.description),
    status: assertProductStatus(row.status)
  }));
}

export async function createCategory(name: string, slug: string, parentId: string | null = null) {
  const normalizedName = assertNonBlank(name, 'اسم التصنيف');
  const normalizedSlug = assertNonBlank(slug, 'معرف التصنيف');
  const normalizedParentId = parentId === null ? null : assertUuid(parentId, 'التصنيف الأب');
  const { data, error } = await requireSupabase().rpc('create_category', { p_name: normalizedName, p_slug: normalizedSlug, p_parent_id: normalizedParentId });
  if (error) throw error;
  return assertEntityId(data, 'إنشاء التصنيف');
}

export async function upsertProduct(input: {
  productId?: string | null;
  sku: string;
  name: string;
  unit: string;
  categoryId?: string | null;
  description?: string | null;
  status?: 'active' | 'inactive';
}) {
  const productId = input.productId ? assertUuid(input.productId, 'المنتج') : null;
  const categoryId = input.categoryId ? assertUuid(input.categoryId, 'التصنيف') : null;
  const sku = assertNonBlank(input.sku, 'SKU');
  const name = assertNonBlank(input.name, 'اسم المنتج');
  const unit = assertNonBlank(input.unit, 'وحدة المنتج');
  const description = input.description?.trim() || null;
  const status = input.status === undefined ? 'active' : assertProductStatus(input.status);
  const { data, error } = await requireSupabase().rpc('upsert_product', {
    p_product_id: productId,
    p_sku: sku,
    p_name: name,
    p_unit: unit,
    p_category_id: categoryId,
    p_description: description,
    p_status: status
  });
  if (error) throw error;
  return assertEntityId(data, 'حفظ المنتج');
}

export async function setProductPrice(productId: string, tier: CustomerTier, amount: number, currency = 'YER') {
  const id = assertUuid(productId, 'المنتج');
  const normalizedTier = assertCustomerTier(tier);
  const normalizedCurrency = assertNonBlank(currency, 'العملة').toUpperCase();
  const normalizedAmount = assertFiniteMoney(amount);
  const { data, error } = await requireSupabase().rpc('set_product_price', {
    p_product_id: id, p_tier: normalizedTier, p_amount: normalizedAmount, p_currency: normalizedCurrency
  });
  if (error) throw error;
  return assertMoney(data);
}

export async function adjustInventory(warehouseId: string, productId: string, delta: number, reason: string) {
  const warehouse = assertUuid(warehouseId, 'المستودع');
  const product = assertUuid(productId, 'المنتج');
  const normalizedDelta = assertInventoryDelta(delta);
  const normalizedReason = assertNonBlank(reason, 'سبب تعديل المخزون');
  const { data, error } = await requireSupabase().rpc('adjust_inventory', {
    p_warehouse_id: warehouse, p_product_id: product, p_delta: normalizedDelta, p_reason: normalizedReason
  });
  if (error) throw error;
  return assertInventoryQuantity(data);
}
