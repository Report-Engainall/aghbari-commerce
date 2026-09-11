import { describe, expect, it } from 'vitest';
import { calculateClientPreviewTotal, validateOrderDraft } from './order';

const productValue = { id: '1', sku: '1', name: 'A', unit: 'قطعة', category: 'أ', availableQuantity: 10, status: 'active' as const };
const PRODUCT_A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

function draft(lines: Array<{ productId: string; quantity: number }>, idempotencyKey = 'order-test-key-001'): any { return { idempotencyKey, lines }; }

describe('validateOrderDraft', () => {
  it('accepts a bounded multi-line order with sufficient stock', () => expect(() => validateOrderDraft(draft([{ productId: PRODUCT_A, quantity: 2 }]), new Map([[PRODUCT_A, 3]]))).not.toThrow());
  it('rejects duplicate product lines', () => expect(() => validateOrderDraft(draft([{ productId: PRODUCT_A, quantity: 1 }, { productId: PRODUCT_A, quantity: 2 }]), new Map([[PRODUCT_A, 3]]))).toThrow(/duplicate/));
  it('rejects duplicate product lines after whitespace normalization', () => expect(() => validateOrderDraft(draft([{ productId: ` ${PRODUCT_A} `, quantity: 1 }, { productId: PRODUCT_A, quantity: 1 }]), new Map([[PRODUCT_A, 3]]))).toThrow(/duplicate/));
  it('accepts a whitespace-normalized product identifier when inventory is keyed by the normalized value', () => expect(() => validateOrderDraft(draft([{ productId: ` ${PRODUCT_A} `, quantity: 1 }]), new Map([[PRODUCT_A, 3]]))).not.toThrow());
  it('does not require client-supplied customer identity', () => expect(() => validateOrderDraft(draft([{ productId: PRODUCT_A, quantity: 1 }]), new Map([[PRODUCT_A, 3]]))).not.toThrow());
  it('rejects blank product and idempotency fields at the client boundary', () => {
    expect(() => validateOrderDraft(draft([{ productId: ' ', quantity: 1 }]), new Map([[' ', 3]]))).toThrow(/productId/);
    expect(() => validateOrderDraft(draft([{ productId: PRODUCT_A, quantity: 1 }], ' '), new Map([[PRODUCT_A, 3]]))).toThrow(/idempotencyKey/);
  });
  it('rejects a non-array line collection', () => expect(() => validateOrderDraft({ idempotencyKey: 'order-test-key-001', lines: null } as any, new Map())).toThrow(/order must/));
  it('rejects an empty order', () => expect(() => validateOrderDraft(draft([]), new Map())).toThrow(/at least one line/));
  it('rejects an idempotency key above the boundary limit', () => expect(() => validateOrderDraft(draft([{ productId: PRODUCT_A, quantity: 1 }], 'x'.repeat(129)), new Map([[PRODUCT_A, 3]]))).toThrow(/128/));
  it('rejects quantities above the domain limit', () => expect(() => validateOrderDraft(draft([{ productId: PRODUCT_A, quantity: 10001 }]), new Map([[PRODUCT_A, 10001]]))).toThrow(/10000/));
  it('rejects zero and negative quantities', () => { expect(() => validateOrderDraft(draft([{ productId: PRODUCT_A, quantity: 0 }]), new Map([[PRODUCT_A, 3]]))).toThrow(/positive/); expect(() => validateOrderDraft(draft([{ productId: PRODUCT_A, quantity: -1 }]), new Map([[PRODUCT_A, 3]]))).toThrow(/positive/); });
  it('rejects fractional quantities', () => expect(() => validateOrderDraft(draft([{ productId: PRODUCT_A, quantity: 1.5 }]), new Map([[PRODUCT_A, 3]]))).toThrow(/positive safe integer/));
  it('rejects unsafe integer quantities', () => expect(() => validateOrderDraft(draft([{ productId: PRODUCT_A, quantity: Number.MAX_SAFE_INTEGER + 1 }]), new Map([[PRODUCT_A, Number.MAX_SAFE_INTEGER + 1]]))).toThrow(/positive safe integer/));
  it('rejects more than the maximum number of lines', () => expect(() => validateOrderDraft(draft(Array.from({ length: 101 }, (_, i) => ({ productId: `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`, quantity: 1 }))), new Map(Array.from({ length: 101 }, (_, i) => [`00000000-0000-4000-8000-${String(i).padStart(12, '0')}`, 2] as [string, number])))).toThrow(/100/));
  it('rejects a quantity greater than available stock', () => expect(() => validateOrderDraft(draft([{ productId: PRODUCT_A, quantity: 4 }]), new Map([[PRODUCT_A, 3]]))).toThrow(/insufficient stock/));
  it('rejects invalid negative or unsafe inventory quantities', () => { expect(() => validateOrderDraft(draft([{ productId: PRODUCT_A, quantity: 1 }]), new Map([[PRODUCT_A, -1]]))).toThrow(/invalid inventory/); expect(() => validateOrderDraft(draft([{ productId: PRODUCT_A, quantity: 1 }]), new Map([[PRODUCT_A, Number.MAX_SAFE_INTEGER + 1]]))).toThrow(/invalid inventory/); });
  it('rejects non-integer and non-finite inventory quantities', () => { expect(() => validateOrderDraft(draft([{ productId: PRODUCT_A, quantity: 1 }]), new Map([[PRODUCT_A, 1.5]]))).toThrow(/invalid inventory/); expect(() => validateOrderDraft(draft([{ productId: PRODUCT_A, quantity: 1 }]), new Map([[PRODUCT_A, Number.NaN]]))).toThrow(/invalid inventory/); });
  it('rejects a non-object draft at the runtime boundary', () => expect(() => validateOrderDraft(null as any, new Map())).toThrow(/draft/));
  it('rejects a missing or non-string idempotency key', () => { expect(() => validateOrderDraft({ lines: [{ productId: PRODUCT_A, quantity: 1 }] } as any, new Map([[PRODUCT_A, 2]]))).toThrow(/idempotencyKey/); expect(() => validateOrderDraft({ idempotencyKey: 123, lines: [{ productId: PRODUCT_A, quantity: 1 }] } as any, new Map([[PRODUCT_A, 2]]))).toThrow(/idempotencyKey/); });
  it('rejects a non-object order line before reading its fields', () => expect(() => validateOrderDraft(draft([null as any]), new Map([[PRODUCT_A, 2]]))).toThrow(/order line/));
  it('rejects a non-string product identifier at runtime', () => expect(() => validateOrderDraft(draft([{ productId: 123 as any, quantity: 1 }]), new Map([[PRODUCT_A, 2]]))).toThrow(/productId/));
  it('rejects an invalid inventory container at the runtime boundary', () => expect(() => validateOrderDraft(draft([{ productId: 'product-1', quantity: 1 }]), null as never)).toThrow(/inventory map/));
});

