import { requireSupabase } from '../lib/supabase';

export type InvoiceStatus = 'issued' | 'partially_paid' | 'paid' | 'void';
export interface OperationalInvoice { id: string; order_id: string | null; customer_id: string; invoice_number: number; status: InvoiceStatus; currency: string; subtotal: number; total: number; paid_amount: number; due_at: string | null; created_at: string; }
export interface CashBalance { id: string; name: string; currency: string; opening_balance: number; received: number; spent: number; current_balance: number; }

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CURRENCY_PATTERN = /^[A-Z]{3}$/;
const PAYMENT_METHODS = new Set(['cash', 'bank_transfer', 'card', 'other']);
const MAX_MONEY = Number.MAX_SAFE_INTEGER;

function requireString(value: unknown, field: string): string {
  if (typeof value !== 'string') throw new Error(`${field} يجب أن يكون نصًا.`);
  return value;
}
function requireUuid(value: unknown, field: string): string {
  const normalized = requireString(value, field).trim();
  if (!UUID_PATTERN.test(normalized)) throw new Error(`${field} غير صالح.`);
  return normalized;
}
function requirePositiveAmount(value: number, field: string): number {
  if (!Number.isFinite(value) || value <= 0 || value > MAX_MONEY) throw new Error(`${field} يجب أن يكون رقمًا أكبر من صفر وضمن الدقة الآمنة.`);
  return value;
}
function requireCurrency(value: unknown): string {
  const normalized = requireString(value, 'العملة').trim().toUpperCase();
  if (!CURRENCY_PATTERN.test(normalized)) throw new Error('العملة يجب أن تكون رمزًا من ثلاثة أحرف.');
  return normalized;
}

export function validatePaymentInput(invoiceId: string, amount: number, method: string, cashAccountId: string | null, reference: string): void {
  requireUuid(invoiceId, 'الفاتورة');
  requirePositiveAmount(amount, 'مبلغ الدفع');
  const normalizedMethod = requireString(method, 'طريقة الدفع').trim();
  if (!PAYMENT_METHODS.has(normalizedMethod)) throw new Error('طريقة الدفع غير مسموحة.');
  if (cashAccountId !== null) requireUuid(cashAccountId, 'حساب النقدية');
  const normalizedReference = requireString(reference, 'مرجع الدفع').trim();
  if (normalizedReference.length > 200) throw new Error('مرجع الدفع طويل جدًا.');
}
export function validateExpenseInput(branchId: string, cashAccountId: string, category: string, amount: number, currency: string, description: string): void {
  requireUuid(branchId, 'الفرع'); requireUuid(cashAccountId, 'حساب النقدية');
  const normalizedCategory = requireString(category, 'تصنيف المصروف').trim();
  if (!normalizedCategory || normalizedCategory.length > 200) throw new Error('تصنيف المصروف مطلوب وبحد أقصى 200 حرف.');
  requirePositiveAmount(amount, 'مبلغ المصروف'); requireCurrency(currency);
  const normalizedDescription = requireString(description, 'وصف المصروف').trim();
  if (normalizedDescription.length > 2000) throw new Error('وصف المصروف طويل جدًا.');
}
export function validateCashAccountInput(branchId: string, name: string, currency: string, openingBalance: number): void {
  requireUuid(branchId, 'الفرع');
  const normalizedName = requireString(name, 'اسم حساب النقدية').trim();
  if (!normalizedName || normalizedName.length > 200) throw new Error('اسم حساب النقدية مطلوب وبحد أقصى 200 حرف.');
  requireCurrency(currency);
  if (!Number.isFinite(openingBalance) || openingBalance < 0 || openingBalance > MAX_MONEY) throw new Error('الرصيد الافتتاحي يجب أن يكون رقمًا غير سالب وضمن الدقة الآمنة.');
}

export async function getInvoices(limit = 100) {
  const normalizedLimit = Number.isSafeInteger(limit) ? Math.min(Math.max(limit, 1), 500) : 100;
  const { data, error } = await requireSupabase().from('operational_invoices').select('id,order_id,customer_id,invoice_number,status,currency,subtotal,total,due_at,created_at').order('created_at', { ascending: false }).limit(normalizedLimit);
  if (error) throw error;
  const rows = (data ?? []) as Array<Omit<OperationalInvoice, 'paid_amount'> & { paid_amount?: number }>;
  const invoiceIds = rows.map((row) => row.id);
  if (!invoiceIds.length) return rows.map((row) => ({ ...row, paid_amount: 0 })) as OperationalInvoice[];
  const { data: paymentRows, error: paymentError } = await requireSupabase().from('payments').select('invoice_id,amount').in('invoice_id', invoiceIds);
  if (paymentError) throw paymentError;
  const paidByInvoice = new Map<string, number>();
  for (const row of paymentRows ?? []) paidByInvoice.set(row.invoice_id, (paidByInvoice.get(row.invoice_id) ?? 0) + Number(row.amount));
  return rows.map((row) => ({ ...row, paid_amount: paidByInvoice.get(row.id) ?? 0 })) as OperationalInvoice[];
}
export async function getCashBalances() {
  const { data, error } = await requireSupabase().rpc('get_cash_account_balances');
  if (error) throw error;
  return (data ?? []) as CashBalance[];
}
export async function createCashAccount(branchId: string, name: string, currency: string, openingBalance: number) {
  validateCashAccountInput(branchId, name, currency, openingBalance);
  const { data, error } = await requireSupabase().rpc('create_cash_account', { p_branch_id: branchId.trim(), p_name: name.trim(), p_currency: currency.trim().toUpperCase(), p_opening_balance: openingBalance });
  if (error) throw error;
  return data as CashBalance;
}
export async function createInvoiceFromOrder(orderId: string) {
  const id = requireUuid(orderId, 'الطلب');
  const { data, error } = await requireSupabase().rpc('create_invoice_from_order', { p_order_id: id });
  if (error) throw error;
  return data as OperationalInvoice;
}
export async function recordPayment(invoiceId: string, amount: number, method: 'cash'|'bank_transfer'|'card'|'other', cashAccountId: string | null, reference: string) {
  validatePaymentInput(invoiceId, amount, method, cashAccountId, reference);
  const { data, error } = await requireSupabase().rpc('record_payment', { p_invoice_id: invoiceId.trim(), p_amount: amount, p_method: method, p_cash_account_id: cashAccountId?.trim() ?? null, p_reference: reference.trim() || null });
  if (error) throw error;
  return data;
}
export async function recordExpense(branchId: string, cashAccountId: string, category: string, amount: number, currency: string, description: string) {
  validateExpenseInput(branchId, cashAccountId, category, amount, currency, description);
  const { data, error } = await requireSupabase().rpc('record_expense', { p_branch_id: branchId.trim(), p_cash_account_id: cashAccountId.trim(), p_category: category.trim(), p_amount: amount, p_currency: currency.trim().toUpperCase(), p_description: description.trim() || null });
  if (error) throw error;
  return data;
}
