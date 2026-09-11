import { describe, expect, it } from 'vitest';
import { validateQuickOrderRows } from './customerQuickOrder';
import type { Product } from '../domain/types';

const product = (overrides: Partial<Product> = {}): Product => ({
  id: '11111111-1111-4111-8111-111111111111', sku: 'SKU-001', name: 'صنف اختبار', unit: 'كرتون', category: 'اختبار', availableQuantity: 20, status: 'active', ...overrides
});

describe('customer quick order validation', () => {
  it('accepts valid SKU and quantity', () => {
    const result = validateQuickOrderRows([{ rowNumber: 2, sku: 'SKU-001', quantity: 5, rawName: '' }], [product()]);
    expect(result.diagnostics).toHaveLength(0);
    expect(result.valid).toHaveLength(1);
    expect(result.valid[0].quantity).toBe(5);
  });
  it('rejects missing product', () => {
    const result = validateQuickOrderRows([{ rowNumber: 2, sku: 'UNKNOWN', quantity: 5, rawName: '' }], [product()]);
    expect(result.valid).toHaveLength(0);
    expect(result.diagnostics[0].message).toContain('غير موجود');
  });
  it('rejects invalid and excessive quantity', () => {
    expect(validateQuickOrderRows([{ rowNumber: 2, sku: 'SKU-001', quantity: 0, rawName: '' }], [product()]).diagnostics).toHaveLength(1);
    expect(validateQuickOrderRows([{ rowNumber: 2, sku: 'SKU-001', quantity: 21, rawName: '' }], [product()]).diagnostics[0].message).toContain('المخزون');
  });
  it('rejects duplicates and inactive products', () => {
    const duplicate = validateQuickOrderRows([
      { rowNumber: 2, sku: 'SKU-001', quantity: 1, rawName: '' },
      { rowNumber: 3, sku: 'SKU-001', quantity: 2, rawName: '' }
    ], [product()]);
    expect(duplicate.valid).toHaveLength(1);
    expect(duplicate.diagnostics[0].message).toContain('مكرر');
    const inactive = validateQuickOrderRows([{ rowNumber: 2, sku: 'SKU-001', quantity: 1, rawName: '' }], [product({ status: 'inactive' })]);
    expect(inactive.diagnostics[0].message).toContain('غير متاح');
  });
});