describe('calculateClientPreviewTotal', () => {
  it('keeps valid finite preview values', () => expect(calculateClientPreviewTotal([{ product: productValue, quantity: 2, unitPrice: 5 }, { product: { ...productValue, id: '2' }, quantity: 3, unitPrice: 2 }])).toBe(16));
  it('ignores non-finite, negative, or unsafe client-preview values', () => expect(calculateClientPreviewTotal([{ product: productValue, quantity: 2, unitPrice: Number.POSITIVE_INFINITY }, { product: productValue, quantity: 2, unitPrice: -5 }, { product: productValue, quantity: Number.MAX_SAFE_INTEGER + 1, unitPrice: 5 }, { product: productValue, quantity: 1, unitPrice: 4 }])).toBe(4));
  it('ignores non-finite quantity and price values without poisoning the preview', () => expect(calculateClientPreviewTotal([{ product: productValue, quantity: Number.NaN, unitPrice: 5 }, { product: productValue, quantity: 2, unitPrice: Number.NaN }, { product: productValue, quantity: 1, unitPrice: 3 }])).toBe(3));
  it('does not return Infinity when a line multiplication overflows', () => expect(calculateClientPreviewTotal([{ product: productValue, quantity: Number.MAX_SAFE_INTEGER, unitPrice: Number.MAX_SAFE_INTEGER }, { product: productValue, quantity: 2, unitPrice: 3 }])).toBe(6));
  it('does not accept negative quantities in a preview', () => expect(calculateClientPreviewTotal([{ product: productValue, quantity: -1, unitPrice: 100 }])).toBe(0));
  it('returns zero for a non-array runtime input', () => expect(calculateClientPreviewTotal(null as never)).toBe(0));
  it('skips malformed runtime line objects', () => expect(calculateClientPreviewTotal([null as never, { product: productValue, quantity: 1, unitPrice: 4 }])).toBe(4));
  it('keeps the accumulated total finite by ignoring unsafe preview line totals', () => expect(calculateClientPreviewTotal([{ product: productValue, quantity: 1, unitPrice: Number.MAX_VALUE }, { product: productValue, quantity: 1, unitPrice: Number.MAX_VALUE }, { product: productValue, quantity: 1, unitPrice: 1 }])).toBe(1));
  it('accepts zero-quantity preview lines without changing the total', () => expect(calculateClientPreviewTotal([{ product: productValue, quantity: 0, unitPrice: 999 }, { product: productValue, quantity: 2, unitPrice: 3 }])).toBe(6));
  it('ignores negative prices without reducing a valid accumulated total', () => expect(calculateClientPreviewTotal([{ product: productValue, quantity: 2, unitPrice: 5 }, { product: productValue, quantity: 2, unitPrice: -10 }])).toBe(10));
});
