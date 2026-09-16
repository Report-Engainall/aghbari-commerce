import { describe, expect, it } from 'vitest';
import { assertCreatedOrderReference, assertOrderTransitionInput } from './orders';

describe('order boundary validation', () => {
  it('accepts only a valid persisted order reference', () => {
    expect(assertCreatedOrderReference({ id: '550e8400-e29b-41d4-a716-446655440000', order_number: 42 })).toEqual({
      id: '550e8400-e29b-41d4-a716-446655440000',
      order_number: 42,
    });
  });

  it.each([
    null,
    undefined,
    {},
    { id: 'not-a-uuid', order_number: 42 },
    { id: '550e8400-e29b-41d4-a716-446655440000', order_number: 0 },
    { id: '550e8400-e29b-41d4-a716-446655440000', order_number: 1.5 },
  ])('rejects an unverifiable order response: %o', (value) => {
    expect(() => assertCreatedOrderReference(value)).toThrow();
  });

  it('accepts an allowed status transition input', () => {
    expect(assertOrderTransitionInput('550e8400-e29b-41d4-a716-446655440000', 'confirmed')).toEqual({
      orderId: '550e8400-e29b-41d4-a716-446655440000',
      status: 'confirmed',
    });
  });

  it.each([
    ['', 'confirmed'],
    ['not-a-uuid', 'confirmed'],
    ['550e8400-e29b-41d4-a716-446655440000', 'unknown'],
    ['550e8400-e29b-41d4-a716-446655440000', ''],
  ])('rejects invalid transition input: %o', (orderId, status) => {
    expect(() => assertOrderTransitionInput(orderId, status)).toThrow();
  });
});
