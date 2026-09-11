import { describe, expect, it } from 'vitest';
import { createOrderTemplate } from './orderTemplates';

describe('order template persistence contract', () => {
  it('exports database-backed template operations', async () => {
    expect(typeof createOrderTemplate).toBe('function');
    const module = await import('./orderTemplates');
    expect(typeof module.listOrderTemplates).toBe('function');
    expect(typeof module.deleteOrderTemplate).toBe('function');
  });

  it('rejects invalid template names and empty lines before DB access', async () => {
    await expect(createOrderTemplate({ customerId: '00000000-0000-4000-8000-000000000001', name: '   ', lines: [] })).rejects.toThrow();
    await expect(createOrderTemplate({ customerId: '00000000-0000-4000-8000-000000000001', name: 'x'.repeat(121), lines: [{ productId: '00000000-0000-4000-8000-000000000002', sku: 'SKU', name: 'صنف', unit: 'قطعة', quantity: 1 }] })).rejects.toThrow();
    await expect(createOrderTemplate({ customerId: '00000000-0000-4000-8000-000000000001', name: 'قائمة', lines: [] })).rejects.toThrow();
  });
});
