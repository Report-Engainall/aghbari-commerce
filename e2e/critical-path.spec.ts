import { test, expect, type Page } from '@playwright/test';

async function login(page: Page, email: string, password: string) {
  await page.goto('/');
  await expect(page.getByText('بوابة الأغبري', { exact: false }).first()).toBeVisible();
  const loginForm = page.locator('form').filter({ has: page.locator('input[type="password"]') }).first();
  await loginForm.locator('input[type="email"]').fill(email);
  await loginForm.locator('input[type="password"]').fill(password);
  await loginForm.getByRole('button', { name: 'دخول آمن' }).click();
  await expect(page.getByRole('link', { name: 'المنتجات' })).toBeVisible();
  await expect(page.getByRole('button', { name: /السلة/ })).toBeVisible();
}

function captureBrowserFailures(page: Page) {
  const pageErrors: string[] = [];
  const consoleErrors: string[] = [];
  const failedResponses: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') consoleErrors.push(message.text());
  });
  page.on('response', (response) => {
    const status = response.status();
    if (status >= 400 && !response.url().endsWith('/favicon.ico')) {
      failedResponses.push(`${status} ${response.request().method()} ${response.url()}`);
    }
  });
  return { pageErrors, consoleErrors, failedResponses };
}

test('authenticated customer completes real catalog → cart → order → refresh persistence path', async ({ page }) => {
  const email = process.env.E2E_EMAIL;
  const password = process.env.E2E_PASSWORD;
  if (!email || !password) throw new Error('E2E_EMAIL and E2E_PASSWORD are required; runtime tests must never silently skip.');

  const failures = captureBrowserFailures(page);
  await login(page, email, password);
  await expect(page.getByText('الكتالوج')).toBeVisible();

  const addButton = page.getByRole('button', { name: /إضافة|أضف/ }).first();
  await expect(addButton).toBeVisible();
  await expect(addButton).toBeEnabled();
  await addButton.click();
  await expect(page.getByRole('button', { name: /السلة، 1 أصناف/ })).toBeVisible();

  const checkout = page.getByRole('button', { name: 'إرسال الطلب' });
  await expect(checkout).toBeEnabled();
  await checkout.click();

  const success = page.getByRole('status').filter({ hasText: 'تم إرسال الطلب رقم' }).last();
  await expect(success).toBeVisible();
  const successText = await success.innerText();
  const orderNumberMatch = successText.match(/طلب رقم\s+(\d+)/);
  expect(orderNumberMatch, `Order number missing from success message: ${successText}`).not.toBeNull();
  const orderNumber = orderNumberMatch![1];

  await expect(page.getByText('طلباتي')).toBeVisible();
  await expect(page.getByText(`طلب #${orderNumber}`, { exact: true })).toBeVisible();

  await page.reload();
  await expect(page.getByRole('link', { name: 'المنتجات' })).toBeVisible();
  await expect(page.getByText('طلباتي')).toBeVisible();
  await expect(page.getByText(`طلب #${orderNumber}`, { exact: true })).toBeVisible();

  expect(failures.pageErrors, `Uncaught browser errors: ${failures.pageErrors.join(' | ')}`).toEqual([]);
  expect(failures.consoleErrors, `Browser console errors: ${failures.consoleErrors.join(' | ')}`).toEqual([]);
  expect(failures.failedResponses, `HTTP responses >= 400: ${failures.failedResponses.join(' | ')}`).toEqual([]);
});

