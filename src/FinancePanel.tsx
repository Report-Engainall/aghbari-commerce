import { useCallback, useEffect, useState } from 'react';
import { supabase } from './lib/supabase';
import { createCashAccount, createInvoiceFromOrder, getCashBalances, getInvoices, recordExpense, recordPayment, type CashBalance, type OperationalInvoice } from './services/finance';

type UserRole = 'owner' | 'admin' | 'sales' | 'warehouse' | 'viewer';
type PaymentMethod = 'cash' | 'bank_transfer' | 'card' | 'other';
interface Order { id: string; order_number: number; customer_name: string; status: string; total: number; currency: string; }
interface Branch { id: string; name: string; }
interface OrderRow { id: string; order_number: number; status: string; total: number; currency: string; customers: { name: string } | null; }
const methodLabels: Record<PaymentMethod,string> = { cash:'نقدي', bank_transfer:'تحويل بنكي', card:'بطاقة', other:'أخرى' };

export default function FinancePanel({ role }: { role: UserRole }) {
  const canInvoice = ['owner','admin','sales'].includes(role);
  const canExpense = ['owner','admin'].includes(role);
  const canAccount = ['owner','admin'].includes(role);
  const [orders,setOrders]=useState<Order[]>([]); const [invoices,setInvoices]=useState<OperationalInvoice[]>([]); const [cash,setCash]=useState<CashBalance[]>([]); const [branches,setBranches]=useState<Branch[]>([]);
  const [invoiceId,setInvoiceId]=useState(''); const [amount,setAmount]=useState(''); const [method,setMethod]=useState<PaymentMethod>('cash'); const [cashAccountId,setCashAccountId]=useState(''); const [reference,setReference]=useState(''); const [paymentKey,setPaymentKey]=useState('');
  const [branchId,setBranchId]=useState(''); const [expenseAccountId,setExpenseAccountId]=useState(''); const [expenseCategory,setExpenseCategory]=useState('تشغيل'); const [expenseAmount,setExpenseAmount]=useState(''); const [expenseDescription,setExpenseDescription]=useState('');
  const [accountName,setAccountName]=useState(''); const [accountCurrency,setAccountCurrency]=useState('YER'); const [openingBalance,setOpeningBalance]=useState('0');
  const [busy,setBusy]=useState(false); const [message,setMessage]=useState<string|null>(null); const [error,setError]=useState<string|null>(null);

  const reload=useCallback(async()=>{
    if(!supabase || (!canInvoice && !canExpense && !canAccount)) return;
    const [{data: orderRows,error:orderError},{data:branchRows,error:branchError},invoiceRows,cashRows]=await Promise.all([
      supabase.from('orders').select('id,order_number,status,total,currency,customers!inner(name)').in('status',['ready','completed']).order('created_at',{ascending:false}).limit(100),
      supabase.from('branches').select('id,name').eq('is_active',true).order('created_at'),getInvoices(100),getCashBalances()
    ]);
    if(orderError) throw orderError;if(branchError) throw branchError;
    const typedOrders=(orderRows??[]) as unknown as OrderRow[];
    setOrders(typedOrders.map(o=>({id:o.id,order_number:o.order_number,customer_name:o.customers?.name??'عميل',status:o.status,total:Number(o.total),currency:o.currency})));
    setBranches((branchRows??[]) as Branch[]);setInvoices(invoiceRows);setCash(cashRows);
    if(!invoiceId&&invoiceRows[0])setInvoiceId(invoiceRows[0].id);if(!cashAccountId&&cashRows[0])setCashAccountId(cashRows[0].id);if(!expenseAccountId&&cashRows[0])setExpenseAccountId(cashRows[0].id);if(!branchId&&branchRows?.[0])setBranchId(branchRows[0].id);
  },[branchId,canAccount,canExpense,canInvoice,cashAccountId,expenseAccountId,invoiceId]);
  useEffect(()=>{void reload().catch(e=>setError(e instanceof Error?e.message:'تعذر تحميل المالية التشغيلية.'));},[reload]);
  async function run(action:()=>Promise<unknown>,success:string){setBusy(true);setError(null);setMessage(null);try{await action();setMessage(success);await reload();}catch(e){setError(e instanceof Error?e.message:'تعذر تنفيذ العملية.');}finally{setBusy(false);}}
  if(!canInvoice&&!canExpense&&!canAccount)return null;

  return <div className="cart-panel" id="finance">
    <div className="section-heading"><div><span className="eyebrow">المالية التشغيلية</span><h2>الفواتير والتحصيل والمصروفات</h2></div><span>{cash.length} حسابات نقدية</span></div>
    <div className="admin-grid">
      {canAccount&&<form className="admin-card" onSubmit={e=>{e.preventDefault();void run(()=>createCashAccount(branchId,accountName.trim(),accountCurrency.trim(),Number(openingBalance)),'تم إنشاء حساب النقدية وتسجيل أثر العملية.').then(()=>{setAccountName('');setOpeningBalance('0');});}}><h3>حساب نقدية جديد</h3><select aria-label="فرع الحساب" value={branchId} onChange={e=>setBranchId(e.target.value)} required><option value="">اختر الفرع</option>{branches.map(b=><option key={b.id} value={b.id}>{b.name}</option>)}</select><input aria-label="اسم حساب النقدية" value={accountName} onChange={e=>setAccountName(e.target.value)} placeholder="اسم الحساب" required /><input aria-label="عملة الحساب" value={accountCurrency} onChange={e=>setAccountCurrency(e.target.value.toUpperCase())} maxLength={3} required /><input aria-label="الرصيد الافتتاحي" type="number" min="0" step="0.01" value={openingBalance} onChange={e=>setOpeningBalance(e.target.value)} /><button disabled={busy}>إنشاء الحساب</button></form>}
      {canInvoice&&<div className="admin-card"><h3>إنشاء فاتورة</h3>{!orders.length?<small>لا توجد طلبات جاهزة للفوترة.</small>:<div className="cart-lines">{orders.slice(0,10).map(order=><article className="cart-line" key={order.id}><div><strong>طلب #{order.order_number}</strong><small>{order.customer_name}</small></div><div><strong>{order.total} {order.currency}</strong><small>{order.status}</small></div><button disabled={busy||invoices.some(i=>i.order_id===order.id)} onClick={()=>void run(()=>createInvoiceFromOrder(order.id),'تم إنشاء الفاتورة وربطها بالطلب.')}>{invoices.some(i=>i.order_id===order.id)?'مفوتر':'إنشاء فاتورة'}</button></article>)}</div>}</div>}
      {canInvoice&&<form className="admin-card" onSubmit={e=>{e.preventDefault();if(!invoiceId||!amount)return;const key=paymentKey.trim()||crypto.randomUUID();setPaymentKey(key);void run(()=>recordPayment(invoiceId,Number(amount),method,method==='cash'?cashAccountId:null,reference,key),'تم تسجيل التحصيل وتحديث حالة الفاتورة.').then(()=>setPaymentKey(''));}}><h3>تسجيل تحصيل</h3><select aria-label="الفاتورة" value={invoiceId} onChange={e=>{setInvoiceId(e.target.value);setPaymentKey('');}} required><option value="">اختر فاتورة</option>{invoices.filter(i=>i.status!=='paid'&&i.status!=='void').map(i=><option key={i.id} value={i.id}>فاتورة #{i.invoice_number} · {i.total} {i.currency}</option>)}</select><input aria-label="مبلغ التحصيل" type="number" min="0.01" step="0.01" value={amount} onChange={e=>setAmount(e.target.value)} placeholder="مبلغ التحصيل" required /><select aria-label="طريقة الدفع" value={method} onChange={e=>{setMethod(e.target.value as PaymentMethod);setPaymentKey('');}}>{(Object.keys(methodLabels) as PaymentMethod[]).map(m=><option key={m} value={m}>{methodLabels[m]}</option>)}</select>{method==='cash'&&<select aria-label="الحساب النقدي" value={cashAccountId} onChange={e=>{setCashAccountId(e.target.value);setPaymentKey('');}} required><option value="">حساب النقدية</option>{cash.map(a=><option key={a.id} value={a.id}>{a.name} · {a.currency}</option>)}</select>}<input aria-label="مرجع التحصيل" value={reference} onChange={e=>setReference(e.target.value)} placeholder="مرجع (اختياري)" /><button disabled={busy||!invoiceId}>تسجيل التحصيل</button></form>}
      {canExpense&&<form className="admin-card" onSubmit={e=>{e.preventDefault();if(!branchId||!expenseAccountId||!expenseAmount)return;void run(()=>recordExpense(branchId,expenseAccountId,expenseCategory,Number(expenseAmount),cash.find(a=>a.id===expenseAccountId)?.currency??'YER',expenseDescription),'تم تسجيل المصروف وتحديث دفتر النقدية.')}}><h3>مصروف تشغيلي</h3><select aria-label="الفرع" value={branchId} onChange={e=>setBranchId(e.target.value)} required><option value="">اختر الفرع</option>{branches.map(b=><option key={b.id} value={b.id}>{b.name}</option>)}</select><select aria-label="حساب المصروف" value={expenseAccountId} onChange={e=>setExpenseAccountId(e.target.value)} required><option value="">حساب النقدية</option>{cash.map(a=><option key={a.id} value={a.id}>{a.name} · {a.currency}</option>)}</select><input aria-label="فئة المصروف" value={expenseCategory} onChange={e=>setExpenseCategory(e.target.value)} placeholder="الفئة" required /><input aria-label="مبلغ المصروف" type="number" min="0.01" step="0.01" value={expenseAmount} onChange={e=>setExpenseAmount(e.target.value)} placeholder="المبلغ" required /><input aria-label="وصف المصروف" value={expenseDescription} onChange={e=>setExpenseDescription(e.target.value)} placeholder="الوصف" /><button disabled={busy}>تسجيل المصروف</button></form>}
      <div className="admin-card"><h3>أرصدة النقدية</h3>{!cash.length?<small>لا توجد حسابات نقدية مهيأة.</small>:<div className="cart-lines">{cash.map(a=><article className="cart-line" key={a.id}><div><strong>{a.name}</strong><small>{a.currency}</small></div><div><strong>{a.current_balance}</strong><small>داخل {a.received} · خارج {a.spent}</small></div></article>)}</div>}</div>
    </div>
    {error&&<div className="error-banner" role="alert">{error}</div>}{message&&<div className="success" role="status">{message}</div>}
  </div>;
}
