import { describe, expect, it } from 'vitest';
import { calculateDataQualityScore, classifyDataQuality } from './import';

describe('import data quality', () => {
  it('returns excellent for clean data', () => {
    expect(calculateDataQualityScore(100, 0, 0)).toBe(100);
    expect(classifyDataQuality(100)).toBe('Excellent');
  });

  it('penalizes invalid rows more than warnings', () => {
    const invalid = calculateDataQualityScore(100, 10, 0);
    const warning = calculateDataQualityScore(100, 0, 10);
    expect(invalid).toBe(93);
    expect(warning).toBe(97);
    expect(invalid).toBeLessThan(warning);
  });

  it('uses the defined quality bands at boundaries', () => {
    expect(classifyDataQuality(90)).toBe('Excellent');
    expect(classifyDataQuality(89.99)).toBe('Acceptable');
    expect(classifyDataQuality(75)).toBe('Acceptable');
    expect(classifyDataQuality(74.99)).toBe('Warning');
    expect(classifyDataQuality(50)).toBe('Warning');
    expect(classifyDataQuality(49.99)).toBe('Reject');
    expect(classifyDataQuality(Number.NaN)).toBe('Reject');
  });
});
