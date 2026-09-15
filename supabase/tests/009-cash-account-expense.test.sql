begin;

create extension if not exists pgtap with schema extensions;
select plan(4);

insert into auth.users(id,email) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','cash-admin@test.local');
insert into public.organizations(id,name) values ('78787878-7878-4787-8787-787878787878','Cash Tenant');
insert into public.branches(id,organization_id,name) values ('78787878-7878-4787-8787-787878787879','78787878-7878-4787-8787-787878787878','Main');
insert into public.profiles(id,organization_id,role) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','78787878-7878-4787-8787-787878787878','admin');
set local role authenticated;
set local request.jwt.claim.sub='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

select is((select name from public.create_cash_account('78787878-7878-4787-8787-787878787879','Main Cash','YER',100)),'Main Cash','Admin can provision a cash account');
select * from public.record_expense('78787878-7878-4787-8787-787878787879',(select id from public.cash_accounts where name='Main Cash'),'Transport',25,'YER','Delivery');
select is((select current_balance from public.get_cash_account_balances() where name='Main Cash'),75::numeric,'Posted expense reduces the operational cash balance');
select throws_ok(
  $$select public.record_expense('78787878-7878-4787-8787-787878787879',(select id from public.cash_accounts where name='Main Cash'),'Overdraw',76,'YER','Should fail')$$,
  '22003','expense exceeds available cash balance','Expense cannot overdraw the operational cash account'
);

select is(
  (select count(*) from public.outbox_events where event_type='expense.posted'),
  1::bigint,
  'Posted expense emits one durable outbox event'
);

select * from finish();
rollback;
