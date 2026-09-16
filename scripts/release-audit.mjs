import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const root = process.cwd();
const requiredFiles = [
  'package.json',
  'package-lock.json',
  'vite.config.ts',
  'playwright.config.ts',
  '.env.example',
  'vercel.json',
  'index.html',
  'src/main.tsx',
  'src/App.tsx',
  'src/lib/supabase.ts',
  'supabase/config.toml',
];

const requiredWorkflows = [
  '.github/workflows/application-quality.yml',
  '.github/workflows/runtime-e2e.yml',
  '.github/workflows/security-audit.yml',
  '.github/workflows/supabase-migration-proof.yml',
  '.github/workflows/bootstrap-release-lockfile.yml',
];

const failures = [];
function fail(message) { failures.push(message); }

for (const file of requiredFiles) {
  if (!existsSync(join(root, file))) fail(`Missing required release file: ${file}`);
}
for (const file of requiredWorkflows) {
  if (!existsSync(join(root, file))) fail(`Missing required workflow: ${file}`);
}

const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
const lockPath = join(root, 'package-lock.json');
if (existsSync(lockPath)) {
  try {
    const lock = JSON.parse(readFileSync(lockPath, 'utf8'));
    if (lock.lockfileVersion !== 3) fail(`package-lock.json must use lockfileVersion 3 (found ${lock.lockfileVersion}).`);
    const rootPackage = lock.packages?.[''];
    if (!rootPackage) fail('package-lock.json is missing its root package entry.');
    if (rootPackage?.name !== pkg.name) fail(`Lockfile root name mismatch: ${rootPackage?.name} !== ${pkg.name}`);
    if (rootPackage?.version !== pkg.version) fail(`Lockfile root version mismatch: ${rootPackage?.version} !== ${pkg.version}`);
    for (const section of ['dependencies', 'devDependencies']) {
      for (const [name, version] of Object.entries(pkg[section] ?? {})) {
        const locked = rootPackage?.[section]?.[name];
        if (locked !== version) fail(`Lockfile ${section} mismatch for ${name}: ${locked} !== ${version}`);
      }
    }
  } catch (error) {
    fail(`package-lock.json is not valid JSON: ${error.message}`);
  }
}

const workflowChecks = {
  '.github/workflows/application-quality.yml': ['npm ci', 'TARGET_SHA', 'workflow_dispatch'],
  '.github/workflows/runtime-e2e.yml': ['npm ci', 'E2E_EXACT_SHA', 'workflow_dispatch'],
  '.github/workflows/security-audit.yml': ['npm ci', 'TARGET_SHA', 'workflow_dispatch'],
  '.github/workflows/supabase-migration-proof.yml': ['TARGET_SHA', 'workflow_dispatch', 'supabase test db'],
  '.github/workflows/bootstrap-release-lockfile.yml': ['package-lock.json', 'npm install --package-lock-only', 'lockfileVersion'],
};
for (const [file, needles] of Object.entries(workflowChecks)) {
  const path = join(root, file);
  if (!existsSync(path)) continue;
  const text = readFileSync(path, 'utf8');
  for (const needle of needles) {
    if (!text.includes(needle)) fail(`Release workflow contract missing '${needle}': ${file}`);
  }
}

