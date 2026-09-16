import { beforeEach, describe, expect, it, vi } from 'vitest';
import { transitionOrder } from './services/staffOrders';

const { requireSupabaseMock } = vi.hoisted(() => ({ requireSupabaseMock: vi.fn() }));

vi.mock('./lib/supabase', () => ({ requireSupabase: requireSupabaseMock }));

describe('staff order transitions', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('reloads the enriched order after transition instead of trusting the raw RPC row', async () => {
    const order = {
      id: '11111111-1111-4111-8111-111111111111',
      order_number: 42,
      customer_id: '22222222-2222-4222-8222-222222222222',
      warehouse_id: '33333333-3333-4333-8333-333333333333',
      status: 'confirmed',
      total: 1250,
      currency: 'YER',
      created_at: '2026-09-10T06:00:00.000Z',
      updated_at: '2026-09-10T06:05:00.000Z',
      customers: { name: 'تاجر اختبار' },
    };

    const from = vi.fn(() => ({
      select: vi.fn(() => ({
        eq: vi.fn(() => ({
          maybeSingle: vi.fn().mockResolvedValue({ data: order, error: null }),
        })),
      })),
    }));

    requireSupabaseMock.mockReturnValue({
      rpc: vi.fn().mockResolvedValue({
        data: { id: order.id, status: order.status },
        error: null,
      }),
      from,
    });

    await expect(transitionOrder(order.id, 'confirmed')).resolves.toMatchObject({
      id: order.id,
      order_number: 42,
      customer_name: 'تاجر اختبار',
      status: 'confirmed',
      total: 1250,
      currency: 'YER',
    });

    expect(from).toHaveBeenCalledWith('orders');
  });

  it('fails closed when the transition RPC does not return an order id', async () => {
    requireSupabaseMock.mockReturnValue({
      rpc: vi.fn().mockResolvedValue({ data: null, error: null }),
    });

    await expect(transitionOrder('11111111-1111-4111-8111-111111111111', 'confirmed')).rejects.toThrow('لم يتم إرجاع معرّف الطلب');
  });
});
