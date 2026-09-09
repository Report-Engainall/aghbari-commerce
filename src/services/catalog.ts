import { requireSupabase } from '../lib/supabase';
import { retryRead } from '../lib/retry';

const SIGNED_URL_TTL_SECONDS = 300;
const SIGNED_URL_REUSE_MS = 240_000;
const imageUrlCache = new Map<string, { url: string; expiresAt: number }>();

export async function getProductImageUrls(paths: Array<string | null>) {
  const client = requireSupabase();
  const uniquePaths = [...new Set(paths.filter((path): path is string => Boolean(path)))];
  if (!uniquePaths.length) return new Map<string, string>();
  const now = Date.now();
  const result = new Map<string, string>();
  const missing: string[] = [];
  for (const path of uniquePaths) {
    const cached = imageUrlCache.get(path);
    if (cached && cached.expiresAt > now) result.set(path, cached.url); else missing.push(path);
  }
  if (missing.length) {
    const { data } = await retryRead(async () => {
      const response = await client.storage.from('product-media').createSignedUrls(missing, SIGNED_URL_TTL_SECONDS);
      if (response.error) throw response.error;
      return response;
    });
    for (const [index, item] of (data ?? []).entries()) {
      const path = missing[index];
      if (!path || !item.signedUrl) continue;
      imageUrlCache.set(path, { url: item.signedUrl, expiresAt: now + SIGNED_URL_REUSE_MS });
      result.set(path, item.signedUrl);
    }
  }
  return result;
}
