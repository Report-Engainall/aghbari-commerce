import { supabase } from '../lib/supabase';

export type CustomerInvoice = {
  id: string;
  orderId: string;
  invoiceNumber: number;
  status: 'issued' | 'partially_paid' | 'paid' | 'void';
  currency: string;
  subtotal: number;
  total: number;
  dueAt: string | null;
  createdAt: string;
  items: Array<{ id: string; productId: string; description: string; quantity: number; unitPrice: number; lineTotal: number | null }>;
};

export async function listCustomerInvoices(customerId: string, limit = 50): Promise<CustomerInvoice[]> {
  if (!supabase) return [];
  const { data, error } = await supabase
    .from('operational_invoices')
    .select('id,order_id,invoice_number,status,currency,subtotal,total,due_at,created_at,operational_invoice_items(id,product_id,description,quantity,unit_price,line_total)')
    .eq('customer_id', customerId)
    .order('created_at', { ascending: false })
    .limit(limit);
  if (error) throw error;
  return (data ?? []).map((row) => ({
    id: row.id,
    orderId: row.order_id,
    invoiceNumber: Number(row.invoice_number),
    status: row.status,
    currency: row.currency,
    subtotal: Number(row.subtotal),
    total: Number(row.total),
    dueAt: row.due_at,
    createdAt: row.created_at,
    items: Array.isArray(row.operational_invoice_items) ? row.operational_invoice_items.map((item) => ({
      id: item.id,
      productId: item.product_id,
      description: item.description,
      quantity: Number(item.quantity),
      unitPrice: Number(item.unit_price),
      lineTotal: item.line_total == null ? null : Number(item.line_total)
    })) : []
  }));
}

export async function getCustomerInvoice(customerId: string, invoiceId: string): Promise<CustomerInvoice | null> {
  const rows = await listCustomerInvoices(customerId, 100);
  return rows.find((invoice) => invoice.id === invoiceId) ?? null;
}
