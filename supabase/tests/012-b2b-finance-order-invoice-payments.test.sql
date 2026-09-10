begin;

create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users (id,email)
values ('12121212-1212-4121-8121-121212121212','finance-flow@test.local');
insert into public.companies (id,name,currency)
values ('12121212-1212-4121-8121-121212121213','Finance Flow Test','YER');
insert into public.company_memberships (id,company_id,user_id,role,is_active,is_default)
values ('12121212-1212-4121-8121-121212121214','12121212-1212-4121-8121-121212121213','12121212-1212-4121-8121-121212121212','admin',true,true);
insert into public.branches (id,company_id,name)
values ('12121212-1212-4121-8121-121212121215','12121212-1212-4121-8121-121212121213','Finance Branch');
insert into public.warehouses (id,company_id,branch_id,name)
values ('12121212-1212-4121-8121-121212121219','12121212-1212-4121-8121-121212121213','12121212-1212-4121-8121-121212121215','Finance Warehouse');
insert into public.customers (id,company_id,name,email)
values ('12121212-1212-4121-8121-121212121216','12121212-1212-4121-8121-121212121213','Finance Customer','finance-flow@test.local');
insert into public.orders (id,company_id,customer_id,warehouse_id,order_number,status,total,currency,idempotency_key,created_by)
values ('12121212-1212-4121-8121-121212121217','12121212-1212-4121-8121-121212121213','12121212-1212-4121-8121-121212121216','12121212-1212-4121-8121-121212121219',9121201,'completed',200,'YER','finance-flow-01','12121212-1212-4121-8121-121212121212');
insert into public.cash_accounts(id,company_id,branch_id,name,currency,opening_balance)
values ('12121212-1212-4121-8121-121212121218','12121212-1212-4121-8121-121212121213','12121212-1212-4121-8121-121212121215','Flow Cash','YER',0);

set local role authenticated;
set local request.jwt.claim.sub='12121212-1212-4121-8121-121212121212';

select is((select total from public.create_invoice_from_order('12121212-1212-4121-8121-121212121217')),200::numeric,'Completed order creates an invoice');
select is((select count(*) from public.sales_invoices where order_id='12121212-1212-4121-8121-121212121217'),1::bigint,'Invoice is unique per order');
select is((select total from public.create_invoice_from_order('12121212-1212-4121-8121-121212121217')),200::numeric,'Repeated invoice command is idempotent');
select is((select (public.record_payment((select id from public.sales_invoices where order_id='12121212-1212-4121-8121-121212121217'),50,'cash','12121212-1212-4121-8121-121212121218','RCPT-1')->>'remaining_balance')::numeric),150::numeric,'Partial payment leaves the correct balance');
select is((select status from public.sales_invoices where order_id='12121212-1212-4121-8121-121212121217'),'partially_paid','Partial payment updates status');
select throws_ok($$select public.record_payment((select id from public.sales_invoices where order_id='12121212-1212-4121-8121-121212121217'),151,'cash','12121212-1212-4121-8121-121212121218','OVER')$$,'P0001','payment_exceeds_balance','Overpayment is rejected');
select is((select (public.record_payment((select id from public.sales_invoices where order_id='12121212-1212-4121-8121-121212121217'),150,'cash','12121212-1212-4121-8121-121212121218','RCPT-2')->>'status')),'paid','Final payment marks invoice paid');
select is((select current_balance from public.cash_accounts where id='12121212-1212-4121-8121-121212121218'),200::numeric,'Cash account reflects collections');
select is((select public.get_staff_receivables()),0::numeric,'Paid invoice contributes zero outstanding receivables');
select throws_ok($$select public.record_payment((select id from public.sales_invoices where order_id='12121212-1212-4121-8121-121212121217'),1,'cash','12121212-1212-4121-8121-121212121218','OVER2')$$,'P0001','payment_exceeds_balance','Second overpayment is rejected');

select * from finish();
rollback;
