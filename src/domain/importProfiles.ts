export type ImportProfileStatus = 'draft' | 'active' | 'retired';

export interface ImportProfile {
  profileId: string;
  profileName: string;
  reportType: string;
  source: string;
  version: number;
  requiredColumns: string[];
  optionalColumns: string[];
  ignoredColumns: string[];
  synonyms: Record<string, string[]>;
  transformationRules: string[];
  validationRules: string[];
  matchingKey: 'item_code' | 'customer_code' | 'supplier_code' | string;
  mergeStrategy: 'upsert' | 'append' | 'replace' | string;
  dateRules: Record<string, string>;
  status: ImportProfileStatus;
}

/** Business identities remain strings so leading zeroes are never lost. */
export function canonicalBusinessIdentity(value: unknown): string {
  return String(value ?? '').trim().replace(/\\s+/g, ' ');
}

export function normalizeColumnName(value: unknown): string {
  return String(value ?? '').trim().toLocaleLowerCase();
}

export function resolveCanonicalColumn(header: unknown, profile: ImportProfile): string | null {
  const normalized = normalizeColumnName(header);
  for (const canonical of [...profile.requiredColumns, ...profile.optionalColumns]) {
    if (normalizeColumnName(canonical) === normalized) return canonical;
    const aliases = profile.synonyms[canonical] ?? [];
    if (aliases.some((alias) => normalizeColumnName(alias) === normalized)) return canonical;
  }
  return profile.ignoredColumns.some((column) => normalizeColumnName(column) === normalized) ? null : null;
}

export const PRODUCT_XLSX_PROFILE_V1: ImportProfile = Object.freeze({
  profileId: 'products-xlsx',
  profileName: 'المنتجات XLSX',
  reportType: 'products',
  source: 'xlsx',
  version: 1,
  requiredColumns: ['SKU', 'Name', 'Unit', 'Category', 'Quantity', 'Retail Price', 'Wholesale Price', 'Distributor Price'],
  optionalColumns: [],
  ignoredColumns: [],
  synonyms: {
    SKU: ['sku', 'item_code', 'كود الصنف', 'كود الصنف الرئيسي'],
    Name: ['name', 'item_name', 'اسم الصنف'],
    Unit: ['unit', 'الوحدة'],
    Category: ['category', 'التصنيف', 'الفئة'],
    Quantity: ['quantity', 'qty', 'الكمية', 'الرصيد'],
    'Retail Price': ['retail price', 'سعر التجزئة'],
    'Wholesale Price': ['wholesale price', 'سعر الجملة'],
    'Distributor Price': ['distributor price', 'سعر الموزع']
  },
  transformationRules: ['trim-text', 'canonical-business-identity'],
  validationRules: ['required-columns', 'non-negative-quantity', 'non-negative-money', 'duplicate-business-identity'],
  matchingKey: 'item_code',
  mergeStrategy: 'upsert',
  dateRules: {},
  status: 'active'
});
