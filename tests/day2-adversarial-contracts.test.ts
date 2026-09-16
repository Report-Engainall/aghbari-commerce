import { describe, expect, it } from 'vitest';
import { validateInventoryTransferInput, validateStockThresholdInput } from '../src/services/inventory';
import { validatePurchaseOrderInput, validateReceiveInput } from '../src/services/purchasing';
import { assertStaffOrderSummary } from '../src/services/staffOrders';

const A = '11111111-1111-4111-8111-111111111111';
const B = '22222222-2222-4222-8222-222222222222';
const C = '33333333-3333-4333-8333-333333333333';
const key = 'day2-adversarial-key-001';

describe('DAY2 adversarial domain contracts', () => {
  it('rejects inventory transfer identity and quantity attacks', () => {
    expect(() => validateInventoryTransferInput(A, A, key, [{ productId: C, quantity: 1 }])).toThrow();
    expect(() => validateInventoryTransferInput(A, B, key, [{ productId: C, quantity: 0 }])).toThrow();
    expect(() => validateInventoryTransferInput(A, B, key, [{ productId: C, quantity: 1.5 }])).toThrow();
    expect(() => validateInventoryTransferInput(A, B, key, [{ productId: C, quantity: 1 }, { productId: C, quantity: 2 }])).toThrow();
    expect(() => validateInventoryTransferInput(A, B, 'short', [{ productId: C, quantity: 1 }])).toThrow();
  });

  it('rejects invalid stock threshold relationships', () => {
    expect(() => validateStockThresholdInput(A, C, 10, 20, 30)).not.toThrow();
    expect(() => validateStockThresholdInput(A, C, 10, 20, 5)).toThrow();
    expect(() => validateStockThresholdInput(A, C, -1, 20)).toThrow();
    expect(() => validateStockThresholdInput(A, C, 10, 0)).toThrow();
  });

  it('rejects duplicate and malformed purchase lines', () => {
    const base = { supplierId: A, warehouseId: B, idempotencyKey: key, lines: [{ productId: C, quantity: 2, unitCost: 100 }] };
    expect(() => validatePurchaseOrderInput(base)).not.toThrow();
    expect(() => validatePurchaseOrderInput({ ...base, lines: [{ productId: C, quantity: 2, unitCost: 100 }, { productId: C, quantity: 1, unitCost: 100 }] })).toThrow();
    expect(() => validatePurchaseOrderInput({ ...base, lines: [{ productId: C, quantity: 1.25, unitCost: 100 }] })).toThrow();
    expect(() => validatePurchaseOrderInput({ ...base, lines: [{ productId: C, quantity: 1, unitCost: -0.01 }] })).toThrow();
    expect(() => validatePurchaseOrderInput({ ...base, currency: 'EUR' })).toThrow();
  });

  it('rejects malformed receiving batches before they reach the RPC', () => {
    const base = { purchaseOrderId: A, idempotencyKey: key, lines: [{ purchaseOrderItemId: B, productId: C, quantity: 2 }] };
    expect(() => validateReceiveInput(base)).not.toThrow();
    expect(() => validateReceiveInput({ ...base, lines: [{ ...base.lines[0], quantity: 0 }] })).toThrow();
    expect(() => validateReceiveInput({ ...base, lines: [{ ...base.lines[0], quantity: 1 }, { ...base.lines[0], quantity: 1 }] })).toThrow();
    expect(() => validateReceiveInput({ ...base, idempotencyKey: 'short' })).toThrow();
  });

  it('fails closed on malformed staff order responses', () => {
    expect(() => assertStaffOrderSummary(null)).toThrow();
    expect(() => assertStaffOrderSummary({ id: 'bad' })).toThrow();
    expect(() => assertStaffOrderSummary({ id: A, customer_id: B, warehouse_id: C, order_number: 0, status: 'pending', total: 10, currency: 'YER', customer_name: 'عميل', created_at: new Date().toISOString(), updated_at: new Date().toISOString() })).toThrow();
    expect(() => assertStaffOrderSummary({ id: A, customer_id: B, warehouse_id: C, order_number: 1, status: 'unknown', total: 10, currency: 'YER', customer_name: 'عميل', created_at: new Date().toISOString(), updated_at: new Date().toISOString() })).toThrow();
  });
});
