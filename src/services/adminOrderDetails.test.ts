import { describe, expect, it } from 'vitest';
import { getAdminOrderDetail } from './adminOrderDetails';

describe('adminOrderDetails', () => {
  it('rejects malformed order ids before touching the backend', async () => {
    await expect(getAdminOrderDetail('not-a-uuid')).rejects.toThrow('معرّف الطلب غير صالح.');
  });
});
