import { requireSupabase } from '../lib/supabase';
import { retryRead } from '../lib/retry';

export interface CategoryOption {
  id: string;
  name: string;
  parent_id: string | null;
}

export async function getCategories(): Promise<CategoryOption[]> {
  const { data, error } = await retryRead(async () => {
    const result = await requireSupabase()
      .from('categories')
      .select('id, name, parent_id')
      .eq('is_active', true)
      .order('name');
    if (result.error) throw result.error;
    return result;
  });
  return (data ?? []) as CategoryOption[];
}
