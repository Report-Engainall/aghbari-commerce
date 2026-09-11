import { describe, expect, it } from 'vitest';
import { updateCustomer } from './customerMutations';

describe('customer profile mutation contract', () => {
  it('rejects malformed ids and invalid fields before RPC', async () => {
    await expect(updateCustomer('bad-id','عميل','777','wholesale')).rejects.toThrow('معرّف العميل غير صالح');
    await expect(updateCustomer('11111111-1111-4111-8111-111111111111','   ','777','wholesale')).rejects.toThrow('اسم العميل');
    await expect(updateCustomer('11111111-1111-4111-8111-111111111111','عميل','x'.repeat(51),'wholesale')).rejects.toThrow('هاتف');
  });
});
