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

export async function signUpWithCustomerInvite(email: string, password: string, token: string) {
  const normalizedEmail = email.trim().toLowerCase();
  const normalizedToken = token.trim().toLowerCase();
  if (!normalizedEmail || password.length < 8 || !/^[0-9a-f]{64}$/.test(normalizedToken)) {
    throw new Error('البريد وكلمة المرور ورمز الدعوة غير صالحين. كلمة المرور يجب ألا تقل عن 8 أحرف.');
  }
  const client = requireSupabase();
  const { data, error } = await client.auth.signUp({ email: normalizedEmail, password });
  if (error) throw error;
  if (!data.user) throw new Error('تعذر إنشاء حساب العميل.');
  const { error: acceptError } = await client.rpc('accept_customer_account_invite', {
    p_token: normalizedToken,
    p_user_id: data.user.id
  });
  if (acceptError) {
    await client.auth.signOut().catch(() => undefined);
    throw acceptError;
  }
  return data;
}

export async function createCustomerAccountInvite(customerId: string, email: string, expiresHours = 72) {
  const normalizedEmail = email.trim().toLowerCase();
  if (!customerId.trim() || !normalizedEmail) throw new Error('العميل والبريد الإلكتروني مطلوبان.');
  const { data, error } = await requireSupabase().rpc('create_customer_account_invite', {
    p_customer_id: customerId.trim(),
    p_email: normalizedEmail,
    p_expires_hours: expiresHours
  });
  if (error) throw error;
  if (!data || typeof data !== 'object' || typeof (data as { token?: unknown }).token !== 'string') {
    throw new Error('استجابة دعوة الحساب غير صالحة.');
  }
  return data as { invite_id: string; customer_id: string; customer_name: string; email: string; token: string; expires_at: string };
}

export async function signOut() {
  const { error } = await requireSupabase().auth.signOut();
  if (error) throw error;
}
