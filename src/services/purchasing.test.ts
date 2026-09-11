import { describe, expect, it } from 'vitest';
import { validatePurchaseOrderInput, validateReceiveInput } from './purchasing';

const supplier = '11111111-1111-4111-8111-111111111111';
const warehouse = '22222222-2222-4222-8222-222222222222';
const product = '33333333-3333-4333-8333-333333333333';
const item = '44444444-4444-4444-8444-444444444444';
const key = 'aghbari-purchase-20260911-001';

describe('purchasing input contracts', () => {
  it('accepts a valid purchase order and rejects duplicate products', () => {
    expect(() => validatePurchaseOrderInput({ supplierId: supplier, warehouseId: warehouse, idempotencyKey: key, lines: [{ productId: product, quantity: 2, unitCost: 10 }], currency: 'YER' })).not.toThrow();
    expect(() => validatePurchaseOrderInput({ supplierId: supplier, warehouseId: warehouse, idempotencyKey: key, lines: [{ productId: product, quantity: 2, unitCost: 10 }, { productId: product, quantity: 1, unitCost: 10 }] })).toThrow('تكرار المنتج');
  });

  it('rejects fractional, unsafe, negative and unsupported monetary inputs', () => {
    expect(() => validatePurchaseOrderInput({ supplierId: supplier, warehouseId: warehouse, idempotencyKey: key, lines: [{ productId: product, quantity: 1.5, unitCost: 10 }] })).toThrow('عددًا صحيحًا');
    expect(() => validatePurchaseOrderInput({ supplierId: supplier, warehouseId: warehouse, idempotencyKey: key, lines: [{ productId: product, quantity: 1, unitCost: -1 }] })).toThrow('غير سالب');
    expect(() => validatePurchaseOrderInput({ supplierId: supplier, warehouseId: warehouse, idempotencyKey: key, lines: [{ productId: product, quantity: 1, unitCost: Number.MAX_SAFE_INTEGER }] })).toThrow('آمنة');
    expect(() => validatePurchaseOrderInput({ supplierId: supplier, warehouseId: warehouse, idempotencyKey: key, lines: [{ productId: product, quantity: 1, unitCost: 10 }], currency: 'EUR' })).toThrow('العملة غير مدعومة');
  });

  it('rejects invalid receiving quantities and duplicate purchase-order items', () => {
    expect(() => validateReceiveInput({ purchaseOrderId: supplier, idempotencyKey: key, lines: [{ purchaseOrderItemId: item, productId: product, quantity: 0 }] })).toThrow('بين 1 و10');
    expect(() => validateReceiveInput({ purchaseOrderId: supplier, idempotencyKey: key, lines: [{ purchaseOrderItemId: item, productId: product, quantity: 1 }, { purchaseOrderItemId: item, productId: product, quantity: 1 }] })).toThrow('تكرار بند');
  });
});
