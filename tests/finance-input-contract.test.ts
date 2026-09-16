import { describe, expect, it } from 'vitest';
import { validateCashAccountInput, validateExpenseInput, validatePaymentInput } from '../src/services/finance';

const UUID = '11111111-1111-4111-8111-111111111111';

describe('finance input contracts', () => {
  it('accepts a valid payment', () => {
    expect(() => validatePaymentInput(UUID, 1250.5, 'cash', UUID, 'REC-001')).not.toThrow();
  });

  it('rejects non-positive, non-finite, and unsupported payment values', () => {
    expect(() => validatePaymentInput(UUID, 0, 'cash', UUID, '')).toThrow();
    expect(() => validatePaymentInput(UUID, Number.NaN, 'cash', UUID, '')).toThrow();
    expect(() => validatePaymentInput(UUID, 10, 'crypto', null, '')).toThrow();
    expect(() => validatePaymentInput('not-a-uuid', 10, 'cash', UUID, '')).toThrow();
  });

  it('rejects an invalid cash account for payment', () => {
    expect(() => validatePaymentInput(UUID, 10, 'cash', 'bad-account', '')).toThrow();
  });

  it('validates expenses and rejects oversized descriptions', () => {
    expect(() => validateExpenseInput(UUID, UUID, 'تشغيل', 500, 'YER', 'نقل')).not.toThrow();
    expect(() => validateExpenseInput(UUID, UUID, '', 500, 'YER', '')).toThrow();
    expect(() => validateExpenseInput(UUID, UUID, 'تشغيل', -1, 'YER', '')).toThrow();
    expect(() => validateExpenseInput(UUID, UUID, 'تشغيل', 500, 'INVALID', '')).toThrow();
    expect(() => validateExpenseInput(UUID, UUID, 'تشغيل', 500, 'YER', 'x'.repeat(2001))).toThrow();
  });

  it('validates cash account identity, currency and opening balance', () => {
    expect(() => validateCashAccountInput(UUID, 'الصندوق الرئيسي', 'YER', 0)).not.toThrow();
    expect(() => validateCashAccountInput(UUID, '', 'YER', 0)).toThrow();
    expect(() => validateCashAccountInput(UUID, 'الصندوق', 'BAD', 0)).toThrow();
    expect(() => validateCashAccountInput(UUID, 'الصندوق', 'YER', -1)).toThrow();
  });
});
