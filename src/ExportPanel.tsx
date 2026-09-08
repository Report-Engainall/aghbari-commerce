import { useState } from 'react';
import { supabase } from './lib/supabase';

type UserRole = 'owner' | 'admin' | 'sales' | 'warehouse' | 'viewer';
const PAGE_SIZE = 1000;
const MAX_EXPORT_ROWS = 10000;
const MAX_PRICE_ROWS = 30000;

function escapeCsv(value: unknown) {
  let text = String(value ?? '');
  if (typeof value === 'string' && /^[=+\-@]/.test(text)) text = `'${text}`;
  return /[",\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

function downloadCsv(filename: string, headers: string[], rows: Array<Record<string, unknown>>) {
  const csv = [headers, ...rows.map((row) => headers.map((header) => escapeCsv(row[header])))]
    .map((row) => row.join(','))
    .join('\r\n');
  const blob = new Blob([`\uFEFF${csv}`], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url; anchor.download = filename; anchor.click();
  URL.revokeObjectURL(url);
}

export default function ExportPanel({ role }: { role: UserRole }) {
  const canExport = role === 'owner' || role === 'admin' || role === 'sales' || role === 'warehouse';
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  if (!canExport || !supabase) return null;
  const client = supabase;

  async function fetchAllProducts() {
    const rows: Array<{ id: string; sku: string; name: string; unit: string; status: string; created_at: string }> = [];
    for (let from = 0; from < MAX_EXPORT_ROWS; from += PAGE_SIZE) {
      const { data, error } = await client
        .from('products')
        .select('id,sku,name,unit,status,created_at')
        .order('name')
        .range(from, Math.min(from + PAGE_SIZE - 1, MAX_EXPORT_ROWS - 1));
      if (error) throw error;
      rows.push(...(data ?? []));
      if (!data || data.length < PAGE_SIZE) break;
    }
    if (rows.length >= MAX_EXPORT_ROWS) throw new Error(`تصدير أكثر من ${MAX_EXPORT_ROWS.toLocaleString('ar-YE')} منتج غير مدعوم في عملية واحدة.`);
    return rows;
  }

  async function exportProducts() {
    setBusy(true); setError(null); setMessage(null);
    try {
      const now = new Date().toISOString();
      const [products, priceResult] = await Promise.all([
        fetchAllProducts(),
        client.from('product_prices')
          .select('product_id,amount,valid_from,valid_to,price_lists!inner(tier,currency)')
          .lte('valid_from', now)
          .or(`valid_to.is.null,valid_to.gte.${now}`)
          .order('valid_from', { ascending: false })
          .limit(MAX_PRICE_ROWS)
      ]);
      if (priceResult.error) throw priceResult.error;
      if ((priceResult.data?.length ?? 0) >= MAX_PRICE_ROWS) throw new Error(`بيانات الأسعار تتجاوز الحد الآمن وهو ${MAX_PRICE_ROWS.toLocaleString('ar-YE')} سجل.`);
      const priceByProduct = new Map<string, { retail?: number; wholesale?: number; distributor?: number; currency?: string }>();
      for (const row of priceResult.data ?? []) {
        const tier = (row.price_lists as { tier?: string; currency?: string } | null)?.tier;
        if (!tier || !['retail', 'wholesale', 'distributor'].includes(tier)) continue;
        const current = priceByProduct.get(row.product_id) ?? {};
        if (current[tier as 'retail' | 'wholesale' | 'distributor'] === undefined) current[tier as 'retail' | 'wholesale' | 'distributor'] = Number(row.amount);
        current.currency ??= (row.price_lists as { currency?: string } | null)?.currency;
        priceByProduct.set(row.product_id, current);
      }
      const rows = products.map((product) => ({
        SKU: product.sku, Name: product.name, Unit: product.unit, Status: product.status,
        'Retail Price': priceByProduct.get(product.id)?.retail ?? '',
        'Wholesale Price': priceByProduct.get(product.id)?.wholesale ?? '',
        'Distributor Price': priceByProduct.get(product.id)?.distributor ?? '',
        Currency: priceByProduct.get(product.id)?.currency ?? 'YER', CreatedAt: product.created_at
      }));
      downloadCsv(`aghbari-products-${new Date().toISOString().slice(0, 10)}.csv`, ['SKU','Name','Unit','Status','Retail Price','Wholesale Price','Distributor Price','Currency','CreatedAt'], rows);
      setMessage(`تم تصدير ${rows.length} منتجًا.`);
    } catch (e) { setError(e instanceof Error ? e.message : 'تعذر تصدير البيانات.'); }
    finally { setBusy(false); }
  }

  return <div className="admin-card"><h3>تصدير بيانات التشغيل</h3><p>تصدير الكتالوج والأسعار المصرح بها كملف CSV متوافق مع Excel، دون إضافة أي لوحة تحليلات داخل الأغبري.</p><button disabled={busy} onClick={() => void exportProducts()}>{busy ? 'جارٍ التصدير…' : 'تصدير الكتالوج والأسعار'}</button>{error && <div className="error-banner" role="alert">{error}</div>}{message && <div className="success" role="status">{message}</div>}</div>;
}
