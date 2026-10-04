import { describe, expect, it } from 'vitest';
import { MAX_IDEMPOTENCY_KEY_LENGTH, MAX_ORDER_LINES, MAX_ORDER_QUANTITY_PER_LINE, OrderValidationError, calculateClientPreviewTotal, validateOrderDraft } from './order';

const product = (id: string, quantity = 10) => [id, quantity] as const;

function draft(lines: Array<{ productId: string; quantity: number }>) {
  return { idempotencyKey: '0123456789abcdef', lines };
}

describe('validateOrderDraft', () => {
  it('accepts a bounded multi-line order with sufficient stock', () => {
    const [first, second] = [product('product-1', 5), product('product-2', 8)];
    validateOrderDraft(draft([{ productId: first[0], quantity: first[1] }, { productId: second[0], quantity: second[1] }]), new Map([first, second]));
  });
  it('rejects duplicate product lines', () => expect(() => validateOrderDraft(draft([{ productId: 'product-1', quantity: 1 }, { productId: 'product-1', quantity: 2 }]), new Map([product('product-1')]))).toThrow(OrderValidationError));
  it('rejects duplicate product lines after whitespace normalization', () => expect(() => validateOrderDraft(draft([{ productId: ' product-1 ', quantity: 1 }, { productId: 'product-1', quantity: 2 }]), new Map([product('product-1')]))).toThrow(/duplicate/));
  it('accepts a whitespace-normalized product identifier when inventory is keyed by the normalized value', () => validateOrderDraft(draft([{ productId: '  product-1  ', quantity: 1 }]), new Map([product('product-1')])));
  it('does not require client-supplied customer identity', () => { const order = draft([{ productId: 'product-1', quantity: 1 }]); expect(order).not.toHaveProperty('customerId'); validateOrderDraft(order, new Map([product('product-1')])); });
  it('rejects blank product and idempotency fields at the client boundary', () => { expect(() => validateOrderDraft(draft([{ productId: '   ', quantity: 1 }]), new Map([product('product-1')]))).toThrow(/productId/); expect(() => validateOrderDraft({ ...draft([{ productId: 'product-1', quantity: 1 }]), idempotencyKey: '                ' }, new Map([product('product-1')]))).toThrow(/idempotencyKey/); });
  it('rejects a non-array line collection', () => expect(() => validateOrderDraft({ ...draft([{ productId: 'product-1', quantity: 1 }]), lines: null as never }, new Map([product('product-1')]))).toThrow(/at least one line/));
  it('rejects an empty order', () => expect(() => validateOrderDraft(draft([]), new Map())).toThrow(/at least one line/));
  it('rejects an idempotency key above the boundary limit', () => expect(() => validateOrderDraft({ ...draft([{ productId: 'product-1', quantity: 1 }]), idempotencyKey: 'x'.repeat(MAX_IDEMPOTENCY_KEY_LENGTH + 1) }, new Map([product('product-1')]))).toThrow(/cannot exceed/));
  it('rejects quantities above the domain limit', () => expect(() => validateOrderDraft(draft([{ productId: 'product-1', quantity: MAX_ORDER_QUANTITY_PER_LINE + 1 }]), new Map([product('product-1', MAX_ORDER_QUANTITY_PER_LINE + 1)]))).toThrow(/cannot exceed/));
  it('rejects zero and negative quantities', () => { expect(() => validateOrderDraft(draft([{ productId: 'product-1', quantity: 0 }]), new Map([product('product-1')]))).toThrow(/positive safe integer/); expect(() => validateOrderDraft(draft([{ productId: 'product-1', quantity: -1 }]), new Map([product('product-1')]))).toThrow(/positive safe integer/); });
  it('rejects fractional quantities', () => expect(() => validateOrderDraft(draft([{ productId: 'product-1', quantity: 1.5 }]), new Map([product('product-1')]))).toThrow(/safe integer/));
  it('rejects unsafe integer quantities', () => expect(() => validateOrderDraft(draft([{ productId: 'product-1', quantity: Number.MAX_SAFE_INTEGER + 1 }]), new Map([product('product-1', Number.MAX_SAFE_INTEGER)]))).toThrow(/safe integer/));
  it('rejects more than the maximum number of lines', () => { const lines = Array.from({ length: MAX_ORDER_LINES + 1 }, (_, index) => ({ productId: `product-${index}`, quantity: 1 })); const inventory = new Map(lines.map((line) => [line.productId, 1] as const)); expect(() => validateOrderDraft(draft(lines), inventory)).toThrow(/more than/); });
  it('rejects a quantity greater than available stock', () => expect(() => validateOrderDraft(draft([{ productId: 'product-1', quantity: 11 }]), new Map([product('product-1', 10)]))).toThrow(/insufficient stock/));
  it('rejects invalid negative or unsafe inventory quantities', () => { expect(() => validateOrderDraft(draft([{ productId: 'product-1', quantity: 1 }]), new Map([product('product-1', -1)]))).toThrow(/invalid inventory/); expect(() => validateOrderDraft(draft([{ productId: 'product-1', quantity: 1 }]), new Map([product('product-1', Number.NaN)]))).toThrow(/invalid inventory/); });
  it('rejects non-integer and non-finite inventory quantities', () => { expect(() => validateOrderDraft(draft([{ productId: 'product-1', quantity: 1 }]), new Map([product('product-1', 1.5)]))).toThrow(/invalid inventory/); expect(() => validateOrderDraft(draft([{ productId: 'product-1', quantity: 1 }]), new Map([product('product-1', Number.POSITIVE_INFINITY)]))).toThrow(/invalid inventory/); });
  it('rejects a non-object draft at the runtime boundary', () => expect(() => validateOrderDraft(null as never, new Map())).toThrow(/draft is required/));
  it('rejects a missing or non-string idempotency key', () => expect(() => validateOrderDraft({ lines: [{ productId: 'product-1', quantity: 1 }] } as never, new Map([product('product-1')]))).toThrow(/idempotencyKey/));
  it('rejects a non-object order line before reading its fields', () => expect(() => validateOrderDraft({ ...draft([{ productId: 'product-1', quantity: 1 }]), lines: [null] } as never, new Map([product('product-1')]))).toThrow(/order line/));
  it('rejects a non-string product identifier at runtime', () => expect(() => validateOrderDraft({ ...draft([{ productId: 'product-1', quantity: 1 }]), lines: [{ productId: 123, quantity: 1 }] } as never, new Map([product('product-1')]))).toThrow(/productId/));
  it('rejects an invalid inventory container at the runtime boundary', () => expect(() => validateOrderDraft(draft([{ productId: 'product-1', quantity: 1 }]), null as never)).toThrow(/inventory map/));
});

