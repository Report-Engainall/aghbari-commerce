import { describe, expect, it } from 'vitest';
import { validateCashAccountInput, validateExpenseInput, validatePaymentInput } from './finance';

const branch = '11111111-1111-4111-8111-111111111111';
const cash = '22222222-2222-4222-8222-222222222222';
const invoice = '33333333-3333-4333-8333-333333333333';
const paymentKey = 'test-payment-key-001';

describe('finance input boundaries', () => {
  it('accepts a valid cash account', () => expect(() => validateCashAccountInput(branch, 'الخزينة الرئيسية', 'YER', 1000)).not.toThrow());
  it('rejects malformed branch and empty account name', () => {
    expect(() => validateCashAccountInput('bad', 'Cash', 'YER', 0)).toThrow();
    expect(() => validateCashAccountInput(branch, '   ', 'YER', 0)).toThrow();
  });
  it('rejects non-string runtime values instead of leaking TypeError', () => {
    expect(() => validateCashAccountInput(123 as unknown as string, 'Cash', 'YER', 0)).toThrow();
    expect(() => validateCashAccountInput(branch, 123 as unknown as string, 'YER', 0)).toThrow();
    expect(() => validateExpenseInput(123 as unknown as string, cash, 'تشغيل', 10, 'YER', '')).toThrow();
    expect(() => validateExpenseInput(branch, cash, 123 as unknown as string, 10, 'YER', '')).toThrow();
    expect(() => validateExpenseInput(branch, cash, 'تشغيل', 10, 'YER', 123 as unknown as string)).toThrow();
    expect(() => validatePaymentInput(123 as unknown as string, 100, 'cash', cash, 'ref', paymentKey)).toThrow();
    expect(() => validatePaymentInput(invoice, 100, 123 as unknown as string, cash, 'ref', paymentKey)).toThrow();
    expect(() => validatePaymentInput(invoice, 100, 'cash', cash, 123 as unknown as string, paymentKey)).toThrow();
    expect(() => validatePaymentInput(invoice, 100, 'cash', cash, 'ref', 123 as unknown as string)).toThrow();
  });
  it('rejects invalid currency and negative opening balance', () => {
    expect(() => validateCashAccountInput(branch, 'Cash', 'Y', 0)).toThrow();
    expect(() => validateCashAccountInput(branch, 'Cash', 'YER', -1)).toThrow();
  });
  it('rejects non-finite and unsafe opening balances', () => {
    expect(() => validateCashAccountInput(branch, 'Cash', 'YER', Infinity)).toThrow();
    expect(() => validateCashAccountInput(branch, 'Cash', 'YER', Number.MAX_SAFE_INTEGER + 1)).toThrow();
  });
  it('accepts valid payment methods including surrounding whitespace', () => {
    for (const method of ['cash', 'bank_transfer', 'card', 'other']) {
      expect(() => validatePaymentInput(invoice, 100, method, cash, 'ref-1', paymentKey)).not.toThrow();
    }
    expect(() => validatePaymentInput(invoice, 100, ' cash ', cash, 'ref-1', paymentKey)).not.toThrow();
  });
  it('rejects malformed invoice, zero amount and unsupported method', () => {
    expect(() => validatePaymentInput('bad', 100, 'cash', cash, 'ref', paymentKey)).toThrow();
    expect(() => validatePaymentInput(invoice, 0, 'cash', cash, 'ref', paymentKey)).toThrow();
    expect(() => validatePaymentInput(invoice, 100, 'crypto', cash, 'ref', paymentKey)).toThrow();
  });
  it('rejects non-finite and unsafe payment amounts and malformed cash account', () => {
    expect(() => validatePaymentInput(invoice, Infinity, 'cash', cash, 'ref', paymentKey)).toThrow();
    expect(() => validatePaymentInput(invoice, Number.MAX_SAFE_INTEGER + 1, 'cash', cash, 'ref', paymentKey)).toThrow();
    expect(() => validatePaymentInput(invoice, 100, 'cash', 'bad', 'ref', paymentKey)).toThrow();
  });
  it('rejects overlong payment references', () => expect(() => validatePaymentInput(invoice, 100, 'cash', cash, 'x'.repeat(201), paymentKey)).toThrow());
  it('rejects missing or invalid idempotency keys', () => {
    expect(() => validatePaymentInput(invoice, 100, 'cash', cash, 'ref', '')).toThrow();
    expect(() => validatePaymentInput(invoice, 100, 'cash', cash, 'ref', 'x'.repeat(129))).toThrow();
  });
  it('accepts a valid expense', () => expect(() => validateExpenseInput(branch, cash, 'تشغيل', 250, 'YER', 'مصروف تشغيل')).not.toThrow());
  it('rejects malformed expense ids, empty category, invalid amount and currency', () => {
    expect(() => validateExpenseInput('bad', cash, 'تشغيل', 250, 'YER', '')).toThrow();
    expect(() => validateExpenseInput(branch, 'bad', 'تشغيل', 250, 'YER', '')).toThrow();
    expect(() => validateExpenseInput(branch, cash, '  ', 250, 'YER', '')).toThrow();
    expect(() => validateExpenseInput(branch, cash, 'تشغيل', -1, 'YER', '')).toThrow();
    expect(() => validateExpenseInput(branch, cash, 'تشغيل', 250, 'Y', '')).toThrow();
  });
  it('rejects overlong expense description', () => expect(() => validateExpenseInput(branch, cash, 'تشغيل', 250, 'YER', 'x'.repeat(2001))).toThrow());
  it('rejects unsafe expense amounts', () => expect(() => validateExpenseInput(branch, cash, 'تشغيل', Number.MAX_SAFE_INTEGER + 1, 'YER', '')).toThrow());
});
