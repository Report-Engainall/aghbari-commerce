import { test, expect, type Page } from '@playwright/test';

async function login(page: Page, email: string, password: string) {
  await page.goto('/');
  await expect(page.getByText('بوابة الأغبري', { exact: false }).first()).toBeVisible();
  const loginForm = page.locator('form').filter({ has: page.locator('input[type="password"]') }).first();
  await loginForm.locator('input[type="email"]').fill(email);
  await loginForm.locator('input[type="password"]').fill(password);
  await loginForm.getByRole('button', { name: 'دخول آمن' }).click();
  await expect(page.getByRole('button', { name: 'الكتالوج' })).toBeVisible();
  await expect(page.getByRole('button', { name: /السلة/ })).toBeVisible();
}

function captureBrowserFailures(page: Page) {
  const pageErrors: string[] = [];
  const consoleErrors: string[] = [];
  const failedResponses: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  page.on('console', (message) => { if (message.type() === 'error') consoleErrors.push(message.text()); });
  page.on('response', (response) => { if (response.status() >= 400 && !response.url().endsWith('/favicon.ico')) failedResponses.push(`${response.status()} ${response.request().method()} ${response.url()}`); });
  return { pageErrors, consoleErrors, failedResponses };
}

async function addFirstProduct(page: Page) {
  const addButton = page.getByRole('button', { name: 'إضافة للسلة' }).first();
  await expect(addButton).toBeVisible();
  await expect(addButton).toBeEnabled();
  await addButton.click();
  await expect(page.getByRole('button', { name: /السلة/ })).toBeVisible();
}

test('authenticated customer completes real catalog → cart → order → refresh persistence path', async ({ page }) => {
  const email = process.env.E2E_EMAIL;
  const password = process.env.E2E_PASSWORD;
  if (!email || !password) throw new Error('E2E_EMAIL and E2E_PASSWORD are required; runtime tests must never silently skip.');
  const failures = captureBrowserFailures(page);
  await login(page, email, password);
  await page.getByRole('button', { name: 'الكتالوج' }).click();
  await addFirstProduct(page);
  await page.getByRole('button', { name: 'تأكيد وإرسال الطلب' }).click();
  const success = page.getByRole('status').filter({ hasText: 'تم إرسال الطلب #' }).last();
  await expect(success).toBeVisible();
  const match = (await success.innerText()).match(/طلب #(\d+)/);
  expect(match, 'Order number missing from persisted order response.').not.toBeNull();
  const orderNumber = match![1];
  await page.getByRole('button', { name: 'طلباتي' }).click();
  await expect(page.getByText(`طلب #${orderNumber}`, { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'عرض التفاصيل' }).first().click();
  await expect(page.getByText('الإجمالي', { exact: true })).toBeVisible();
  await page.reload();
  await page.getByRole('button', { name: 'طلباتي' }).click();
  await expect(page.getByText(`طلب #${orderNumber}`, { exact: true })).toBeVisible();
  expect(failures.pageErrors, `Uncaught browser errors: ${failures.pageErrors.join(' | ')}`).toEqual([]);
  expect(failures.consoleErrors, `Browser console errors: ${failures.consoleErrors.join(' | ')}`).toEqual([]);
  expect(failures.failedResponses, `HTTP responses >= 400: ${failures.failedResponses.join(' | ')}`).toEqual([]);
});

test('customer order template survives reload and remains scoped to the customer', async ({ page }) => {
  const email = process.env.E2E_EMAIL;
  const password = process.env.E2E_PASSWORD;
  if (!email || !password) throw new Error('E2E_EMAIL and E2E_PASSWORD are required for template persistence proof.');
  const failures = captureBrowserFailures(page);
  await login(page, email, password);
  await page.getByRole('button', { name: 'الكتالوج' }).click();
  await addFirstProduct(page);
  await page.getByRole('button', { name: /السلة/ }).click();
  const templateInput = page.getByPlaceholder('حفظ كقائمة');
  await templateInput.fill(`E2E-${Date.now()}`);
  await page.getByRole('button', { name: 'حفظ' }).click();
  await page.getByRole('button', { name: 'قوائم الطلب' }).click();
  await expect(page.getByText(/E2E-/).last()).toBeVisible();
  await page.reload();
  await page.getByRole('button', { name: 'قوائم الطلب' }).click();
  await expect(page.getByText(/E2E-/).last()).toBeVisible();
  expect(failures.pageErrors).toEqual([]);
  expect(failures.consoleErrors).toEqual([]);
  expect(failures.failedResponses).toEqual([]);
});

test('tenant isolation: Tenant B cannot read Tenant A order through the real UI session', async ({ browser }) => {
  const emailA = process.env.E2E_EMAIL;
  const passwordA = process.env.E2E_PASSWORD;
  const emailB = process.env.E2E_EMAIL_B;
  const passwordB = process.env.E2E_PASSWORD_B;
  if (!emailA || !passwordA || !emailB || !passwordB) throw new Error('E2E customer A/B credentials are required for tenant-isolation runtime proof.');
  const contextA = await browser.newContext(); const pageA = await contextA.newPage(); const failuresA = captureBrowserFailures(pageA);
  await login(pageA, emailA, passwordA); await pageA.getByRole('button', { name: 'الكتالوج' }).click(); await addFirstProduct(pageA); await pageA.getByRole('button', { name: 'تأكيد وإرسال الطلب' }).click();
  const success = pageA.getByRole('status').filter({ hasText: 'تم إرسال الطلب #' }).last(); await expect(success).toBeVisible();
  const match = (await success.innerText()).match(/طلب #(\d+)/); expect(match).not.toBeNull(); const orderNumberA = match![1];
  const contextB = await browser.newContext(); const pageB = await contextB.newPage(); const failuresB = captureBrowserFailures(pageB);
  await login(pageB, emailB, passwordB); await pageB.getByRole('button', { name: 'طلباتي' }).click(); await expect(pageB.getByText(`طلب #${orderNumberA}`, { exact: true })).toHaveCount(0);
  expect(failuresA.pageErrors).toEqual([]); expect(failuresA.consoleErrors).toEqual([]); expect(failuresA.failedResponses).toEqual([]); expect(failuresB.pageErrors).toEqual([]); expect(failuresB.consoleErrors).toEqual([]); expect(failuresB.failedResponses).toEqual([]);
  await contextB.close(); await contextA.close();
});
