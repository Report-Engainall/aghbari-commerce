import { describe, expect, it } from 'vitest';
import { validatePurchaseOrderInput, validateReceiveInput } from './purchasing';

const supplier = '11111111-1111-4111-8111-111111111111';
const warehouse = '22222222-2222-4222-8222-222222222222';
const product = '33333333-3333-4333-8333-333333333333';
const product2 = '44444444-4444-4444-8444-444444444444';
const item = '55555555-5555-4555-8555-555555555555';
const key = 'purchase-idempotency-001';
const validPurchase = { supplierId: supplier, warehouseId: warehouse, idempotencyKey: key, lines: [{ productId: product, quantity: 2, unitCost: 100 }], currency: 'YER' };

describe('purchasing input boundaries', () => {
  it('accepts a valid purchase order', () => expect(() => validatePurchaseOrderInput(validPurchase)).not.toThrow());
  it('rejects malformed supplier or warehouse ids', () => { expect(() => validatePurchaseOrderInput({ ...validPurchase, supplierId: 'bad' })).toThrow(); expect(() => validatePurchaseOrderInput({ ...validPurchase, warehouseId: 'bad' })).toThrow(); });
  it('rejects missing lines and weak idempotency', () => { expect(() => validatePurchaseOrderInput({ ...validPurchase, lines: [] })).toThrow(); expect(() => validatePurchaseOrderInput({ ...validPurchase, idempotencyKey: 'short' })).toThrow(); });
  it('rejects duplicate products and invalid quantities', () => { expect(() => validatePurchaseOrderInput({ ...validPurchase, lines: [{ productId: product, quantity: 1, unitCost: 10 }, { productId: product, quantity: 2, unitCost: 20 }] })).toThrow(); expect(() => validatePurchaseOrderInput({ ...validPurchase, lines: [{ productId: product, quantity: 0, unitCost: 10 }] })).toThrow(); expect(() => validatePurchaseOrderInput({ ...validPurchase, lines: [{ productId: product, quantity: 1.5, unitCost: 10 }] })).toThrow(); expect(() => validatePurchaseOrderInput({ ...validPurchase, lines: [{ productId: product, quantity: 10_001, unitCost: 10 }] })).toThrow(); expect(() => validatePurchaseOrderInput({ ...validPurchase, lines: [{ productId: product, quantity: Number.MAX_SAFE_INTEGER + 1, unitCost: 10 }] })).toThrow(); });
  it('rejects negative or non-finite costs and invalid currency', () => { expect(() => validatePurchaseOrderInput({ ...validPurchase, lines: [{ productId: product, quantity: 1, unitCost: -1 }] })).toThrow(); expect(() => validatePurchaseOrderInput({ ...validPurchase, lines: [{ productId: product, quantity: 1, unitCost: Infinity }] })).toThrow(); expect(() => validatePurchaseOrderInput({ ...validPurchase, currency: 'bad' })).toThrow(); });
  it('accepts supported currencies case-insensitively', () => { for (const currency of ['YER', 'yer', 'USD', 'usd', 'SAR', 'sar']) expect(() => validatePurchaseOrderInput({ ...validPurchase, currency })).not.toThrow(); });
  it('accepts multiple distinct lines', () => expect(() => validatePurchaseOrderInput({ ...validPurchase, lines: [{ productId: product, quantity: 1, unitCost: 10 }, { productId: product2, quantity: 4, unitCost: 25 }] })).not.toThrow());
  it('accepts a valid receipt', () => expect(() => validateReceiveInput({ purchaseOrderId: supplier, idempotencyKey: key, lines: [{ purchaseOrderItemId: item, productId: product, quantity: 2 }] })).not.toThrow());
  it('rejects malformed purchase or item ids', () => { expect(() => validateReceiveInput({ purchaseOrderId: 'bad', idempotencyKey: key, lines: [{ purchaseOrderItemId: item, productId: product, quantity: 1 }] })).toThrow(); expect(() => validateReceiveInput({ purchaseOrderId: supplier, idempotencyKey: key, lines: [{ purchaseOrderItemId: 'bad', productId: product, quantity: 1 }] })).toThrow(); });
  it('rejects duplicate receipt items and invalid quantities', () => { expect(() => validateReceiveInput({ purchaseOrderId: supplier, idempotencyKey: key, lines: [{ purchaseOrderItemId: item, productId: product, quantity: 1 }, { purchaseOrderItemId: item, productId: product2, quantity: 1 }] })).toThrow(); expect(() => validateReceiveInput({ purchaseOrderId: supplier, idempotencyKey: key, lines: [{ purchaseOrderItemId: item, productId: product, quantity: 0 }] })).toThrow(); });
});
