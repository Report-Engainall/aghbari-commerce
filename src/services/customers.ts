import { requireSupabase } from '../lib/supabase';
import type { CustomerTier } from '../domain/types';

export interface StaffCustomer {
  id: string;
  name: string;
  phone: string | null;
  email: string | null;
  tier: CustomerTier;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CUSTOMER_TIERS = new Set<CustomerTier>(['retail','wholesale','distributor']);

function requireUuid(value: string, field: string): string { const normalized = value.trim(); if (!UUID_PATTERN.test(normalized)) throw new Error(`${field} غير صالح.`); return normalized; }
export function validateCustomerInput(name: string, phone: string, tier: CustomerTier) {
  const normalizedName = name.trim(); if (!normalizedName || normalizedName.length > 200) throw new Error('اسم العميل مطلوب وبحد أقصى 200 حرف.');
  const normalizedPhone = phone.trim(); if (normalizedPhone.length > 50) throw new Error('رقم هاتف العميل طويل جدًا.');
  if (!CUSTOMER_TIERS.has(tier)) throw new Error('فئة العميل غير مسموحة.');
  return { name: normalizedName, phone: normalizedPhone || null, tier };
}
export function validateCustomerTier(tier: CustomerTier): CustomerTier { if (!CUSTOMER_TIERS.has(tier)) throw new Error('فئة العميل غير مسموحة.'); return tier; }

export async function getCustomers(limit = 200) {
  const normalizedLimit = Number.isSafeInteger(limit) ? Math.min(Math.max(limit, 1), 500) : 200;
  const { data, error } = await requireSupabase().from('customers').select('id,name,phone,email,tier,is_active,created_at,updated_at').order('created_at', { ascending: false }).limit(normalizedLimit);
  if (error) throw error; return (data ?? []) as StaffCustomer[];
}
export async function createCustomer(name: string, phone: string, tier: CustomerTier) {
  const input = validateCustomerInput(name, phone, tier); const { data, error } = await requireSupabase().rpc('create_customer', { p_name: input.name, p_phone: input.phone, p_tier: input.tier }); if (error) throw error; return data as StaffCustomer;
}
export async function setCustomerTier(customerId: string, tier: CustomerTier) {
  const id = requireUuid(customerId, 'العميل'); const normalizedTier = validateCustomerTier(tier); const { data, error } = await requireSupabase().rpc('set_customer_tier', { p_customer_id: id, p_tier: normalizedTier }); if (error) throw error; return data as StaffCustomer;
}
export async function setCustomerActive(customerId: string, isActive: boolean) {
  const id = requireUuid(customerId, 'العميل'); if (typeof isActive !== 'boolean') throw new Error('حالة العميل غير صالحة.'); const { data, error } = await requireSupabase().rpc('set_customer_active', { p_customer_id: id, p_is_active: isActive }); if (error) throw error; return data as StaffCustomer;
}
