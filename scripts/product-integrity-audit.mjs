import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const required = [
  'src/App.tsx', 'src/AdminPanel.tsx', 'src/lib/supabase.ts', 'src/services/auth.ts',
  'src/services/orders.ts', 'src/services/catalog.ts', 'src/services/cart.ts', 'src/services/staffOrders.ts',
  'src/domain/order.ts', 'src/domain/pricing.ts', 'src/domain/import.ts', 'src/domain/businessIntelligence.ts', 'src/AppErrorBoundary.tsx'
];
const requiredMigrations = [
  '0033_onyx_isolated_analytics_sandbox.sql', '0034_onyx_tenant_cross_key_hardening.sql',
  '0035_onyx_fk_indexes.sql', '0036_notification_rls_and_fk_indexes.sql'
];

const failures = [];
for (const file of required) if (!fs.existsSync(path.join(root, file))) failures.push(`Missing required file: ${file}`);
for (const file of requiredMigrations) if (!fs.existsSync(path.join(root, 'supabase', 'migrations', file))) failures.push(`Missing required migration: ${file}`);

const sourceFiles = [];
function walk(dir) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (['node_modules', '.git', 'dist'].includes(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (/\.(tsx?|jsx?|css|html)$/.test(entry.name)) sourceFiles.push(full);
  }
}
walk(path.join(root, 'src'));

const forbiddenBrand = /العامري|عامري|Alamri|alamri/i;
const forbiddenMatches = [];
const debugMatches = [];
for (const file of sourceFiles) {
  const text = fs.readFileSync(file, 'utf8');
  if (forbiddenBrand.test(text)) forbiddenMatches.push(path.relative(root, file));
  if (/console\.(log|debug)\s*\(/.test(text)) debugMatches.push(path.relative(root, file));
}
if (forbiddenMatches.length) failures.push(`Legacy branding found in source: ${forbiddenMatches.join(', ')}`);
if (debugMatches.length) failures.push(`Debug console calls found in source: ${debugMatches.join(', ')}`);

const envExamplePath = path.join(root, '.env.example');
if (!fs.existsSync(envExamplePath)) failures.push('Missing environment contract: .env.example');
else {
  const envExample = fs.readFileSync(envExamplePath, 'utf8');
  if (!/^VITE_SUPABASE_URL=/m.test(envExample)) failures.push('Missing environment contract: VITE_SUPABASE_URL');
  if (!/^VITE_SUPABASE_PUBLISHABLE_KEY=/m.test(envExample)) failures.push('Missing environment contract: VITE_SUPABASE_PUBLISHABLE_KEY');
}

const packageJson = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
for (const script of ['typecheck', 'lint', 'test', 'build', 'test:e2e', 'test:release-audit', 'test:product-integrity']) {
  if (!packageJson.scripts?.[script]) failures.push(`Missing npm script: ${script}`);
}

if (failures.length) {
  console.error('PRODUCT INTEGRITY AUDIT: FAIL');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}
console.log('PRODUCT INTEGRITY AUDIT: PASS');
console.log(`Checked ${required.length} required files, ${requiredMigrations.length} critical migrations, ${sourceFiles.length} source files, and the environment contract.`);
