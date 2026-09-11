import { useEffect, useMemo, useState, type FormEvent } from 'react';
import type { CartLine, Product, OrderStatus } from './domain/types';
import { calculateClientPreviewTotal } from './domain/order';
import { formatMoney } from './domain/pricing';
import { getCatalog, getProductImageUrls, type CatalogItem } from './services/catalog';
import { getCategories, type CategoryOption } from './services/categories';
import { getCart, removeCartItem, setCartItem, syncOfflineCart } from './services/cart';
import { createOrder } from './services/orders';
import { getCustomerOrders, type CustomerOrderSummary } from './services/customerOrders';
import { getSession, signIn, signOut } from './services/auth';
import { supabase } from './lib/supabase';
import AdminPanel from './AdminPanel';
import CustomerCommerceHub from './CustomerCommerceHub';
import './styles.css';
import './customer-commerce-hub.css';

type UserRole = 'owner' | 'admin' | 'sales' | 'warehouse' | 'viewer';
const STAFF_ROLES = new Set<UserRole>(['owner', 'admin', 'sales', 'warehouse']);
const STATUS_LABELS: Record<OrderStatus, string> = {
  draft: 'مسودة', pending: 'قيد المراجعة', confirmed: 'مؤكد', preparing: 'قيد التجهيز', ready: 'جاهز', completed: 'مكتمل', cancelled: 'ملغي'
};

function mapCatalogItem(item: CatalogItem, categoryName: string, imageUrl?: string): Product & { authorizedPrice?: number } {
  return { id: item.id, sku: item.sku, name: item.name, unit: item.unit, category: categoryName, description: item.description ?? undefined, availableQuantity: item.available_quantity, status: item.status === 'active' ? 'active' : 'inactive', imageUrl, authorizedPrice: item.authorized_price ?? undefined };
}

