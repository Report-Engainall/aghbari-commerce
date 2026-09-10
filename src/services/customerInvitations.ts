import { requireSupabase } from '../lib/supabase';

export type InvitationStatus = 'pending' | 'accepted' | 'expired' | 'revoked';

export interface CustomerInvitation {
  id: string;
  customer_id: string;
  email: string;
  expires_at: string;
  accepted_at: string | null;
  revoked_at: string | null;
  created_at: string;
  status: InvitationStatus;
}

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function normalizeEmail(value: string) {
  const email = value.trim().toLowerCase();
  if (!EMAIL_PATTERN.test(email) || email.length > 320) throw new Error('البريد الإلكتروني غير صالح.');
  return email;
}

function statusOf(item: Omit<CustomerInvitation, 'status'>): InvitationStatus {
  if (item.revoked_at) return 'revoked';
  if (item.accepted_at) return 'accepted';
  if (new Date(item.expires_at).getTime() <= Date.now()) return 'expired';
  return 'pending';
}

export async function getCustomerInvitations(limit = 100) {
  const safeLimit = Number.isSafeInteger(limit) ? Math.min(Math.max(limit, 1), 200) : 100;
  const { data, error } = await requireSupabase().from('customer_invitations')
    .select('id,customer_id,email,expires_at,accepted_at,revoked_at,created_at')
    .order('created_at', { ascending: false }).limit(safeLimit);
  if (error) throw error;
  return ((data ?? []) as Omit<CustomerInvitation, 'status'>[]).map((item) => ({ ...item, status: statusOf(item) }));
}

export async function createCustomerInvitation(customerId: string, email: string, expiresHours = 72) {
  if (!customerId) throw new Error('العميل مطلوب.');
  const normalizedEmail = normalizeEmail(email);
  const hours = Number.isSafeInteger(expiresHours) ? Math.min(Math.max(expiresHours, 1), 168) : 72;
  const { data, error } = await requireSupabase().rpc('create_customer_invitation', {
    p_customer_id: customerId, p_email: normalizedEmail, p_expires_hours: hours
  });
  if (error) throw error;
  const result = data as { id: string; token: string; expires_at: string; email: string };
  if (!result?.id || !result?.token) throw new Error('لم يتم إثبات إنشاء الدعوة.');
  const origin = window.location.origin;
  const url = `${origin}/?invite=${encodeURIComponent(result.token)}`;
  return { ...result, url };
}

export async function revokeCustomerInvitation(invitationId: string) {
  if (!invitationId) throw new Error('الدعوة مطلوبة.');
  const { data, error } = await requireSupabase().rpc('revoke_customer_invitation', { p_invitation_id: invitationId });
  if (error) throw error;
  if (data !== true) throw new Error('الدعوة غير قابلة للإلغاء أو غير موجودة.');
  return true;
}

export async function acceptCustomerInvitation(token: string) {
  const normalized = token.trim();
  if (normalized.length < 32) throw new Error('رابط الدعوة غير صالح.');
  const { data, error } = await requireSupabase().rpc('accept_customer_invitation', { p_token: normalized });
  if (error) throw error;
  if (!data || typeof data !== 'object' || !('id' in data)) throw new Error('تعذر تفعيل حساب العميل.');
  return data;
}
