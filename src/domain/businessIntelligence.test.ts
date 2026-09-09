import { describe, expect, it } from 'vitest';
import { buildBusinessSignals, buildBusinessSnapshot, buildStatusBreakdown } from './businessIntelligence';
import type { CustomerOrderSummary } from '../services/customerOrders';

type TestOrder = CustomerOrderSummary & { customer_id: string };
const order = (overrides: Partial<TestOrder> = {}): TestOrder => ({
  id: crypto.randomUUID(), order_number: 1, status: 'completed', total: 100, currency: 'YER', created_at: '2026-09-01T00:00:00Z', customer_id: crypto.randomUUID(), ...overrides,
});

describe('business intelligence evidence layer', () => {
  it('calculates safe operational totals', () => {
    const snapshot = buildBusinessSnapshot([order(), order({ total: 50, status: 'pending' })]);
    expect(snapshot.orderCount).toBe(2);
    expect(snapshot.grossValue).toBe(150);
    expect(snapshot.averageOrderValue).toBe(75);
    expect(snapshot.pendingCount).toBe(1);
    expect(snapshot.completionRate).toBe(0.5);
  });

  it('breaks down statuses by count and value', () => {
    const rows = buildStatusBreakdown([order(), order({ status: 'cancelled', total: 250 })]);
    expect(rows[0]).toEqual({ status: 'cancelled', count: 1, value: 250 });
  });

  it('raises deterministic backlog and cancellation signals', () => {
    const rows = Array.from({ length: 10 }, (_, index) => order({
      id: crypto.randomUUID(), order_number: index + 1, status: index < 8 ? 'pending' : 'cancelled', total: 100,
    }));
    const signals = buildBusinessSignals(rows);
    expect(signals.map((signal) => signal.kind)).toEqual(expect.arrayContaining(['pending_backlog', 'cancellation_rate']));
    expect(signals.every((signal) => signal.evidence.orderCount === 10)).toBe(true);
  });

  it('does not invent customer concentration when only one customer exists', () => {
    const customerId = crypto.randomUUID();
    const signals = buildBusinessSignals([order({ customer_id: customerId }), order({ customer_id: customerId })]);
    expect(signals.some((signal) => signal.kind === 'customer_concentration')).toBe(false);
    expect(signals.some((signal) => signal.kind === 'repeat_customer')).toBe(true);
  });
});