test('authenticated customer persists an order template through reload and re-applies it to the real cart', async ({ page }) => {
  const email = process.env.E2E_EMAIL;
  const password = process.env.E2E_PASSWORD;
  if (!email || !password) throw new Error('E2E_EMAIL and E2E_PASSWORD are required; runtime tests must never silently skip.');

  const failures = captureBrowserFailures(page);
  await login(page, email, password);
  await expect(page.getByText('الكتالوج')).toBeVisible();

  const addButton = page.getByRole('button', { name: /إضافة|أضف/ }).first();
  await expect(addButton).toBeEnabled();
  await addButton.click();

  const templateName = `E2E-${Date.now()}`;
  const templateInput = page.getByRole('textbox', { name: 'اسم قالب الطلب' });
  await templateInput.fill(templateName);
  await page.getByRole('button', { name: 'حفظ السلة كقالب' }).click();
  await expect(page.getByText(templateName, { exact: true })).toBeVisible();

  await page.reload();
  await expect(page.getByText(templateName, { exact: true })).toBeVisible();

  const templateRow = page.locator('article.portal-row').filter({ hasText: templateName }).first();
  await templateRow.getByRole('button', { name: 'إلى السلة' }).click();
  await expect(page.getByRole('button', { name: /السلة/ })).toContainText('1');

  expect(failures.pageErrors, `Uncaught browser errors: ${failures.pageErrors.join(' | ')}`).toEqual([]);
  expect(failures.consoleErrors, `Browser console errors: ${failures.consoleErrors.join(' | ')}`).toEqual([]);
  expect(failures.failedResponses, `HTTP responses >= 400: ${failures.failedResponses.join(' | ')}`).toEqual([]);
});

test('tenant isolation: Tenant B cannot read Tenant A order through the real UI session', async ({ browser }) => {
  const emailA = process.env.E2E_EMAIL;
  const passwordA = process.env.E2E_PASSWORD;
  const emailB = process.env.E2E_EMAIL_B;
  const passwordB = process.env.E2E_PASSWORD_B;
  if (!emailA || !passwordA || !emailB || !passwordB) {
    throw new Error('E2E_EMAIL/E2E_PASSWORD and E2E_EMAIL_B/E2E_PASSWORD_B are required for tenant-isolation runtime proof.');
  }

  const contextA = await browser.newContext();
  const pageA = await contextA.newPage();
  const failuresA = captureBrowserFailures(pageA);
  await login(pageA, emailA, passwordA);
  const addButton = pageA.getByRole('button', { name: /إضافة|أضف/ }).first();
  await expect(addButton).toBeEnabled();
  await addButton.click();
  await pageA.getByRole('button', { name: 'إرسال الطلب' }).click();
  const success = pageA.getByRole('status').filter({ hasText: 'تم إرسال الطلب رقم' }).last();
  await expect(success).toBeVisible();
  const match = (await success.innerText()).match(/طلب رقم\s+(\d+)/);
  expect(match, 'Tenant A order number must be captured from the real persisted response.').not.toBeNull();
  const orderNumberA = match![1];

  const contextB = await browser.newContext();
  const pageB = await contextB.newPage();
  const failuresB = captureBrowserFailures(pageB);
  await login(pageB, emailB, passwordB);
  await expect(pageB.getByText('طلباتي')).toBeVisible();
  await expect(pageB.getByText(`طلب #${orderNumberA}`, { exact: true })).toHaveCount(0);

  expect(failuresA.pageErrors, `Tenant A browser errors: ${failuresA.pageErrors.join(' | ')}`).toEqual([]);
  expect(failuresA.consoleErrors, `Tenant A console errors: ${failuresA.consoleErrors.join(' | ')}`).toEqual([]);
  expect(failuresA.failedResponses, `Tenant A HTTP >=400: ${failuresA.failedResponses.join(' | ')}`).toEqual([]);
  expect(failuresB.pageErrors, `Tenant B browser errors: ${failuresB.pageErrors.join(' | ')}`).toEqual([]);
  expect(failuresB.consoleErrors, `Tenant B console errors: ${failuresB.consoleErrors.join(' | ')}`).toEqual([]);
  expect(failuresB.failedResponses, `Tenant B HTTP >=400: ${failuresB.failedResponses.join(' | ')}`).toEqual([]);

  await contextB.close();
  await contextA.close();
});
