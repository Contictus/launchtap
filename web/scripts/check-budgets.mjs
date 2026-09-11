import fs from "node:fs";
import path from "node:path";

const root = path.resolve(process.cwd(), ".next");
const maxInitialJavaScriptBytes = 1_800_000;
const maxAllJavaScriptBytes = 8_000_000;
const maxRouteManifestBytes = 500_000;

function filesUnder(directory, predicate) {
  if (!fs.existsSync(directory)) return [];
  const result = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const filename = path.join(directory, entry.name);
    if (entry.isDirectory()) result.push(...filesUnder(filename, predicate));
    else if (predicate(filename)) result.push(filename);
  }
  return result;
}

if (!fs.existsSync(root)) {
  console.error("Performance budget requires a production build at web/.next");
  process.exit(1);
}

const chunks = filesUnder(path.join(root, "static", "chunks"), (filename) =>
  filename.endsWith(".js"),
);
const total = chunks.reduce((sum, filename) => sum + fs.statSync(filename).size, 0);
const initial = chunks
  .filter((filename) => /(?:main|app|framework|webpack|polyfills)/i.test(path.basename(filename)))
  .reduce((sum, filename) => sum + fs.statSync(filename).size, 0);
const manifests = filesUnder(root, (filename) =>
  /(?:build-manifest|app-build-manifest|routes-manifest)\.json$/.test(filename),
);
const largestManifest = manifests.reduce(
  (max, filename) => Math.max(max, fs.statSync(filename).size),
  0,
);

const violations = [];
if (initial > maxInitialJavaScriptBytes)
  violations.push(`initial JavaScript ${initial} > ${maxInitialJavaScriptBytes} bytes`);
if (total > maxAllJavaScriptBytes)
  violations.push(`all JavaScript ${total} > ${maxAllJavaScriptBytes} bytes`);
if (largestManifest > maxRouteManifestBytes)
  violations.push(`route manifest ${largestManifest} > ${maxRouteManifestBytes} bytes`);

const bundleFiles = filesUnder(root, (filename) => /\.(?:js|json|html)$/.test(filename));
const forbidden =
  /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|sk_(?:live|test)_[A-Za-z0-9]+|Bearer\s+[A-Za-z0-9._-]{20,}|0x4f3edf983ac636a65a842ce7c78d9aa706d3b113/i;
for (const filename of bundleFiles) {
  const source = fs.readFileSync(filename, "utf8");
  if (forbidden.test(source))
    violations.push(`sensitive value pattern in ${path.relative(root, filename)}`);
}

console.log(
  `bundle budget: initial=${initial} bytes, all=${total} bytes, largest-manifest=${largestManifest} bytes`,
);
if (violations.length) {
  for (const violation of violations) console.error(`BUDGET_FAIL: ${violation}`);
  process.exit(1);
}
