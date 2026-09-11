import { supabase } from '../lib/supabase';

export type TemplateLine = { productId: string; sku: string; name: string; unit: string; quantity: number };
export type OrderTemplate = { id: string; name: string; branchLabel: string; lines: TemplateLine[]; updatedAt: string };

type DbTemplate = {
  id: string;
  name: string;
  branch_label: string | null;
  lines: unknown;
  updated_at: string;
};

function normalizeLines(value: unknown): TemplateLine[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((line) => {
    if (!line || typeof line !== 'object') return [];
    const item = line as Record<string, unknown>;
    if (typeof item.productId !== 'string' || typeof item.sku !== 'string' || typeof item.name !== 'string' || typeof item.unit !== 'string') return [];
    const quantity = Number(item.quantity);
    if (!Number.isSafeInteger(quantity) || quantity < 1) return [];
    return [{ productId: item.productId, sku: item.sku, name: item.name, unit: item.unit, quantity }];
  });
}

function fromDb(row: DbTemplate): OrderTemplate {
  return { id: row.id, name: row.name, branchLabel: row.branch_label ?? 'الفرع الرئيسي', lines: normalizeLines(row.lines), updatedAt: row.updated_at };
}

export async function listOrderTemplates(customerId: string, limit = 50): Promise<OrderTemplate[]> {
  if (!supabase) return [];
  const { data, error } = await supabase
    .from('order_templates')
    .select('id,name,branch_label,lines,updated_at')
    .eq('customer_id', customerId)
    .order('updated_at', { ascending: false })
    .limit(limit);
  if (error) throw error;
  return (data ?? []).map((row) => fromDb(row as DbTemplate));
}

export async function createOrderTemplate(input: { customerId: string; name: string; branchLabel?: string; lines: TemplateLine[]; }): Promise<OrderTemplate> {
  if (!supabase) throw new Error('قاعدة البيانات غير متاحة.');
  const name = input.name.trim();
  if (!name || name.length > 120) throw new Error('اسم المسودة غير صالح.');
  if (!input.lines.length) throw new Error('لا يمكن حفظ مسودة بدون أصناف.');
  const { data, error } = await supabase
    .from('order_templates')
    .insert({ customer_id: input.customerId, name, branch_label: input.branchLabel?.trim() || 'الفرع الرئيسي', lines: input.lines })
    .select('id,name,branch_label,lines,updated_at')
    .single();
  if (error) throw error;
  return fromDb(data as DbTemplate);
}

export async function deleteOrderTemplate(templateId: string, customerId: string): Promise<void> {
  if (!supabase) throw new Error('قاعدة البيانات غير متاحة.');
  const { error } = await supabase.from('order_templates').delete().eq('id', templateId).eq('customer_id', customerId);
  if (error) throw error;
}
