import { describe, expect, it, vi } from 'vitest';

const from = vi.fn();
vi.mock('../lib/supabase', () => ({ requireSupabase: () => ({ from }) }));

import { getCustomerOrderDetail } from './customerOrderDetails';

describe('getCustomerOrderDetail', () => {
  it('rejects malformed identifiers before any database query', async () => {
    await expect(getCustomerOrderDetail('not-a-uuid')).rejects.toThrow('معرّف الطلب غير صالح');
    expect(from).not.toHaveBeenCalled();
  });

  it('does not treat an arbitrary customer id as an authorization bypass', async () => {
    await expect(getCustomerOrderDetail('11111111-1111-4111-8111-111111111111')).rejects.toThrow();
    expect(from).toHaveBeenCalledWith('orders');
  });
});
