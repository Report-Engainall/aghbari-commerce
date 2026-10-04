/*
# Auto-create profile on user signup

## Purpose
When a new user registers through the sign-up screen, Supabase Auth creates a row in `auth.users`
but no corresponding row in `public.profiles`. The app's `loadIdentity` function queries `profiles`
to determine the user's role and customer association — without a profile row, it crashes.

## Changes
1. Creates a `handle_new_user` trigger function that:
   - Finds the first (default) organization from `public.organizations`.
   - Inserts a new `profiles` row with `role = 'viewer'` and `customer_id = NULL`.
   - If no organization exists, raises an exception.
2. Attaches the function to `auth.users` via `AFTER INSERT` trigger.
3. All statements are idempotent.

## Security
- SECURITY DEFINER with search_path = public.
- REVOKE EXECUTE from anon and authenticated.
- No RLS changes.

## Notes
1. New user gets role = 'viewer' — can browse catalog, no admin access.
2. customer_id is NULL until an admin links the user to a customer.
3. Trigger fires automatically on auth.users INSERT (signUp).
*/

-- Ensure at least one default organization exists
INSERT INTO public.organizations (id, name)
SELECT gen_random_uuid(), 'الأغبري للتجارة'
WHERE NOT EXISTS (SELECT 1 FROM public.organizations LIMIT 1)
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  default_org_id uuid;
BEGIN
  SELECT id INTO default_org_id FROM public.organizations ORDER BY created_at LIMIT 1;
  IF default_org_id IS NULL THEN
    RAISE EXCEPTION 'لا توجد مؤسسة افتراضية.';
  END IF;
  INSERT INTO public.profiles (id, organization_id, role, customer_id)
  VALUES (NEW.id, default_org_id, 'viewer', NULL)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon, authenticated;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();
