import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const failures = [];
const warnings = [];
const requiredDirs = ['src/domain', 'src/services', 'src/lib', 'src'];
for (const dir of requiredDirs) if (!fs.existsSync(path.join(root, dir))) failures.push(`Missing architecture directory: ${dir}`);

const sourceFiles = [];
function walk(dir) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (['node_modules', '.git', 'dist'].includes(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (/\.(tsx?|jsx?)$/.test(entry.name)) sourceFiles.push(full);
  }
}
walk(path.join(root, 'src'));

let uiCount = 0;
let serviceCount = 0;
let domainCount = 0;
for (const file of sourceFiles) {
  const rel = path.relative(root, file).replaceAll('\\', '/');
  if (/src\/(App|AdminPanel|.*Panel|.*\.tsx)$/.test(rel)) uiCount += 1;
  if (rel.startsWith('src/services/')) serviceCount += 1;
  if (rel.startsWith('src/domain/')) domainCount += 1;
}
if (!serviceCount) failures.push('No service layer detected.');
if (!domainCount) failures.push('No domain layer detected.');
if (uiCount < 2) warnings.push('UI surface is unusually small; review product coverage.');

const packageJson = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
for (const script of ['typecheck', 'lint', 'test', 'build', 'test:e2e', 'test:release-audit', 'test:product-integrity']) {
  if (!packageJson.scripts?.[script]) failures.push(`Missing quality command: ${script}`);
}

if (failures.length) {
  console.error('ARCHITECTURE AUDIT: FAIL');
  failures.forEach((item) => console.error(`- ${item}`));
  process.exit(1);
}
console.log('ARCHITECTURE AUDIT: PASS');
console.log(JSON.stringify({ sourceFiles: sourceFiles.length, uiCount, serviceCount, domainCount, warnings }, null, 2));
