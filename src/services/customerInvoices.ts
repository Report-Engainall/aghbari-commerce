import { requireSupabase } from '../lib/supabase';

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

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function assertUuid(value: string, field: string): string {
  if (typeof value !== 'string' || !UUID_PATTERN.test(value.trim())) throw new Error(`معرّف ${field} غير صالح.`);
  return value.trim();
}

function mapInvoice(row: any): CustomerInvoice {
  const id = assertUuid(row.id, 'الفاتورة');
  const orderId = assertUuid(row.order_id, 'الطلب');
  const invoiceNumber = Number(row.invoice_number);
  const total = Number(row.total);
  const subtotal = Number(row.subtotal);
  if (!Number.isSafeInteger(invoiceNumber) || invoiceNumber < 1) throw new Error('رقم الفاتورة غير صالح.');
  if (!Number.isFinite(total) || total < 0 || !Number.isFinite(subtotal) || subtotal < 0) throw new Error('قيمة الفاتورة غير صالحة.');
  if (typeof row.currency !== 'string' || !/^[A-Z]{3}$/.test(row.currency)) throw new Error('عملة الفاتورة غير صالحة.');
  return {
    id,
    orderId,
    invoiceNumber,
    status: row.status,
    currency: row.currency,
    subtotal,
    total,
    dueAt: row.due_at,
    createdAt: row.created_at,
    items: Array.isArray(row.operational_invoice_items) ? row.operational_invoice_items.map((item: any) => ({
      id: item.id,
      productId: item.product_id,
      description: item.description,
      quantity: Number(item.quantity),
      unitPrice: Number(item.unit_price),
      lineTotal: item.line_total == null ? null : Number(item.line_total)
    })) : []
  };
}

export async function listCustomerInvoices(customerId: string, limit = 50): Promise<CustomerInvoice[]> {
  const id = assertUuid(customerId, 'العميل');
  const safeLimit = Math.min(Math.max(Math.trunc(limit), 1), 100);
  const { data, error } = await requireSupabase()
    .from('operational_invoices')
    .select('id,order_id,invoice_number,status,currency,subtotal,total,due_at,created_at,operational_invoice_items(id,product_id,description,quantity,unit_price,line_total)')
    .eq('customer_id', id)
    .order('created_at', { ascending: false })
    .limit(safeLimit);
  if (error) throw error;
  return (data ?? []).map(mapInvoice);
}

export async function getCustomerInvoice(customerId: string, invoiceId: string): Promise<CustomerInvoice | null> {
  const customer = assertUuid(customerId, 'العميل');
  const invoice = assertUuid(invoiceId, 'الفاتورة');
  const { data, error } = await requireSupabase()
    .from('operational_invoices')
    .select('id,order_id,invoice_number,status,currency,subtotal,total,due_at,created_at,operational_invoice_items(id,product_id,description,quantity,unit_price,line_total)')
    .eq('customer_id', customer)
    .eq('id', invoice)
    .maybeSingle();
  if (error) throw error;
  return data ? mapInvoice(data) : null;
}
