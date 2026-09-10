import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import openapiTS from "openapi-typescript";
import { astToString } from "openapi-typescript";

const root = resolve(import.meta.dirname, "../..");
const source = join(root, "backend", "openapi", "v1.json");
const target = join(import.meta.dirname, "../src/api/generated.ts");
const check = process.argv.includes("--check");

const document = JSON.parse(await readFile(source, "utf8"));
const generated = `${astToString(await openapiTS(document)).trimEnd()}\n`;
await mkdir(join(import.meta.dirname, "../src/api"), { recursive: true });
if (check) {
  const actual = await readFile(target, "utf8");
  if (actual !== generated)
    throw new Error("src/api/generated.ts is stale; run npm run web-api-sync");
} else {
  await writeFile(target, generated, "utf8");
}
