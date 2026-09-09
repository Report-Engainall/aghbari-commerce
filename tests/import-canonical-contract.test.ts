import { describe, expect, it } from 'vitest';
import { PRODUCT_XLSX_PROFILE_V1, canonicalBusinessIdentity, resolveCanonicalColumn } from '../src/domain/importProfiles';
import { calculateDataQualityScore, classifyDataQuality } from '../src/domain/import';

describe('unified import contracts', () => {
  it('preserves leading zeroes and string semantics', () => {
    expect(canonicalBusinessIdentity('  000123  ')).toBe('000123');
    expect(canonicalBusinessIdentity(123)).toBe('123');
  });

  it('resolves Arabic and English aliases through one profile', () => {
    expect(resolveCanonicalColumn('كود الصنف', PRODUCT_XLSX_PROFILE_V1)).toBe('SKU');
    expect(resolveCanonicalColumn('سعر الجملة', PRODUCT_XLSX_PROFILE_V1)).toBe('Wholesale Price');
    expect(resolveCanonicalColumn('SKU', PRODUCT_XLSX_PROFILE_V1)).toBe('SKU');
  });

  it('does not invent unknown canonical fields', () => {
    expect(resolveCanonicalColumn('unknown column', PRODUCT_XLSX_PROFILE_V1)).toBeNull();
  });

  it('keeps DQS thresholds deterministic', () => {
    expect(classifyDataQuality(100)).toBe('Excellent');
    expect(classifyDataQuality(89.99)).toBe('Acceptable');
    expect(classifyDataQuality(74.99)).toBe('Warning');
    expect(classifyDataQuality(49.99)).toBe('Reject');
    expect(calculateDataQualityScore(100, 0, 0)).toBe(100);
  });
});
