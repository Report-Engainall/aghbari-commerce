import type { CartLine, OrderDraft } from './types';

export const MAX_ORDER_LINES = 100;
export const MAX_ORDER_QUANTITY_PER_LINE = 10000;
export const MAX_IDEMPOTENCY_KEY_LENGTH = 128;

export class OrderValidationError extends Error {
  constructor(message: string) { super(message); this.name = 'OrderValidationError'; }
}

export function validateOrderDraft(draft: OrderDraft, inventory: Map<string, number>): void {
  if (!draft || typeof draft !== 'object') throw new OrderValidationError('order draft is required');
  if (!inventory || typeof inventory.get !== 'function') throw new OrderValidationError('inventory map is required');
  if (typeof draft.idempotencyKey !== 'string') throw new OrderValidationError('idempotencyKey is required');
  const idempotencyKey = draft.idempotencyKey.trim();
  if (idempotencyKey.length < 16) throw new OrderValidationError('idempotencyKey must be at least 16 characters');
  if (idempotencyKey.length > MAX_IDEMPOTENCY_KEY_LENGTH) throw new OrderValidationError(`idempotencyKey cannot exceed ${MAX_IDEMPOTENCY_KEY_LENGTH} characters`);
  if (!Array.isArray(draft.lines) || draft.lines.length === 0) throw new OrderValidationError('order must contain at least one line');
  if (draft.lines.length > MAX_ORDER_LINES) throw new OrderValidationError(`order cannot contain more than ${MAX_ORDER_LINES} lines`);
  const seen = new Set<string>();
  for (const line of draft.lines) {
    if (!line || typeof line !== 'object') throw new OrderValidationError('order line is required');
    if (typeof line.productId !== 'string') throw new OrderValidationError('productId is required');
    const productId = line.productId.trim();
    if (!productId) throw new OrderValidationError('productId is required');
    if (seen.has(productId)) throw new OrderValidationError('duplicate product line');
    seen.add(productId);
    if (!Number.isSafeInteger(line.quantity) || line.quantity <= 0) throw new OrderValidationError('quantity must be a positive safe integer');
    if (line.quantity > MAX_ORDER_QUANTITY_PER_LINE) throw new OrderValidationError(`quantity cannot exceed ${MAX_ORDER_QUANTITY_PER_LINE}`);
    const available = inventory.get(productId) ?? 0;
    if (!Number.isSafeInteger(available) || available < 0) throw new OrderValidationError('invalid inventory quantity');
    if (line.quantity > available) throw new OrderValidationError('insufficient stock');
  }
}

export function calculateClientPreviewTotal(lines: CartLine[]): number {
  // Preview only. The canonical order total must be recalculated server-side.
  if (!Array.isArray(lines)) return 0;
  return lines.reduce((sum, line) => {
    if (!line || typeof line !== 'object') return sum;
    if (!Number.isFinite(line.unitPrice) || line.unitPrice < 0 || !Number.isSafeInteger(line.quantity) || line.quantity < 0) return sum;
    const lineTotal = line.unitPrice * line.quantity;
    // A finite floating-point result can still be outside the safe integer range;
    // never let an unsafe preview value poison the displayed total.
    if (!Number.isSafeInteger(lineTotal)) return sum;
    const nextTotal = sum + lineTotal;
    return Number.isSafeInteger(nextTotal) ? nextTotal : sum;
  }, 0);
}
