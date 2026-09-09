import { describe, expect, it } from 'vitest';
import { PRODUCT_XLSX_PROFILE_V1, canonicalBusinessIdentity, resolveCanonicalColumn } from './importProfiles';
import { calculateDataQualityScore, classifyDataQuality } from './import';

describe('canonical import contracts', () => {
  it('preserves leading zeroes and string semantics for business codes', () => {
    expect(canonicalBusinessIdentity('  000123  ')).toBe('000123');
    expect(canonicalBusinessIdentity(123)).toBe('123');
  });

  it('resolves Arabic and English aliases through the single profile', () => {
    expect(resolveCanonicalColumn('كود الصنف', PRODUCT_XLSX_PROFILE_V1)).toBe('SKU');
    expect(resolveCanonicalColumn('سعر الجملة', PRODUCT_XLSX_PROFILE_V1)).toBe('Wholesale Price');
    expect(resolveCanonicalColumn('SKU', PRODUCT_XLSX_PROFILE_V1)).toBe('SKU');
  });

  it('keeps DQS bands aligned with the production thresholds', () => {
    expect(classifyDataQuality(100)).toBe('Excellent');
    expect(classifyDataQuality(89.99)).toBe('Acceptable');
    expect(classifyDataQuality(74.99)).toBe('Warning');
    expect(classifyDataQuality(49.99)).toBe('Reject');
    expect(calculateDataQualityScore(100, 0, 0)).toBe(100);
  });
});
