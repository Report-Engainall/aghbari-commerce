import { readSheet } from 'read-excel-file/browser';
import { fingerprintFile, MAX_IMPORT_CELL_LENGTH, MAX_IMPORT_COLUMNS, MAX_IMPORT_FILE_BYTES, MAX_IMPORT_ROWS, normalizeSku, validateImportRows, type ImportRow } from '../domain/import';
import { PRODUCT_XLSX_PROFILE_V1, resolveCanonicalColumn } from '../domain/importProfiles';
import { requireSupabase } from '../lib/supabase';

const REQUIRED_HEADERS = PRODUCT_XLSX_PROFILE_V1.requiredColumns;
const MAX_DATA_ROWS = MAX_IMPORT_ROWS;
const MAX_SOURCE_NAME_LENGTH = 180;
const XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const ZIP_SIGNATURES = ['504b0304', '504b0506', '504b0708'];
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export interface CommittedImportResult { imported_rows: number; products_created: number; products_updated: number; inventory_changed: number; }

function assertUuid(value: unknown, message: string): string {
  if (typeof value !== 'string' || !UUID_PATTERN.test(value)) throw new Error(message);
  return value;
}

function assertCommittedImportResult(value: unknown): CommittedImportResult {
  if (!value || typeof value !== 'object') throw new Error('استجابة اعتماد الاستيراد غير صالحة. لم يتم إثبات اعتماد الاستيراد.');
  const candidate = value as Partial<CommittedImportResult>;
  const fields: Array<keyof CommittedImportResult> = ['imported_rows', 'products_created', 'products_updated', 'inventory_changed'];
  for (const field of fields) if (!Number.isSafeInteger(candidate[field]) || (candidate[field] as number) < 0) throw new Error('استجابة اعتماد الاستيراد ناقصة أو غير صالحة. لم يتم إثبات اعتماد الاستيراد.');
  return { imported_rows: candidate.imported_rows!, products_created: candidate.products_created!, products_updated: candidate.products_updated!, inventory_changed: candidate.inventory_changed! };
}

async function assertXlsxContainer(file: File): Promise<void> {
  const header = new Uint8Array(await file.slice(0, 4).arrayBuffer());
  const signature = Array.from(header, (byte) => byte.toString(16).padStart(2, '0')).join('');
  if (!ZIP_SIGNATURES.includes(signature)) throw new Error('الملف لا يبدو كحاوية XLSX صالحة.');
}

export async function parseProductWorkbook(file: File) {
  if (!file.name.toLowerCase().endsWith('.xlsx') || (file.type && file.type !== XLSX_MIME && file.type !== 'application/zip')) throw new Error('يجب رفع ملف XLSX');
  if (file.size < 1 || file.size > MAX_IMPORT_FILE_BYTES) throw new Error('حجم ملف الاستيراد يتجاوز الحد الأقصى المسموح به وهو 100 MB.');
  await assertXlsxContainer(file);

  const rows = await readSheet(file);
  const [header = [], ...data] = rows;
  if (header.length > MAX_IMPORT_COLUMNS) throw new Error(`ملف الاستيراد يتجاوز الحد الأقصى وهو ${MAX_IMPORT_COLUMNS} عمودًا.`);
  if (data.length > MAX_DATA_ROWS) throw new Error(`ملف الاستيراد يتجاوز الحد الأقصى وهو ${MAX_DATA_ROWS.toLocaleString('ar-YE')} صف.`);
  const normalizedHeaders = header.map((cell) => String(cell ?? '').trim());
  const canonicalHeaders = normalizedHeaders.map((headerName) => resolveCanonicalColumn(headerName, PRODUCT_XLSX_PROFILE_V1) ?? headerName);
  const missing = REQUIRED_HEADERS.filter((name) => !canonicalHeaders.includes(name));
  if (missing.length) throw new Error(`أعمدة ناقصة: ${missing.join(', ')}`);

  const index = (name: string) => canonicalHeaders.indexOf(name);
  const toText = (value: unknown) => String(value ?? '').trim();
  const toNumber = (value: unknown) => Number(String(value ?? '').replace(/,/g, '').trim());
  const parsed: ImportRow[] = data.map((row, i) => ({
    rowNumber: i + 2,
    sku: normalizeSku(row[index('SKU')]),
    name: toText(row[index('Name')]),
    unit: toText(row[index('Unit')]),
    category: toText(row[index('Category')]),
    quantity: toNumber(row[index('Quantity')]),
    prices: { retail: toNumber(row[index('Retail Price')]), wholesale: toNumber(row[index('Wholesale Price')]), distributor: toNumber(row[index('Distributor Price')]) }
  }));
  const oversizedCell = parsed.find((row) => [row.sku, row.name, row.unit, row.category].some((value) => value.length > MAX_IMPORT_CELL_LENGTH));
  if (oversizedCell) throw new Error(`الصف ${oversizedCell.rowNumber} يحتوي خلية تتجاوز ${MAX_IMPORT_CELL_LENGTH} حرف.`);
  return { rows: parsed, diagnostics: validateImportRows(parsed), fingerprint: await fingerprintFile(file), profile: PRODUCT_XLSX_PROFILE_V1 };
}

export async function stageProductImport(file: File) {
  const parsed = await parseProductWorkbook(file);
  if (parsed.diagnostics.length) return { ...parsed, jobId: null };
  const sourceName = file.name.trim().slice(0, MAX_SOURCE_NAME_LENGTH) || 'products.xlsx';
  const { data, error } = await requireSupabase().rpc('stage_product_import', { p_source_name: sourceName, p_source_fingerprint: parsed.fingerprint, p_rows: parsed.rows });
  if (error) throw error;
  return { ...parsed, jobId: assertUuid(data, 'استجابة تجهيز الاستيراد غير صالحة. لم يتم إنشاء مهمة استيراد موثوقة.') };
}

export async function commitProductImport(importJobId: string, warehouseId: string) {
  assertUuid(importJobId, 'معرّف مهمة الاستيراد غير صالح.');
  assertUuid(warehouseId, 'معرّف المستودع غير صالح.');
  const { data, error } = await requireSupabase().rpc('commit_product_import', { p_import_job_id: importJobId, p_warehouse_id: warehouseId });
  if (error) throw error;
  const rows = Array.isArray(data) ? data : [];
  if (rows.length !== 1) throw new Error('استجابة اعتماد الاستيراد غير مكتملة. لم يتم إثبات اعتماد الاستيراد.');
  return assertCommittedImportResult(rows[0]);
}
