import { requireSupabase } from '../lib/supabase';

export type CustomerPayment = { id: string; invoiceId: string; amount: number; method: string; reference: string | null; paidAt: string | null; createdAt: string };

export async function listCustomerPayments(): Promise<CustomerPayment[]> {
  const { data, error } = await requireSupabase().rpc('get_customer_payments');
  if (error) throw error;
  return (Array.isArray(data) ? data : []).map((row) => ({
    id: row.id,
    invoiceId: row.invoice_id,
    amount: Number(row.amount),
    method: String(row.method),
    reference: row.reference ?? null,
    paidAt: row.paid_at ?? null,
    createdAt: row.created_at
  }));
}
