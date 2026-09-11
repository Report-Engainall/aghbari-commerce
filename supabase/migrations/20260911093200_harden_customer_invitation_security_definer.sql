-- Day 1 follow-up: harden the customer invitation SECURITY DEFINER functions without mutating history.
alter function public.create_customer_invitation(uuid,text,integer) set search_path = '';
alter function public.revoke_customer_invitation(uuid) set search_path = '';
alter function public.accept_customer_invitation(text) set search_path = '';
