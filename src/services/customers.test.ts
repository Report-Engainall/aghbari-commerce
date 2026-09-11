import { describe, expect, it } from 'vitest';
import { validateCustomerInput, validateCustomerTier } from './customers';

describe('customer input contracts', () => {
  it('normalizes valid customer data', () => {
    expect(validateCustomerInput('  متجر صنعاء  ', ' 771234567 ', 'wholesale')).toEqual({
      name: 'متجر صنعاء', phone: '771234567', tier: 'wholesale'
    });
  });

  it('rejects blank names', () => {
    expect(() => validateCustomerInput('   ', '', 'wholesale')).toThrow('اسم العميل مطلوب');
  });

  it('rejects oversized phone values', () => {
    expect(() => validateCustomerInput('عميل', '1'.repeat(51), 'retail')).toThrow('رقم هاتف العميل طويل جدًا');
  });

  it('rejects unsupported customer tiers at the service boundary', () => {
    expect(() => validateCustomerTier('owner' as never)).toThrow('فئة العميل غير مسموحة');
  });
});