describe('calculateClientPreviewTotal', () => {
  const productValue = { id: '1', sku: '1', name: 'A', unit: 'قطعة', category: 'أ', availableQuantity: 10, status: 'active' as const };
  it('keeps valid finite preview values', () => expect(calculateClientPreviewTotal([{ product: productValue, quantity: 2, unitPrice: 5 }, { product: { ...productValue, id: '2' }, quantity: 3, unitPrice: 2 }])).toBe(16));
  it('ignores non-finite, negative, or unsafe client-preview values', () => expect(calculateClientPreviewTotal([{ product: productValue, quantity: 2, unitPrice: Number.POSITIVE_INFINITY }, { product: productValue, quantity: 2, unitPrice: -5 }, { product: productValue, quantity: Number.MAX_SAFE_INTEGER + 1, unitPrice: 5 }, { product: productValue, quantity: 1, unitPrice: 4 }])).toBe(4));
  it('ignores non-finite quantity and price values without poisoning the preview', () => expect(calculateClientPreviewTotal([{ product: productValue, quantity: Number.NaN, unitPrice: 5 }, { product: productValue, quantity: 2, unitPrice: Number.NaN }, { product: productValue, quantity: 1, unitPrice: 3 }])).toBe(3));
  it('does not return Infinity when a line multiplication overflows', () => expect(calculateClientPreviewTotal([{ product: productValue, quantity: Number.MAX_SAFE_INTEGER, unitPrice: Number.MAX_SAFE_INTEGER }, { product: productValue, quantity: 2, unitPrice: 3 }])).toBe(6));
  it('does not accept negative quantities in a preview', () => expect(calculateClientPreviewTotal([{ product: productValue, quantity: -1, unitPrice: 100 }])).toBe(0));
  it('returns zero for a non-array runtime input', () => expect(calculateClientPreviewTotal(null as never)).toBe(0));
  it('skips malformed runtime line objects', () => expect(calculateClientPreviewTotal([null as never, { product: productValue, quantity: 1, unitPrice: 4 }])).toBe(4));
  it('keeps the accumulated total finite when addition itself overflows', () => expect(calculateClientPreviewTotal([{ product: productValue, quantity: 1, unitPrice: Number.MAX_VALUE }, { product: productValue, quantity: 1, unitPrice: Number.MAX_VALUE }, { product: productValue, quantity: 1, unitPrice: 1 }])).toBe(1));
  it('accepts zero-quantity preview lines without changing the total', () => expect(calculateClientPreviewTotal([{ product: productValue, quantity: 0, unitPrice: 999 }, { product: productValue, quantity: 2, unitPrice: 3 }])).toBe(6));
  it('ignores negative prices without reducing a valid accumulated total', () => expect(calculateClientPreviewTotal([{ product: productValue, quantity: 2, unitPrice: 5 }, { product: productValue, quantity: 2, unitPrice: -10 }])).toBe(10));
});
