import { beforeEach, describe, expect, it } from 'vitest';
import {
  clearOfflineQueue,
  drainOfflineOperations,
  enqueueOfflineOperation,
  markOfflineOperationAttempt,
  MAX_OFFLINE_ATTEMPTS,
  MAX_OFFLINE_OPERATIONS,
  MAX_OFFLINE_PAYLOAD_BYTES,
  OFFLINE_CART_REMOVE_ITEM,
  OFFLINE_CART_SET_ITEM,
  pendingOfflineOperations
} from './offlineQueue';

const storage = new Map<string, string>();
const USER_A = '11111111-1111-4111-8111-111111111111';
const USER_B = '22222222-2222-4222-8222-222222222222';
const PRODUCT_A = '33333333-3333-4333-8333-333333333333';
const PRODUCT_B = '44444444-4444-4444-8444-444444444444';

Object.defineProperty(globalThis, 'localStorage', {
  configurable: true,
  value: {
    getItem: (key: string) => storage.get(key) ?? null,
    setItem: (key: string, value: string) => { storage.set(key, value); },
    removeItem: (key: string) => { storage.delete(key); },
    clear: () => storage.clear()
  }
});

describe('offline operation queue', () => {
  beforeEach(() => storage.clear());

  it('rejects empty and unsafe operation types', () => {
    expect(() => enqueueOfflineOperation(USER_A, '   ', {})).toThrow('نوع العملية مطلوب');
    expect(() => enqueueOfflineOperation(USER_A, 'order:submit', {})).toThrow('لا يُسمح بتأجيلها');
    enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_A, quantity: 1 });
    expect(pendingOfflineOperations(USER_A)).toHaveLength(1);
  });

  it('requires a valid authenticated user scope', () => {
    expect(() => enqueueOfflineOperation('not-a-user', OFFLINE_CART_SET_ITEM, { productId: PRODUCT_A, quantity: 1 })).toThrow('هوية المستخدم مطلوبة');
  });

  it('tracks attempts without losing operation identity', () => {
    const operation = enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_A, quantity: 1 });
    markOfflineOperationAttempt(operation.operationId, 1_000);
    expect(pendingOfflineOperations(USER_A)[0]).toMatchObject({ operationId: operation.operationId, userId: USER_A, attempts: 1, type: OFFLINE_CART_SET_ITEM });
    expect(Date.parse(pendingOfflineOperations(USER_A)[0].nextAttemptAt!)).toBe(3_000);
  });

  it('uses bounded exponential retry backoff and does not retry early', async () => {
    const operation = enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_A, quantity: 1 });
    markOfflineOperationAttempt(operation.operationId, 10_000);
    const processor = async () => { throw new Error('transient'); };
    const early = await drainOfflineOperations(processor, USER_A, 11_999);
    expect(early).toEqual({ processed: 0, failed: 0 });
    const due = await drainOfflineOperations(processor, USER_A, 12_000);
    expect(due).toEqual({ processed: 0, failed: 1 });
    expect(pendingOfflineOperations(USER_A)[0].attempts).toBe(2);
    expect(Date.parse(pendingOfflineOperations(USER_A)[0].nextAttemptAt!)).toBe(16_000);
  });

  it('marks exhausted operations terminal without blocking following work', async () => {
    const exhausted = enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_A, quantity: 1 });
    const following = enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_B, quantity: 1 });
    for (let index = 0; index < MAX_OFFLINE_ATTEMPTS; index += 1) markOfflineOperationAttempt(exhausted.operationId, 1_000 + index);
    const seen: string[] = [];
    const result = await drainOfflineOperations(async (operation) => { seen.push(operation.operationId); }, USER_A, Date.now() + 1_000_000);
    expect(result).toEqual({ processed: 1, failed: 0 });
    expect(seen).toEqual([following.operationId]);
    expect(pendingOfflineOperations(USER_A)).toHaveLength(1);
    expect(pendingOfflineOperations(USER_A)[0]).toMatchObject({ operationId: exhausted.operationId, attempts: MAX_OFFLINE_ATTEMPTS, terminal: true });
  });

  it('returns no records for an invalid user filter instead of exposing the full queue', () => {
    enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_A, quantity: 1 });
    expect(pendingOfflineOperations('not-a-user')).toHaveLength(0);
  });

  it('does not clear another user scope when the supplied user id is invalid', () => {
    enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_A, quantity: 1 });
    clearOfflineQueue('not-a-user');
    expect(pendingOfflineOperations(USER_A)).toHaveLength(1);
  });

  it('drops legacy or malformed persisted records rather than replaying them', () => {
    storage.set('aghbari.offline.operations.v1', JSON.stringify([
      { operationId: 'not-a-uuid', userId: USER_A, type: OFFLINE_CART_SET_ITEM, createdAt: new Date().toISOString(), attempts: 0, payload: {} },
      { operationId: crypto.randomUUID(), userId: USER_A, type: 'order:submit', createdAt: new Date().toISOString(), attempts: 0, payload: {} },
      { operationId: crypto.randomUUID(), type: OFFLINE_CART_SET_ITEM, createdAt: new Date().toISOString(), attempts: 0, payload: { productId: PRODUCT_A, quantity: 1 } },
      { operationId: crypto.randomUUID(), userId: USER_A, type: OFFLINE_CART_SET_ITEM, createdAt: new Date().toISOString(), attempts: 0, payload: { productId: PRODUCT_A, quantity: 1 } }
    ]));
    expect(pendingOfflineOperations(USER_A)).toHaveLength(1);
    expect(pendingOfflineOperations(USER_A)[0].userId).toBe(USER_A);
  });

  it('keeps each authenticated user isolated in the local queue', () => {
    enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_A, quantity: 1 });
    enqueueOfflineOperation(USER_B, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_B, quantity: 2 });
    expect(pendingOfflineOperations(USER_A)).toHaveLength(1);
    expect(pendingOfflineOperations(USER_B)).toHaveLength(1);
    expect(pendingOfflineOperations(USER_A)[0].userId).toBe(USER_A);
    expect(pendingOfflineOperations(USER_B)[0].userId).toBe(USER_B);
    clearOfflineQueue(USER_A);
    expect(pendingOfflineOperations(USER_A)).toHaveLength(0);
    expect(pendingOfflineOperations(USER_B)).toHaveLength(1);
  });

  it('enforces a payload size ceiling', () => {
    expect(() => enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_A, quantity: 1, blob: 'x'.repeat(MAX_OFFLINE_PAYLOAD_BYTES) })).toThrow(/حجم بيانات/);
  });

  it('enforces a hard queue ceiling', () => {
    for (let index = 0; index < MAX_OFFLINE_OPERATIONS; index += 1) {
      enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_A, quantity: 1 });
    }
    expect(() => enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_A, quantity: 1 })).toThrow('100');
    clearOfflineQueue(USER_A);
    expect(pendingOfflineOperations(USER_A)).toHaveLength(0);
  });

  it('drains only the selected user scope and retains failed operations for recovery', async () => {
    const success = enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_A, quantity: 2 });
    const failed = enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_B, quantity: 3 });
    const otherUser = enqueueOfflineOperation(USER_B, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_A, quantity: 4 });
    const seen: string[] = [];
    const result = await drainOfflineOperations(async (operation) => {
      seen.push(operation.operationId);
      if (operation.operationId === failed.operationId) throw new Error('transient');
    }, USER_A, Date.now());
    expect(result).toEqual({ processed: 1, failed: 1 });
    expect(seen).toEqual([success.operationId, failed.operationId]);
    expect(pendingOfflineOperations(USER_A)).toHaveLength(1);
    expect(pendingOfflineOperations(USER_A)[0].operationId).toBe(failed.operationId);
    expect(pendingOfflineOperations(USER_A)[0].attempts).toBe(1);
    expect(pendingOfflineOperations(USER_B)[0].operationId).toBe(otherUser.operationId);
  });

  it('does not drain while the browser is offline', async () => {
    const operation = enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_A, quantity: 1 });
    Object.defineProperty(globalThis, 'navigator', { configurable: true, value: { onLine: false } });
    const processor = async () => { throw new Error('must not execute'); };
    await expect(drainOfflineOperations(processor, USER_A, Date.now())).resolves.toEqual({ processed: 0, failed: 0 });
    expect(pendingOfflineOperations(USER_A)[0].operationId).toBe(operation.operationId);
    Object.defineProperty(globalThis, 'navigator', { configurable: true, value: { onLine: true } });
  });

  it('removes a successful operation even when the processor mutates the queue', async () => {
    const operation = enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_A, quantity: 1 });
    const added = enqueueOfflineOperation(USER_A, OFFLINE_CART_REMOVE_ITEM, { productId: PRODUCT_B });
    let processorCalls = 0;
    const result = await drainOfflineOperations(async () => {
      if (processorCalls++ === 0) enqueueOfflineOperation(USER_B, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_B, quantity: 1 });
    }, USER_A, Date.now());
    expect(result).toEqual({ processed: 2, failed: 0 });
    expect(pendingOfflineOperations(USER_A)).toHaveLength(0);
    expect(pendingOfflineOperations(USER_B)).toHaveLength(1);
    expect(added.operationId).not.toBe(operation.operationId);
  });

  it('never invokes the processor for terminal operations', async () => {
    const operation = enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_A, quantity: 1 });
    for (let index = 0; index < MAX_OFFLINE_ATTEMPTS; index += 1) markOfflineOperationAttempt(operation.operationId, 5_000 + index);
    let calls = 0;
    const result = await drainOfflineOperations(async () => { calls += 1; }, USER_A, Date.now() + 10_000_000);
    expect(result).toEqual({ processed: 0, failed: 0 });
    expect(calls).toBe(0);
    expect(pendingOfflineOperations(USER_A)[0].terminal).toBe(true);
  });

  it('rejects cyclic payloads instead of persisting an unserializable record', () => {
    const payload: { self?: unknown } = {};
    payload.self = payload;
    expect(() => enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, payload)).toThrow('غير قابلة للحفظ');
    expect(pendingOfflineOperations(USER_A)).toHaveLength(0);
  });

  it('ignores malformed retry timestamps during persisted-record recovery', () => {
    storage.set('aghbari.offline.operations.v1', JSON.stringify([
      { operationId: crypto.randomUUID(), userId: USER_A, type: OFFLINE_CART_SET_ITEM, createdAt: new Date().toISOString(), attempts: 0, nextAttemptAt: 'not-a-date', payload: { productId: PRODUCT_A, quantity: 1 } }
    ]));
    expect(pendingOfflineOperations(USER_A)).toHaveLength(0);
  });

  it('keeps retry delay deterministic through the maximum retry boundary', () => {
    const operation = enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_A, quantity: 1 });
    for (let index = 0; index < MAX_OFFLINE_ATTEMPTS - 1; index += 1) markOfflineOperationAttempt(operation.operationId, 1_000);
    markOfflineOperationAttempt(operation.operationId, 1_000);
    expect(Date.parse(pendingOfflineOperations(USER_A)[0].nextAttemptAt!)).toBe(1_000 + 256_000);
    expect(pendingOfflineOperations(USER_A)[0].attempts).toBe(MAX_OFFLINE_ATTEMPTS);
    expect(pendingOfflineOperations(USER_A)[0].terminal).toBe(true);
  });

  it('normalizes user and operation type whitespace before persistence', () => {
    const operation = enqueueOfflineOperation(`  ${USER_A}  `, ` ${OFFLINE_CART_REMOVE_ITEM} `, { productId: PRODUCT_A });
    expect(operation.userId).toBe(USER_A);
    expect(operation.type).toBe(OFFLINE_CART_REMOVE_ITEM);
    expect(pendingOfflineOperations(` ${USER_A} `)[0]).toMatchObject({ userId: USER_A, type: OFFLINE_CART_REMOVE_ITEM });
  });

  it('does not expose the global queue when an invalid explicit user filter is supplied', () => {
    enqueueOfflineOperation(USER_A, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_A, quantity: 1 });
    enqueueOfflineOperation(USER_B, OFFLINE_CART_SET_ITEM, { productId: PRODUCT_B, quantity: 1 });
    expect(pendingOfflineOperations()).toHaveLength(2);
    expect(pendingOfflineOperations(' ')).toHaveLength(0);
    expect(pendingOfflineOperations('not-a-user')).toHaveLength(0);
  });
});
