import { useEffect, useState, type FormEvent } from 'react';
import { acceptCustomerInvitation } from './services/customerInvitations';
import { signIn, signUp } from './services/auth';

export default function CustomerActivation({ token }: { token: string }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    void acceptCustomerInvitation(token).then(() => {
      if (!cancelled) { setMessage('تم تفعيل حساب العميل. جارٍ فتح بوابة الأغبري…'); window.history.replaceState({}, '', window.location.pathname); window.setTimeout(() => window.location.reload(), 250); }
    }).catch((e) => {
      if (!cancelled && e instanceof Error && !['AUTH_REQUIRED', 'INVITATION_EMAIL_MISMATCH'].includes(e.message)) setError(e.message);
    });
    return () => { cancelled = true; };
  }, [token]);

  async function submit(event: FormEvent) {
    event.preventDefault(); setError(null); setMessage(null);
    if (password.length < 8) { setError('كلمة المرور يجب أن تكون 8 أحرف على الأقل.'); return; }
    if (password !== confirm) { setError('تأكيد كلمة المرور غير مطابق.'); return; }
    setBusy(true);
    try {
      const session = await signUp(email, password, window.location.href);
      if (!session) { setMessage('تم إنشاء الحساب. أكمل تأكيد البريد الإلكتروني ثم افتح رابط الدعوة مرة أخرى لإتمام الربط.'); return; }
      await signIn(email, password);
      await acceptCustomerInvitation(token);
      window.history.replaceState({}, '', window.location.pathname);
      window.location.reload();
    } catch (e) { setError(e instanceof Error ? e.message : 'تعذر تفعيل الحساب.'); }
    finally { setBusy(false); }
  }

  return <div className="auth-shell"><form className="auth-card" onSubmit={submit}>
    <span className="eyebrow">بوابة الأغبري التجارية</span><h1>تفعيل حساب العميل</h1>
    <p>أنشئ كلمة المرور الخاصة بك لإكمال ربط حسابك بملف العميل.</p>
    <label>البريد الإلكتروني<input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required autoComplete="email" /></label>
    <label>كلمة المرور<input type="password" minLength={8} value={password} onChange={(e) => setPassword(e.target.value)} required autoComplete="new-password" /></label>
    <label>تأكيد كلمة المرور<input type="password" minLength={8} value={confirm} onChange={(e) => setConfirm(e.target.value)} required autoComplete="new-password" /></label>
    {error && <div className="error-banner" role="alert">{error}</div>}
    {message && <div className="success" role="status">{message}</div>}
    <button className="checkout" disabled={busy}>{busy ? 'جارٍ التفعيل…' : 'تفعيل الحساب'}</button>
  </form></div>;
}
