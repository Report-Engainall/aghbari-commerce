import { useCallback, useEffect, useMemo, useState } from 'react';
import type { CustomerTier } from './domain/types';
import { createCustomer, getCustomers, setCustomerActive, setCustomerTier, updateCustomer, type StaffCustomer } from './services/customers';
import { createCustomerInvitation, getCustomerInvitations, revokeCustomerInvitation, type CustomerInvitation } from './services/customerInvitations';

const tiers: CustomerTier[] = ['retail', 'wholesale', 'distributor'];
const tierLabels: Record<CustomerTier, string> = { retail: 'تجزئة', wholesale: 'جملة', distributor: 'موزع' };
type UserRole = 'owner' | 'admin' | 'sales' | 'warehouse' | 'viewer';
const INVITATION_STATUS_LABELS: Record<CustomerInvitation['status'], string> = { pending: 'بانتظار التفعيل', accepted: 'تم التفعيل', expired: 'منتهية', revoked: 'ملغاة' };
const PAGE_SIZE = 20;

export default function CustomerPanel({ role }: { role: UserRole }) {
  const canCreate = ['owner', 'admin', 'sales'].includes(role);
  const canManage = ['owner', 'admin'].includes(role);
  const [customers, setCustomers] = useState<StaffCustomer[]>([]);
  const [invitations, setInvitations] = useState<CustomerInvitation[]>([]);
  const [name, setName] = useState(''); const [phone, setPhone] = useState('');
  const [tier, setTier] = useState<CustomerTier>('wholesale');
  const [inviteEmail, setInviteEmail] = useState<Record<string, string>>({});
  const [inviteLinks, setInviteLinks] = useState<Record<string, string>>({});
  const [query, setQuery] = useState(''); const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'inactive'>('all');
  const [page, setPage] = useState(1); const [editingId, setEditingId] = useState<string | null>(null); const [editName, setEditName] = useState(''); const [editPhone, setEditPhone] = useState(''); const [editTier, setEditTier] = useState<CustomerTier>('wholesale');
  const [busy, setBusy] = useState(false); const [error, setError] = useState<string | null>(null); const [message, setMessage] = useState<string | null>(null);

  const reload = useCallback(async () => { const [nextCustomers, nextInvitations] = await Promise.all([getCustomers(500), getCustomerInvitations(500)]); setCustomers(nextCustomers); setInvitations(nextInvitations); }, []);
  useEffect(() => { void reload().catch((e) => setError(e instanceof Error ? e.message : 'تعذر تحميل العملاء.')); }, [reload]);

  async function run(action: () => Promise<unknown>, success: string) { setBusy(true); setError(null); setMessage(null); try { await action(); setMessage(success); await reload(); } catch (e) { setError(e instanceof Error ? e.message : 'تعذر تنفيذ العملية.'); } finally { setBusy(false); } }
  async function invite(customer: StaffCustomer) { const email = inviteEmail[customer.id]?.trim() || customer.email?.trim() || ''; if (!email) { setError('أدخل بريد العميل قبل إرسال الدعوة.'); return; } setBusy(true); setError(null); setMessage(null); try { const result = await createCustomerInvitation(customer.id, email, 72); setInviteLinks((current) => ({ ...current, [customer.id]: result.url })); setMessage('تم إنشاء دعوة جديدة.'); await reload(); } catch (e) { setError(e instanceof Error ? e.message : 'تعذر إنشاء دعوة العميل.'); } finally { setBusy(false); } }
  async function copyInvite(customerId: string) { const url = inviteLinks[customerId]; if (!url) return; try { await navigator.clipboard.writeText(url); setMessage('تم نسخ رابط الدعوة.'); } catch { setError('تعذر نسخ الرابط تلقائيًا.'); } }
  function beginEdit(customer: StaffCustomer) { setEditingId(customer.id); setEditName(customer.name); setEditPhone(customer.phone ?? ''); setEditTier(customer.tier); setError(null); setMessage(null); }
  async function saveEdit(customerId: string) { await run(() => updateCustomer(customerId, editName, editPhone, editTier), 'تم تحديث بيانات العميل وتسجيل أثر العملية.'); setEditingId(null); }

  const filteredCustomers = useMemo(() => { const needle = query.trim().toLowerCase(); return customers.filter((customer) => { const matchesQuery = !needle || [customer.name, customer.phone ?? '', customer.email ?? ''].some((value) => value.toLowerCase().includes(needle)); const matchesStatus = statusFilter === 'all' || (statusFilter === 'active' ? customer.is_active : !customer.is_active); return matchesQuery && matchesStatus; }); }, [customers, query, statusFilter]);
  const pageCount = Math.max(1, Math.ceil(filteredCustomers.length / PAGE_SIZE));
  const visibleCustomers = filteredCustomers.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);
  useEffect(() => { if (page > pageCount) setPage(pageCount); }, [page, pageCount]);
  function changeQuery(value: string) { setQuery(value); setPage(1); }
  function changeFilter(value: 'all' | 'active' | 'inactive') { setStatusFilter(value); setPage(1); }

  if (!canCreate && !canManage) return null;
  return <div className="cart-panel" id="customers-admin">
    <div className="section-heading"><div><span className="eyebrow">العملاء</span><h2>دورة العميل</h2></div><span>{filteredCustomers.length} من {customers.length} عملاء</span></div>
    <div className="admin-grid">
      {canCreate && <form className="admin-card" onSubmit={(e) => { e.preventDefault(); void run(async () => { await createCustomer(name, phone, tier); setName(''); setPhone(''); }, 'تم إنشاء العميل وتسجيل أثر العملية.'); }}>
        <h3>عميل جديد</h3><input aria-label="اسم العميل" placeholder="اسم العميل" value={name} onChange={(e) => setName(e.target.value)} required maxLength={200} />
        <input aria-label="هاتف العميل" placeholder="رقم الهاتف" value={phone} onChange={(e) => setPhone(e.target.value)} maxLength={50} />
        <select aria-label="فئة العميل" value={tier} onChange={(e) => setTier(e.target.value as CustomerTier)}>{tiers.map((item) => <option key={item} value={item}>{tierLabels[item]}</option>)}</select><button disabled={busy}>حفظ العميل</button>
      </form>}
      <div className="admin-card"><h3>العملاء الحاليون</h3>
        <div className="admin-filters"><input aria-label="بحث العملاء" placeholder="بحث بالاسم أو الهاتف أو البريد" value={query} onChange={(e) => changeQuery(e.target.value)} /><select aria-label="حالة العميل" value={statusFilter} onChange={(e) => changeFilter(e.target.value as 'all' | 'active' | 'inactive')}><option value="all">كل الحالات</option><option value="active">نشطون</option><option value="inactive">موقوفون</option></select></div>
        {!visibleCustomers.length ? <small>لا توجد نتائج مطابقة.</small> : <div className="cart-lines">{visibleCustomers.map((customer) => { const latest = invitations.find((item) => item.customer_id === customer.id); const editing = editingId === customer.id; return <article className="cart-line" key={customer.id}>
          {editing ? <div className="edit-grid"><input aria-label={`اسم ${customer.name}`} value={editName} onChange={(e) => setEditName(e.target.value)} maxLength={200} required /><input aria-label={`هاتف ${customer.name}`} value={editPhone} onChange={(e) => setEditPhone(e.target.value)} maxLength={50} /><select aria-label={`فئة ${customer.name}`} value={editTier} onChange={(e) => setEditTier(e.target.value as CustomerTier)}>{tiers.map((item) => <option key={item} value={item}>{tierLabels[item]}</option>)}</select><div><button type="button" disabled={busy} onClick={() => void saveEdit(customer.id)}>حفظ التعديل</button><button type="button" disabled={busy} onClick={() => setEditingId(null)}>إلغاء</button></div></div> : <><div><strong>{customer.name}</strong><small>{customer.phone ?? 'بدون هاتف'} · {customer.is_active ? 'نشط' : 'موقوف'}{latest ? ` · ${INVITATION_STATUS_LABELS[latest.status]}` : ''}</small></div>
          <select aria-label={`فئة ${customer.name}`} disabled={!canManage || busy} value={customer.tier} onChange={(e) => void run(() => setCustomerTier(customer.id, e.target.value as CustomerTier), 'تم تحديث فئة العميل.')}>{tiers.map((item) => <option key={item} value={item}>{tierLabels[item]}</option>)}</select>
          {canManage && <><button disabled={busy} onClick={() => beginEdit(customer)}>تعديل</button><button disabled={busy} onClick={() => void run(() => setCustomerActive(customer.id, !customer.is_active), customer.is_active ? 'تم إيقاف العميل.' : 'تم تفعيل العميل.')}>{customer.is_active ? 'إيقاف' : 'تفعيل'}</button></>}
          {canCreate && customer.is_active && <div className="invite-controls"><input aria-label={`بريد دعوة ${customer.name}`} type="email" placeholder="بريد العميل" value={inviteEmail[customer.id] ?? customer.email ?? ''} onChange={(e) => setInviteEmail((current) => ({ ...current, [customer.id]: e.target.value }))} /><button type="button" disabled={busy} onClick={() => void invite(customer)}>{latest?.status === 'pending' ? 'إعادة إرسال' : 'إرسال دعوة'}</button>{latest?.status === 'pending' && canManage && <button type="button" disabled={busy} onClick={() => void run(() => revokeCustomerInvitation(latest.id), 'تم إلغاء الدعوة.')}>إلغاء</button>}{inviteLinks[customer.id] && <div className="invite-link"><input aria-label={`رابط دعوة ${customer.name}`} value={inviteLinks[customer.id]} readOnly onFocus={(e) => e.currentTarget.select()} /><button type="button" onClick={() => void copyInvite(customer.id)}>نسخ</button></div>}</div>}
          </>}
        </article>; })}</div>}
        {filteredCustomers.length > PAGE_SIZE && <div className="pagination" aria-label="صفحات العملاء"><button type="button" disabled={page <= 1 || busy} onClick={() => setPage((current) => current - 1)}>السابق</button><span>صفحة {page} من {pageCount}</span><button type="button" disabled={page >= pageCount || busy} onClick={() => setPage((current) => current + 1)}>التالي</button></div>}
      </div>
    </div>
    {error && <div className="error-banner" role="alert">{error}</div>}{message && <div className="success" role="status">{message}</div>}
  </div>;
}
