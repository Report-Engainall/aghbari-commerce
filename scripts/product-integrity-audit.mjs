import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const required = [
  'src/App.tsx', 'src/AdminPanel.tsx', 'src/lib/supabase.ts', 'src/services/auth.ts',
  'src/services/orders.ts', 'src/services/catalog.ts', 'src/services/cart.ts', 'src/services/staffOrders.ts',
  'src/domain/order.ts', 'src/domain/pricing.ts', 'src/domain/import.ts', 'src/domain/businessIntelligence.ts', 'src/AppErrorBoundary.tsx'
];

const requiredMigrationPatterns = [
  /^20260909005534_.*\.sql$/,
  /^20260909005546_.*\.sql$/,
  /^20260909005715_.*\.sql$/,
  /^20260909005745_.*\.sql$/,
  /^20260909005901_.*\.sql$/,
  /^20260909010000_.*\.sql$/,
];

const migrationDir = path.join(root, 'supabase', 'migrations');
const migrationNames = fs.existsSync(migrationDir) ? fs.readdirSync(migrationDir) : [];
const failures = [];
for (const file of required) if (!fs.existsSync(path.join(root, file))) failures.push(`Missing required file: ${file}`);
for (const pattern of requiredMigrationPatterns) if (!migrationNames.some((name) => pattern.test(name))) failures.push(`Missing required canonical migration: ${pattern}`);

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
const legacyRuntime = /\b(?:localStorage|sessionStorage)\s*\./;
const placeholderActions = /\b(?:TODO|FIXME)\b|alert\s*\(|(?:mock|fake data|placeholder action)/i;
const forbiddenMatches = [];
const runtimeStorageMatches = [];
const placeholderMatches = [];
const debugMatches = [];
for (const file of sourceFiles) {
  const text = fs.readFileSync(file, 'utf8');
  const relative = path.relative(root, file);
  if (forbiddenBrand.test(text)) forbiddenMatches.push(relative);
  if (legacyRuntime.test(text)) runtimeStorageMatches.push(relative);
  if (placeholderActions.test(text)) placeholderMatches.push(relative);
  if (/console\.(log|debug)\s*\(/.test(text)) debugMatches.push(relative);
}
if (forbiddenMatches.length) failures.push(`Legacy branding found in source: ${forbiddenMatches.join(', ')}`);
if (runtimeStorageMatches.length) failures.push(`Browser storage persistence found in source: ${runtimeStorageMatches.join(', ')}`);
if (placeholderMatches.length) failures.push(`Placeholder/debug action markers found in source: ${placeholderMatches.join(', ')}`);
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
console.log(`Checked ${required.length} required files, ${requiredMigrationPatterns.length} canonical migrations, ${sourceFiles.length} source files, and the environment contract.`);