export default function App() {
  const [email, setEmail] = useState(''); const [password, setPassword] = useState('');
  const [sessionReady, setSessionReady] = useState(false); const [signedIn, setSignedIn] = useState(false); const [role, setRole] = useState<UserRole>('viewer');
  const [authBusy, setAuthBusy] = useState(false); const [authError, setAuthError] = useState<string | null>(null);
  const [query, setQuery] = useState(''); const [catalogSearch, setCatalogSearch] = useState(''); const [categoryId, setCategoryId] = useState<string | null>(null);
  const [categoryOptions, setCategoryOptions] = useState<CategoryOption[]>([]); const [products, setProducts] = useState<Product[]>([]); const [serverPrices, setServerPrices] = useState<Record<string, number>>({});
  const [catalogLoading, setCatalogLoading] = useState(false);
  const [cart, setCart] = useState<CartLine[]>([]); const [checkoutKey, setCheckoutKey] = useState<string | null>(null); const [warehouseId, setWarehouseId] = useState<string | null>(null); const [customerId, setCustomerId] = useState<string | null>(null);
  const [orders, setOrders] = useState<CustomerOrderSummary[]>([]); const [ordersLoading, setOrdersLoading] = useState(false); const [ordersError, setOrdersError] = useState<string | null>(null);
  const [runtimeError, setRuntimeError] = useState<string | null>(null); const [orderBusy, setOrderBusy] = useState(false); const [orderResult, setOrderResult] = useState<string | null>(null);
  const [isOnline, setIsOnline] = useState(() => typeof navigator === 'undefined' ? true : navigator.onLine);

  async function loadIdentity(userId: string) {
    const client = supabase;
    if (!client) throw new Error('Supabase غير مهيأ. تحقق من إعدادات البيئة قبل استخدام التطبيق.');
    const { data: profile, error } = await client.from('profiles').select('customer_id, role').eq('id', userId).single();
    if (error) throw error;
    setCustomerId(profile.customer_id); setRole((profile.role as UserRole) ?? 'viewer');
  }

  useEffect(() => {
    let cancelled = false;
    const client = supabase;
    if (!client) {
      setSessionReady(true);
      setAuthError('Supabase غير مهيأ. تحقق من إعدادات البيئة قبل تسجيل الدخول.');
      return;
    }
    void getSession().then(async (currentSession) => {
      if (cancelled) return;
      setSignedIn(Boolean(currentSession)); setSessionReady(true);
      if (currentSession) await loadIdentity(currentSession.user.id);
    }).catch((error) => {
      if (!cancelled) { setSessionReady(true); setAuthError(error instanceof Error ? error.message : 'تعذر قراءة جلسة الدخول.'); }
    });
    const listener = client.auth.onAuthStateChange((event, nextSession) => {
      if (cancelled) return;
      setSignedIn(Boolean(nextSession));
      if (nextSession) {
        setAuthError(null);
        if (event === 'SIGNED_IN' || event === 'TOKEN_REFRESHED') {
          void loadIdentity(nextSession.user.id).catch((error) => setAuthError(error instanceof Error ? error.message : 'تعذر تحميل هوية الحساب.'));
        }
      } else {
        setCustomerId(null); setRole('viewer'); setOrders([]); setWarehouseId(null); setProducts([]); setCart([]); setServerPrices({}); setCheckoutKey(null);
      }
    });
    return () => { cancelled = true; listener.data.subscription.unsubscribe(); };
  }, []);

  useEffect(() => {
    const handleOnline = () => {
      setIsOnline(true);
      void syncOfflineCart().then(({ failed }) => {
        if (failed) setRuntimeError('تمت استعادة الاتصال، لكن بعض تحديثات السلة تحتاج إعادة المحاولة.');
      }).catch(() => setRuntimeError('تعذر مزامنة السلة بعد استعادة الاتصال.'));
    };
    const handleOffline = () => setIsOnline(false);
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  useEffect(() => {
    if (!signedIn) return;
    const timer = window.setTimeout(() => setCatalogSearch(query.trim()), 250);
    return () => window.clearTimeout(timer);
  }, [query, signedIn]);

  useEffect(() => {
    const client = supabase;
    if (!signedIn || !client || !isOnline) return; let cancelled = false;
    async function loadRuntime() {
      const runtimeClient = supabase;
      if (!runtimeClient) return;
      setCatalogLoading(true); setRuntimeError(null);
      try {
        const [{ data: warehouse, error: warehouseError }, items, savedCart, categories] = await Promise.all([
          runtimeClient.from('warehouses').select('id').eq('is_active', true).order('created_at').limit(1).maybeSingle(),
          getCatalog(catalogSearch, categoryId, 100, 0), getCart(), getCategories()
        ]);
        if (warehouseError) throw warehouseError;
        if (!warehouse?.id) throw new Error('لا يوجد مستودع تشغيلي نشط.');
        if (cancelled) return;
        const categoryMap = new Map(categories.map((item) => [item.id, item.name]));
        const imageUrls = await getProductImageUrls(items.map((item) => item.image_path));
        if (cancelled) return;
        setWarehouseId(warehouse.id); setCategoryOptions(categories);
        const mapped = items.map((item) => mapCatalogItem(item, categoryMap.get(item.category_id ?? '') ?? 'أصناف', item.image_path ? imageUrls.get(item.image_path) : undefined));
        setProducts(mapped); setServerPrices(Object.fromEntries(items.map((item) => [item.id, item.authorized_price ?? 0])));
        setCart(savedCart.map((item) => ({ product: mapped.find((product) => product.id === item.product_id) ?? { id: item.product_id, sku: item.sku, name: item.name, unit: item.unit, category: 'أصناف', availableQuantity: 0, status: 'active' }, quantity: item.quantity, unitPrice: item.authorized_price ?? 0 })));
      } catch (error) {
        if (!cancelled) setRuntimeError(error instanceof Error ? error.message : 'تعذر تحميل بيانات المتجر.');
      } finally { if (!cancelled) setCatalogLoading(false); }
    }
    void loadRuntime(); return () => { cancelled = true; };
  }, [catalogSearch, categoryId, signedIn, isOnline]);

  useEffect(() => {
    if (!signedIn || !isOnline) return; let cancelled = false;
    setOrdersLoading(true); setOrdersError(null);
    void getCustomerOrders(20).then((items) => { if (!cancelled) setOrders(items); }).catch((error) => { if (!cancelled) setOrdersError(error instanceof Error ? error.message : 'تعذر تحميل الطلبات.'); }).finally(() => { if (!cancelled) setOrdersLoading(false); });
    return () => { cancelled = true; };
  }, [signedIn, orderResult, isOnline]);

  useEffect(() => {
    const client = supabase;
    if (!client || !signedIn || !customerId) return;
    const channel = client.channel(`aghbari-customer-orders-${customerId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'orders', filter: `customer_id=eq.${customerId}` }, () => {
        void getCustomerOrders(20).then(setOrders).catch((error) => setOrdersError(error instanceof Error ? error.message : 'تعذر تحديث الطلبات تلقائيًا.'));
      })
      .subscribe();
    return () => { void client.removeChannel(channel); };
  }, [customerId, signedIn]);

  const categories = useMemo(() => [{ id: null, name: 'الكل' }, ...categoryOptions], [categoryOptions]);
  const priceFor = (product: Product) => serverPrices[product.id] ?? 0;
  const total = calculateClientPreviewTotal(cart);

  async function handleLogin(event: FormEvent) {
    event.preventDefault(); setAuthBusy(true); setAuthError(null);
    try { const session = await signIn(email.trim(), password); if (session) await loadIdentity(session.user.id); setPassword(''); }
    catch (error) { setAuthError(error instanceof Error ? error.message : 'تعذر تسجيل الدخول.'); }
    finally { setAuthBusy(false); }
  }

  async function handleSignOut() {
    try { await signOut(); }
    finally { setProducts([]); setCart([]); setOrders([]); setCustomerId(null); setWarehouseId(null); setRole('viewer'); setCheckoutKey(null); setOrderResult(null); }
  }

  async function addToCart(product: Product) {
    const price = priceFor(product);
    if (price <= 0 || product.availableQuantity < 1) return;
    const existing = cart.find((line) => line.product.id === product.id);
    const quantity = Math.min((existing?.quantity ?? 0) + 1, product.availableQuantity);
    try {
      await setCartItem(product.id, quantity);
      setCart((current) => existing ? current.map((line) => line.product.id === product.id ? { ...line, quantity } : line) : [...current, { product, quantity, unitPrice: price }]);
      setCheckoutKey(null); setOrderResult(null); setRuntimeError(null);
    } catch (error) { setRuntimeError(error instanceof Error ? error.message : 'تعذر تحديث السلة.'); }
  }

  async function updateQuantity(id: string, quantity: number) {
    const line = cart.find((item) => item.product.id === id); if (!line) return;
    const next = Math.max(0, Math.min(quantity, line.product.availableQuantity));
    try {
      if (next === 0) { await removeCartItem(id); setCart((current) => current.filter((item) => item.product.id !== id)); }
      else { await setCartItem(id, next); setCart((current) => current.map((item) => item.product.id === id ? { ...item, quantity: next } : item)); }
      setCheckoutKey(null); setRuntimeError(null);
    } catch (error) { setRuntimeError(error instanceof Error ? error.message : 'تعذر تحديث الكمية.'); }
  }

  async function submitOrder() {
    if (!isOnline) { setRuntimeError('إرسال الطلب يحتاج اتصالًا بالإنترنت. تم حفظ تغييرات السلة فقط.'); return; }
    if (!customerId || !warehouseId || !cart.length || orderBusy) return;
    setOrderBusy(true); setOrderResult(null); setRuntimeError(null);
    const idempotencyKey = checkoutKey ?? crypto.randomUUID();
    setCheckoutKey(idempotencyKey);
    try {
      const result = await createOrder({ customerId, idempotencyKey, lines: cart.map((line) => ({ productId: line.product.id, quantity: line.quantity })) }, warehouseId);
      setCart([]); setCheckoutKey(null); setOrderResult(result ? `تم إرسال الطلب رقم ${result.order_number} بنجاح.` : 'تم إرسال الطلب بنجاح.');
    } catch (error) { setRuntimeError(error instanceof Error ? error.message : 'تعذر إرسال الطلب. لم يتم اعتماد أي سعر من العميل.'); }
    finally { setOrderBusy(false); }
  }

  async function refreshCartFromServer() {
    const savedCart = await getCart();
    setCart(savedCart.map((item) => ({ product: products.find((product) => product.id === item.product_id) ?? { id: item.product_id, sku: item.sku, name: item.name, unit: item.unit, category: 'أصناف', availableQuantity: 0, status: 'active' }, quantity: item.quantity, unitPrice: item.authorized_price ?? 0 })));
  }

  if (!sessionReady) return <div className="auth-shell"><div className="auth-card"><span className="eyebrow">الأغبري</span><h1>جارٍ التحقق من الجلسة</h1><p>يتم التحقق من الهوية قبل عرض بيانات المتجر.</p></div></div>;
  if (!signedIn) return <div className="auth-shell"><form className="auth-card" onSubmit={handleLogin}><span className="eyebrow">بوابة الأغبري التجارية</span><h1>تسجيل الدخول</h1><p>ادخل بحسابك للوصول إلى الكتالوج والأسعار المصرح بها.</p><label>البريد الإلكتروني<input type="email" value={email} onChange={(event) => setEmail(event.target.value)} required autoComplete="email" /></label><label>كلمة المرور<input type="password" value={password} onChange={(event) => setPassword(event.target.value)} required autoComplete="current-password" /></label>{authError && <div className="error-banner" role="alert">{authError}</div>}<button className="checkout" disabled={authBusy}>{authBusy ? 'جارٍ الدخول…' : 'دخول آمن'}</button></form></div>;

  return <div className="app-shell"><header className="topbar"><div className="brand"><span className="brand-mark">أ</span><div><strong>بوابة الأغبري</strong><small>للتجارة والجملة</small></div></div><nav aria-label="التنقل الرئيسي"><a className="active" href="#catalog">المنتجات</a>{STAFF_ROLES.has(role) && <a href="#account">مركز التحكم</a>}<a href="#orders">طلباتي</a></nav><div className="topbar-actions"><button className="cart-button" aria-label={`السلة، ${cart.length} أصناف`} onClick={() => document.getElementById('cart')?.scrollIntoView({ behavior: 'smooth' })}>السلة <b>{cart.length}</b></button><button className="signout" onClick={() => void handleSignOut()}>خروج</button></div></header>
    {!isOnline && <div className="offline-banner" role="status" aria-live="polite">أنت الآن دون اتصال. يمكنك تعديل السلة، وسيتم مزامنتها عند عودة الاتصال. <strong>إرسال الطلب يحتاج اتصالًا.</strong></div>}
    <main><section className="hero" id="catalog"><div><span className="eyebrow">تجارة جملة أسرع</span><h1>اطلب احتياج متجرك<br/>بخطوات بسيطة.</h1><p>الكتالوج والسعر والمخزون تأتي من الخادم بعد التحقق من هوية العميل وتصنيفه.</p></div><div className="hero-card"><span>حالة الخدمة</span><strong>{runtimeError ? 'يحتاج انتباهًا' : isOnline ? 'متصل' : 'دون اتصال'}</strong><small>{runtimeError ?? (isOnline ? 'الأسعار المعروضة هي السعر الفعّال المصرح به لحسابك.' : 'البيانات المحلية قد تكون قديمة حتى تعود الشبكة.')}</small></div></section>
      <section className="catalog-section"><div className="catalog-toolbar"><input aria-label="بحث المنتجات" placeholder="ابحث عن منتج أو SKU…" value={query} onChange={(e) => setQuery(e.target.value)} /><select aria-label="تصنيف المنتجات" value={categoryId ?? ''} onChange={(e) => setCategoryId(e.target.value || null)}>{categories.map((item) => <option key={item.id ?? 'all'} value={item.id ?? ''}>{item.name}</option>)}</select></div>
        {catalogLoading ? <div className="loading-state">جارٍ تحميل الكتالوج…</div> : <div className="product-grid">{products.map((product) => { const price = priceFor(product); return <article className="product-card" key={product.id}><div className="product-image">{product.imageUrl ? <img src={product.imageUrl} alt={product.name} loading="lazy" /> : <span>الأغبري</span>}</div><div className="product-info"><span>{product.category}</span><h3>{product.name}</h3><small>{product.sku} · {product.unit}</small><strong>{price > 0 ? formatMoney(price) : 'السعر غير متاح'}</strong><small>{product.availableQuantity > 0 ? `متوفر: ${product.availableQuantity}` : 'غير متوفر'}</small><button disabled={price <= 0 || product.availableQuantity < 1} onClick={() => void addToCart(product)}>أضف للسلة</button></div></article>; })}</div>}
      </section>
      <section className="cart-section" id="cart"><div className="section-heading"><div><span className="eyebrow">السلة</span><h2>طلب الجملة</h2></div><span>{cart.length} أصناف</span></div><div className="cart-card">{!cart.length ? <p>السلة فارغة.</p> : <>{cart.map((line) => <article className="cart-line" key={line.product.id}><div><strong>{line.product.name}</strong><small>{formatMoney(priceFor(line.product))} · {line.product.unit}</small></div><div className="qty-controls"><button aria-label={`إنقاص ${line.product.name}`} onClick={() => void updateQuantity(line.product.id, line.quantity - 1)}>−</button><span>{line.quantity}</span><button aria-label={`زيادة ${line.product.name}`} disabled={line.quantity >= line.product.availableQuantity} onClick={() => void updateQuantity(line.product.id, line.quantity + 1)}>+</button></div></article>)}<div className="cart-total"><span>الإجمالي التقديري</span><strong>{formatMoney(total)}</strong></div><button className="checkout" disabled={orderBusy || !customerId || !warehouseId || !isOnline} onClick={() => void submitOrder()}>{orderBusy ? 'جارٍ اعتماد الطلب…' : 'إرسال طلب الجملة'}</button>{orderResult && <div className="success" role="status">{orderResult}</div>}{runtimeError && <div className="error-banner" role="alert">{runtimeError}</div>}</>}</div></section>
      <section className="orders-section" id="orders"><div className="section-heading"><div><span className="eyebrow">الطلبات</span><h2>طلباتي</h2></div><span>{orders.length} آخر الطلبات</span></div>{ordersLoading ? <div className="loading-state">جارٍ تحميل الطلبات…</div> : ordersError ? <div className="error-banner" role="alert">{ordersError}</div> : !orders.length ? <div className="empty-state">لا توجد طلبات بعد.</div> : <div className="orders-list">{orders.map((order) => <article className="order-card" key={order.id}><div><strong>طلب #{order.order_number}</strong><small>{new Date(order.created_at).toLocaleString('ar-YE')}</small></div><div><strong>{formatMoney(order.total)}</strong><span className={`status status-${order.status}`}>{STATUS_LABELS[order.status]}</span></div></article>)}</div>}</section>
      <CustomerCommerceHub cart={cart} onCartRefresh={refreshCartFromServer} customerId={customerId} warehouseId={warehouseId} />
      {STAFF_ROLES.has(role) && <AdminPanel role={role} />}
    </main></div>;
}
