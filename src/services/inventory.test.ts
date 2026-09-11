import { describe, expect, it, vi } from 'vitest';

const rpc = vi.fn();
vi.mock('../lib/supabase', () => ({ requireSupabase: () => ({ rpc }) }));

import { validateInventoryTransferInput, validateStockThresholdInput } from './inventory';

const warehouseA = '11111111-1111-4111-8111-111111111111';
const warehouseB = '22222222-2222-4222-8222-222222222222';
const productA = '33333333-3333-4333-8333-333333333333';

const validKey = 'aghbari-transfer-20260911-001';

describe('inventory input contracts', () => {
  it('accepts integer quantities and rejects fractional transfer quantities', () => {
    expect(() => validateInventoryTransferInput(warehouseA, warehouseB, validKey, [{ productId: productA, quantity: 3 }])).not.toThrow();
    expect(() => validateInventoryTransferInput(warehouseA, warehouseB, validKey, [{ productId: productA, quantity: 1.5 }])).toThrow('عددًا صحيحًا');
  });

  it('rejects unsafe or oversized quantities before RPC execution', () => {
    expect(() => validateInventoryTransferInput(warehouseA, warehouseB, validKey, [{ productId: productA, quantity: 1000001 }])).toThrow('الحد المسموح');
    expect(() => validateStockThresholdInput(warehouseA, productA, 1.5, 2)).toThrow('عددًا صحيحًا');
    expect(rpc).not.toHaveBeenCalled();
  });

  it('rejects an invalid threshold ordering', () => {
    expect(() => validateStockThresholdInput(warehouseA, productA, 10, 5, 9)).toThrow('الحد الأقصى لا يمكن أن يكون أقل من الحد الأدنى');
  });

  it('rejects duplicate products and same-warehouse transfers', () => {
    expect(() => validateInventoryTransferInput(warehouseA, warehouseA, validKey, [{ productId: productA, quantity: 1 }])).toThrow('نفس المخزن');
    expect(() => validateInventoryTransferInput(warehouseA, warehouseB, validKey, [{ productId: productA, quantity: 1 }, { productId: productA, quantity: 2 }])).toThrow('تكرار المنتج');
  });
});
