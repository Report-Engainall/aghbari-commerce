import { requireSupabase } from '../lib/supabase';

export async function getSession() {
  const { data, error } = await requireSupabase().auth.getSession();
  if (error) throw error;
  return data.session;
}

export async function signIn(email: string, password: string) {
  const { data, error } = await requireSupabase().auth.signInWithPassword({ email: email.trim(), password });
  if (error) throw error;
  return data.session;
}

export async function signUp(email: string, password: string, emailRedirectTo?: string) {
  const normalizedEmail = email.trim().toLowerCase();
  if (!normalizedEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)) throw new Error('البريد الإلكتروني غير صالح.');
  if (password.length < 8) throw new Error('كلمة المرور يجب ألا تقل عن 8 أحرف.');
  const { data, error } = await requireSupabase().auth.signUp({
    email: normalizedEmail,
    password,
    options: emailRedirectTo ? { emailRedirectTo } : undefined
  });
  if (error) throw error;
  return data.session;
}

export async function signUpWithCustomerInvite(email: string, password: string, token: string) {
  const normalizedToken = token.trim();
  if (!/^[A-Za-z0-9_-]{32,128}$/.test(normalizedToken)) throw new Error('رمز الدعوة غير صالح.');
  const session = await signUp(email, password, window.location.href);
  if (!session) return { session: null, pendingConfirmation: true };
  const { data, error } = await requireSupabase().rpc('accept_customer_invitation', { p_token: normalizedToken });
  if (error) { await requireSupabase().auth.signOut().catch(() => undefined); throw error; }
  return { session, customer: data, pendingConfirmation: false };
}

export async function createCustomerAccountInvite(customerId: string, email: string, expiresHours = 72) {
  const normalizedEmail = email.trim().toLowerCase();
  if (!customerId.trim() || !normalizedEmail) throw new Error('العميل والبريد الإلكتروني مطلوبان.');
  const { data, error } = await requireSupabase().rpc('create_customer_invitation', {
    p_customer_id: customerId.trim(), p_email: normalizedEmail, p_expires_hours: expiresHours
  });
  if (error) throw error;
  if (!data || typeof data !== 'object' || typeof (data as { token?: unknown }).token !== 'string') throw new Error('استجابة دعوة الحساب غير صالحة.');
  return data as { id: string; customer_id: string; email: string; token: string; expires_at: string };
}

export async function signOut() {
  const { error } = await requireSupabase().auth.signOut();
  if (error) throw error;
}
