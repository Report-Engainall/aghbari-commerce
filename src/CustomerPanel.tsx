import { useCallback, useEffect, useState } from 'react';
import type { CustomerTier } from './domain/types';
import { createCustomer, getCustomers, setCustomerActive, setCustomerTier, type StaffCustomer } from './services/customers';
import { createCustomerInvitation, getCustomerInvitations, revokeCustomerInvitation, type CustomerInvitation } from './services/customerInvitations';

const tiers: CustomerTier[] = ['retail', 'wholesale', 'distributor'];
const tierLabels: Record<CustomerTier, string> = { retail: 'تجزئة', wholesale: 'جملة', distributor: 'موزع' };
type UserRole = 'owner' | 'admin' | 'sales' | 'warehouse' | 'viewer';
const INVITATION_STATUS_LABELS: Record<CustomerInvitation['status'], string> = { pending: 'بانتظار التفعيل', accepted: 'تم التفعيل', expired: 'منتهية', revoked: 'ملغاة' };

export default function CustomerPanel({ role }: { role: UserRole }) {
  const canCreate = ['owner', 'admin', 'sales'].includes(role);
  const canManage = ['owner', 'admin'].includes(role);
  const [customers, setCustomers] = useState<StaffCustomer[]>([]);
  const [invitations, setInvitations] = useState<CustomerInvitation[]>([]);
  const [name, setName] = useState(''); const [phone, setPhone] = useState('');
  const [tier, setTier] = useState<CustomerTier>('wholesale');
  const [inviteEmail, setInviteEmail] = useState<Record<string, string>>({});
  const [inviteLinks, setInviteLinks] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false); const [error, setError] = useState<string | null>(null); const [message, setMessage] = useState<string | null>(null);

  const reload = useCallback(async () => {
    const [nextCustomers, nextInvitations] = await Promise.all([getCustomers(200), getCustomerInvitations(200)]);
    setCustomers(nextCustomers); setInvitations(nextInvitations);
  }, []);
  useEffect(() => { void reload().catch((e) => setError(e instanceof Error ? e.message : 'تعذر تحميل العملاء.')); }, [reload]);

  async function run(action: () => Promise<unknown>, success: string) {
    setBusy(true); setError(null); setMessage(null);
    try { await action(); setMessage(success); await reload(); } catch (e) { setError(e instanceof Error ? e.message : 'تعذر تنفيذ العملية.'); } finally { setBusy(false); }
  }

  async function invite(customer: StaffCustomer) {
    const email = inviteEmail[customer.id]?.trim() || customer.email?.trim() || '';
    if (!email) { setError('أدخل بريد العميل قبل إرسال الدعوة.'); return; }
    setBusy(true); setError(null); setMessage(null);
    try { const result = await createCustomerInvitation(customer.id, email, 72); setInviteLinks((current) => ({ ...current, [customer.id]: result.url })); setMessage('تم إنشاء دعوة جديدة.'); await reload(); }
    catch (e) { setError(e instanceof Error ? e.message : 'تعذر إنشاء دعوة العميل.'); } finally { setBusy(false); }
  }

  async function copyInvite(customerId: string) {
    const url = inviteLinks[customerId]; if (!url) return;
    try { await navigator.clipboard.writeText(url); setMessage('تم نسخ رابط الدعوة.'); } catch { setError('تعذر نسخ الرابط تلقائيًا.'); }
  }

  if (!canCreate && !canManage) return null;
  return <div className="cart-panel" id="customers-admin">
    <div className="section-heading"><div><span className="eyebrow">العملاء</span><h2>دورة العميل</h2></div><span>{customers.length} عملاء</span></div>
    <div className="admin-grid">
      {canCreate && <form className="admin-card" onSubmit={(e) => { e.preventDefault(); void run(async () => { await createCustomer(name.trim(), phone.trim(), tier); setName(''); setPhone(''); }, 'تم إنشاء العميل وتسجيل أثر العملية.'); }}>
        <h3>عميل جديد</h3><input aria-label="اسم العميل" placeholder="اسم العميل" value={name} onChange={(e) => setName(e.target.value)} required />
        <input aria-label="هاتف العميل" placeholder="رقم الهاتف" value={phone} onChange={(e) => setPhone(e.target.value)} />
        <select aria-label="فئة العميل" value={tier} onChange={(e) => setTier(e.target.value as CustomerTier)}>{tiers.map((item) => <option key={item} value={item}>{tierLabels[item]}</option>)}</select><button disabled={busy}>حفظ العميل</button>
      </form>}
      <div className="admin-card"><h3>العملاء الحاليون</h3>
        {!customers.length ? <small>لا يوجد عملاء مسجلون بعد.</small> : <div className="cart-lines">{customers.map((customer) => { const latest = invitations.find((item) => item.customer_id === customer.id); return <article className="cart-line" key={customer.id}>
          <div><strong>{customer.name}</strong><small>{customer.phone ?? 'بدون هاتف'} · {customer.is_active ? 'نشط' : 'موقوف'}{latest ? ` · ${INVITATION_STATUS_LABELS[latest.status]}` : ''}</small></div>
          <select aria-label={`فئة ${customer.name}`} disabled={!canManage || busy} value={customer.tier} onChange={(e) => void run(() => setCustomerTier(customer.id, e.target.value as CustomerTier), 'تم تحديث فئة العميل.')}>{tiers.map((item) => <option key={item} value={item}>{tierLabels[item]}</option>)}</select>
          {canManage && <button disabled={busy} onClick={() => void run(() => setCustomerActive(customer.id, !customer.is_active), customer.is_active ? 'تم إيقاف العميل.' : 'تم تفعيل العميل.')}>{customer.is_active ? 'إيقاف' : 'تفعيل'}</button>}
          {canCreate && customer.is_active && <div className="invite-controls"><input aria-label={`بريد دعوة ${customer.name}`} type="email" placeholder="بريد العميل" value={inviteEmail[customer.id] ?? customer.email ?? ''} onChange={(e) => setInviteEmail((current) => ({ ...current, [customer.id]: e.target.value }))} /><button type="button" disabled={busy} onClick={() => void invite(customer)}>{latest?.status === 'pending' ? 'إعادة إرسال' : 'إرسال دعوة'}</button>
            {latest?.status === 'pending' && canManage && <button type="button" disabled={busy} onClick={() => void run(() => revokeCustomerInvitation(latest.id), 'تم إلغاء الدعوة.')}>إلغاء</button>}
            {inviteLinks[customer.id] && <div className="invite-link"><input aria-label={`رابط دعوة ${customer.name}`} value={inviteLinks[customer.id]} readOnly onFocus={(e) => e.currentTarget.select()} /><button type="button" onClick={() => void copyInvite(customer.id)}>نسخ</button></div>}
          </div>}
        </article>; })}</div>}
      </div>
    </div>
    {error && <div className="error-banner" role="alert">{error}</div>}{message && <div className="success" role="status">{message}</div>}
  </div>;
}
