import { describe, expect, it, vi } from 'vitest';

const rpc = vi.fn();
vi.mock('../lib/supabase', () => ({ requireSupabase: () => ({ rpc }) }));
vi.mock('./offlineQueue', () => ({ drainOfflineOperations: vi.fn(), enqueueOfflineOperation: vi.fn(), OFFLINE_CART_REMOVE_ITEM: 'remove', OFFLINE_CART_SET_ITEM: 'set' }));

import { setCartItems } from './cart';

const productA = '11111111-1111-4111-8111-111111111111';
const productB = '22222222-2222-4222-8222-222222222222';

describe('setCartItems', () => {
  it('rejects an empty batch before calling the backend', async () => {
    await expect(setCartItems([])).rejects.toThrow('من 1 إلى 200');
    expect(rpc).not.toHaveBeenCalled();
  });

  it('rejects duplicate products before calling the backend', async () => {
    await expect(setCartItems([{ productId: productA, quantity: 1 }, { productId: productA, quantity: 2 }])).rejects.toThrow('تكرار المنتج');
    expect(rpc).not.toHaveBeenCalled();
  });

  it('rejects invalid quantities before calling the backend', async () => {
    await expect(setCartItems([{ productId: productA, quantity: 0 }])).rejects.toThrow('الكمية');
    expect(rpc).not.toHaveBeenCalled();
  });

  it('sends a normalized atomic RPC payload for valid items', async () => {
    rpc.mockResolvedValueOnce({ data: [{ product_id: productA, sku: 'A', name: 'A', unit: 'box', quantity: 2, authorized_price: 10, currency: 'YER' }], error: null });
    const result = await setCartItems([{ productId: ` ${productA} `, quantity: 2 }, { productId: productB, quantity: 3 }]);
    expect(rpc).toHaveBeenCalledWith('set_cart_items', { p_items: [{ product_id: productA, quantity: 2 }, { product_id: productB, quantity: 3 }] });
    expect(result[0].product_id).toBe(productA);
  });
});