const sourceRoot = join(root, 'src');
const ignoredNames = new Set(['node_modules', 'dist', '.git']);
const suspiciousPatterns = [
  /\bTODO\b/i,
  /\bFIXME\b/i,
  /\bnot\s+implemented\b/i,
  /\bnotimplemented\b/i,
  /\b(?:mock|fake|sample)\s+(?:data|api|response|success)\b/i,
];
const legacyBrandPattern = /العامري|\bAlamri\b|\bAl-Amri\b/i;
const forbiddenRuntimePatterns = [
  { pattern: /VITE_SUPABASE_SERVICE_ROLE|SUPABASE_SERVICE_ROLE|service_role/i, label: 'service-role credential reference' },
  { pattern: /\beval\s*\(/i, label: 'eval()' },
  { pattern: /new\s+Function\s*\(/i, label: 'dynamic Function constructor' },
  { pattern: /dangerouslySetInnerHTML/i, label: 'dangerouslySetInnerHTML' },
];

function walk(dir) {
  if (!existsSync(dir)) return [];
  const result = [];
  for (const entry of readdirSync(dir)) {
    if (ignoredNames.has(entry)) continue;
    const path = join(dir, entry);
    const info = statSync(path);
    if (info.isDirectory()) result.push(...walk(path));
    else result.push(path);
  }
  return result;
}

const sourceFiles = walk(sourceRoot).filter((file) => /\.(?:ts|tsx|js|mjs|css|html)$/.test(file));
for (const file of sourceFiles) {
  const text = readFileSync(file, 'utf8');
  const rel = relative(root, file).replaceAll('\\', '/');
  if (legacyBrandPattern.test(text)) fail(`Legacy branding found in executable source: ${rel}`);
  for (const pattern of suspiciousPatterns) {
    if (pattern.test(text) && !/(?:\.test\.|tests?\/)/i.test(rel)) {
      fail(`Suspicious completion/mock marker ${pattern} found in executable source: ${rel}`);
    }
  }
  for (const { pattern, label } of forbiddenRuntimePatterns) {
    if (pattern.test(text)) fail(`Forbidden runtime construct ${label} found in executable source: ${rel}`);
  }
  if (/https?:\/\/(?:localhost|127\.0\.0\.1)(?::\d+)?\b/i.test(text)) {
    fail(`Hard-coded local runtime URL found in executable source: ${rel}`);
  }
}

for (const file of ['index.html', 'public/manifest.webmanifest', 'vercel.json', '.env.example']) {
  const path = join(root, file);
  if (!existsSync(path)) continue;
  const text = readFileSync(path, 'utf8');
  if (legacyBrandPattern.test(text)) fail(`Legacy branding found in release artifact: ${file}`);
  for (const { pattern, label } of forbiddenRuntimePatterns) {
    if (pattern.test(text)) fail(`Forbidden runtime construct ${label} found in release artifact: ${file}`);
  }
}

const vitePath = join(root, 'vite.config.ts');
if (existsSync(vitePath)) {
  const viteText = readFileSync(vitePath, 'utf8');
  if (!viteText.includes("product: 'aghbari-commerce'")) fail('Build metadata must identify aghbari-commerce.');
  if (!viteText.includes('git_sha: gitSha')) fail('Build metadata must carry the exact Git SHA.');
  if (!viteText.includes('built_at: builtAt')) fail('Build metadata must carry an immutable build timestamp.');
  if (!viteText.includes("build: { sourcemap: true }")) fail('Production builds must retain source maps for release diagnostics.');
}

const swPath = join(root, 'public/sw.js');
if (existsSync(swPath)) {
  const swText = readFileSync(swPath, 'utf8');
  if (!swText.includes("event.request.method !== 'GET'")) fail('Service worker must not intercept non-GET requests.');
  if (!swText.includes("url.origin !== self.location.origin")) fail('Service worker must not intercept cross-origin requests.');
  if (!swText.includes("url.pathname.startsWith('/api/')")) fail('Service worker must bypass API traffic.');
  if (!swText.includes("url.pathname.includes('/auth/')")) fail('Service worker must bypass auth traffic.');
}

const manifestPath = join(root, 'public/manifest.webmanifest');
if (existsSync(manifestPath)) {
  try {
    const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
    if (manifest.lang !== 'ar') fail('PWA manifest language must remain Arabic.');
    if (manifest.dir !== 'rtl') fail('PWA manifest direction must remain RTL.');
    if (manifest.display !== 'standalone') fail('PWA manifest must use standalone display.');
    if (manifest.start_url !== '/') fail('PWA manifest start_url must remain /.');
    if (manifest.scope !== '/') fail('PWA manifest scope must remain /.');
    if (!Array.isArray(manifest.icons) || manifest.icons.length < 2) fail('PWA manifest must provide at least two icon declarations.');
    if (!manifest.icons.some((icon) => icon.sizes === '192x192')) fail('PWA manifest is missing a 192x192 icon.');
    if (!manifest.icons.some((icon) => icon.sizes === '512x512')) fail('PWA manifest is missing a 512x512 icon.');
  } catch (error) {
    fail(`PWA manifest is not valid JSON: ${error.message}`);
  }
}

for (const script of ['test', 'lint', 'build', 'test:e2e', 'test:release-audit', 'typecheck']) {
  if (!pkg.scripts?.[script]) fail(`Missing package script: ${script}`);
}
if (pkg.engines?.node !== '>=22 <23') fail('Node runtime contract must remain pinned to >=22 <23.');
if (pkg.private !== true) fail('Application package must remain private.');
if (pkg.type !== 'module') fail('Application package must remain ESM.');
if (typeof pkg.version !== 'string' || !/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(pkg.version)) fail(`Invalid application version: ${pkg.version}`);

const envExample = readFileSync(join(root, '.env.example'), 'utf8');
for (const key of ['VITE_SUPABASE_URL', 'VITE_SUPABASE_PUBLISHABLE_KEY']) {
  if (!new RegExp(`^${key}=`, 'm').test(envExample)) fail(`Missing environment key in .env.example: ${key}`);
}
if (/SERVICE_ROLE|ANON_KEY\s*=\s*sk_/i.test(envExample)) fail('Environment example must not advertise privileged Supabase credentials.');

const migrationRoot = join(root, 'supabase', 'migrations');
if (!existsSync(migrationRoot)) fail('Missing Supabase migration directory.');
const migrationFiles = walk(migrationRoot).filter((file) => file.endsWith('.sql')).sort();
const migrationVersions = migrationFiles.map((file) => {
  const name = file.split(/[/\\]/).pop() ?? '';
  const match = name.match(/^(\d+)_/);
  if (!match) fail(`Migration filename must begin with a numeric version: ${relative(root, file)}`);
  return match?.[1] ?? '';
}).filter(Boolean);
const duplicateVersions = migrationVersions.filter((version, index) => migrationVersions.indexOf(version) !== index);
for (const version of [...new Set(duplicateVersions)]) fail(`Duplicate migration version detected: ${version}`);

const migrationText = migrationFiles.map((file) => readFileSync(file, 'utf8')).join('\n');
if (/\bDROP\s+SCHEMA\s+public\b/i.test(migrationText)) fail('Release migrations must not drop the public schema.');
if (/\bDROP\s+DATABASE\b/i.test(migrationText)) fail('Release migrations must not contain DROP DATABASE.');

const rpcCalls = new Set();
for (const file of sourceFiles.filter((path) => /\.(?:ts|tsx|js|mjs)$/.test(path))) {
  const text = readFileSync(file, 'utf8');
  for (const match of text.matchAll(/\.rpc\(\s*['"]([a-z0-9_]+)['"]/gi)) rpcCalls.add(match[1]);
}
const missingRpcs = [...rpcCalls].filter((name) => {
  const functionPattern = new RegExp(`(?:create|replace)\\s+function\\s+(?:public\\.)?${name}\\s*\\(`, 'i');
  return !functionPattern.test(migrationText);
});
for (const name of missingRpcs) fail(`RPC contract missing from migration history: ${name}`);

const vercelText = readFileSync(join(root, 'vercel.json'), 'utf8');
for (const header of ['Content-Security-Policy', 'X-Content-Type-Options', 'X-Frame-Options', 'Strict-Transport-Security']) {
  if (!vercelText.includes(`\"key\": \"${header}\"`)) fail(`Required production security header missing from vercel.json: ${header}`);
}

if (failures.length) {
  console.error('RELEASE AUDIT: FAIL');
  for (const item of failures) console.error(`- ${item}`);
  process.exit(1);
}

console.log('RELEASE AUDIT: PASS');
console.log(`Checked required files: ${requiredFiles.length + requiredWorkflows.length}`);
console.log(`Checked ${rpcCalls.size} literal frontend RPC contracts against migration history.`);
console.log(`Checked ${migrationFiles.length} SQL migrations for release topology safety.`);
console.log('Checked lockfile/package manifest synchronization.');
console.log('Checked release workflows, executable source, release artifacts, production security headers, PWA, service-worker boundaries, package identity, and credential-safety contracts.');
