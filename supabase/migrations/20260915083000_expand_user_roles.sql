begin;

alter type public.user_role add value if not exists 'employee';
alter type public.user_role add value if not exists 'finance';
alter type public.user_role add value if not exists 'customer';

commit;
