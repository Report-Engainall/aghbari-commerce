import readSheet from '../lib/read-excel-file-browser';
import { normalizeSku } from '../domain/import';
import type { Product } from '../domain/types';

const MAX_WORKBOOK_BYTES = 10 * 1024 * 1024;
const MAX_ROWS = 500;
const ZIP_SIGNATURES = new Set(['504b0304', '504b0506', '504b0708']);

type QuickRow = { rowNumber: number; sku: string; quantity: number; rawName: string };
export type QuickOrderDiagnostic = { rowNumber: number; sku: string; quantity: number; message: string };

export async function parseQuickOrderWorkbook(file: File): Promise<QuickRow[]> {
  if (!file.name.toLowerCase().endsWith('.xlsx')) throw new Error('يجب رفع ملف XLSX للطلب السريع.');
  if (file.size < 1 || file.size > MAX_WORKBOOK_BYTES) throw new Error('حجم ملف الطلب السريع غير صالح. الحد الأقصى 10 MB.');
  const header = new Uint8Array(await file.slice(0, 4).arrayBuffer());
  const signature = Array.from(header, (byte) => byte.toString(16).padStart(2, '0')).join('');
  if (!ZIP_SIGNATURES.has(signature)) throw new Error('الملف ليس حاوية XLSX صالحة.');
  const rows = await readSheet(file);
  const [headerRow = [], ...data] = rows;
  const headers = headerRow.map((cell) => String(cell ?? '').trim().toLowerCase());
  const skuIndex = headers.findIndex((value) => ['sku', 'رمز الصنف', 'كود الصنف', 'الباركود'].includes(value));
  const quantityIndex = headers.findIndex((value) => ['quantity', 'qty', 'الكمية'].includes(value));
  if (skuIndex < 0 || quantityIndex < 0) throw new Error('الملف يجب أن يحتوي على أعمدة SKU والكمية.');
  if (data.length > MAX_ROWS) throw new Error(`ملف الطلب السريع يتجاوز ${MAX_ROWS} صف.`);
  return data.map((row, index) => ({
    rowNumber: index + 2,
    sku: normalizeSku(row[skuIndex]),
    quantity: Number(String(row[quantityIndex] ?? '').replace(/,/g, '').trim()),
    rawName: String(row[skuIndex + 1] ?? '').trim()
  }));
}

export function validateQuickOrderRows(rows: QuickRow[], products: Product[]): { valid: Array<QuickRow & { product: Product }>; diagnostics: QuickOrderDiagnostic[] } {
  const bySku = new Map(products.map((product) => [normalizeSku(product.sku), product]));
  const seen = new Set<string>();
  const diagnostics: QuickOrderDiagnostic[] = [];
  const valid: Array<QuickRow & { product: Product }> = [];
  for (const row of rows) {
    const sku = normalizeSku(row.sku);
    if (!sku) { diagnostics.push({ ...row, message: 'SKU مفقود.' }); continue; }
    if (!Number.isSafeInteger(row.quantity) || row.quantity < 1) { diagnostics.push({ ...row, message: 'الكمية يجب أن تكون عددًا صحيحًا موجبًا.' }); continue; }
    if (seen.has(sku)) { diagnostics.push({ ...row, message: 'الصنف مكرر في الملف.' }); continue; }
    seen.add(sku);
    const product = bySku.get(sku);
    if (!product) { diagnostics.push({ ...row, message: 'الصنف غير موجود أو غير مصرح به.' }); continue; }
    if (product.status !== 'active') { diagnostics.push({ ...row, message: 'الصنف غير متاح للطلب.' }); continue; }
    if (row.quantity > product.availableQuantity) { diagnostics.push({ ...row, message: `الكمية تتجاوز المخزون المتاح (${product.availableQuantity}).` }); continue; }
    valid.push({ ...row, sku, product });
  }
  return { valid, diagnostics };
}
