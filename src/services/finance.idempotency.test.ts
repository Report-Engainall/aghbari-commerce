import { describe, expect, it } from 'vitest';
import { validatePaymentInput } from './finance';

describe('payment idempotency contract', () => {
  const invoice = '11111111-1111-4111-8111-111111111111';
  const account = '22222222-2222-4222-8222-222222222222';

  it('requires an idempotency key', () => {
    expect(() => validatePaymentInput(invoice, 100, 'cash', account, '', '')).toThrow(/مفتاح العملية/);
  });

  it('accepts a valid payment command with an idempotency key', () => {
    expect(() => validatePaymentInput(invoice, 100, 'cash', account, '', 'payment-op-001')).not.toThrow();
  });

  it('rejects unsupported payment methods', () => {
    expect(() => validatePaymentInput(invoice, 100, 'crypto', null, '', 'payment-op-002')).toThrow(/طريقة الدفع/);
  });

  it('rejects oversized idempotency keys', () => {
    expect(() => validatePaymentInput(invoice, 100, 'cash', account, '', 'x'.repeat(129))).toThrow(/مفتاح العملية/);
  });
});
