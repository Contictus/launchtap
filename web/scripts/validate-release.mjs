import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const production = process.argv.includes("--production");
const anvil = process.argv.includes("--anvil");
const required = [
  "NEXT_PUBLIC_PRIVY_APP_ID",
  "NEXT_PUBLIC_DEPLOYMENT_ID",
  "NEXT_PUBLIC_CHAIN_ID",
  "NEXT_PUBLIC_API_BASE_URL",
  "NEXT_PUBLIC_RPC_URL",
];
const fixture = /task6|e2e|anvil|localhost|127\.0\.0\.1|test|mock|fixture/i;
const errors = [];
for (const key of required) if (!process.env[key]?.trim()) errors.push(`${key} is required`);
if (production && process.env.NEXT_PUBLIC_E2E_FIXTURE === "1")
  errors.push("E2E fixture is not deployable");
if (production) {
  for (const key of required)
    if (fixture.test(process.env[key] ?? ""))
      errors.push(`${key} contains a fixture or test value`);
  const generatedPath = path.resolve(process.cwd(), "src/contracts/generated.ts");
  const generated = fs.existsSync(generatedPath) ? fs.readFileSync(generatedPath, "utf8") : "";
  const deploymentMatch = generated.match(
    /export const reviewedDeployments:[^=]+=\s*(\[[\s\S]*?\]);/,
  );
  let reviewedDeployments = [];
  try {
    reviewedDeployments = deploymentMatch ? JSON.parse(deploymentMatch[1]) : [];
  } catch {
    errors.push("reviewed deployment manifest is not valid generated JSON");
  }
  const deployment = reviewedDeployments.find(
    (candidate) =>
      candidate.deploymentId === process.env.NEXT_PUBLIC_DEPLOYMENT_ID &&
      String(candidate.chainId) === process.env.NEXT_PUBLIC_CHAIN_ID,
  );
  if (!deployment) errors.push("deployment ID and chain ID are not in the reviewed manifest");
  else if (!deployment.enabled) errors.push("deployment is disabled in the reviewed manifest");
}
if (anvil && process.env.NEXT_PUBLIC_E2E_FIXTURE !== "1")
  errors.push("Anvil gate requires NEXT_PUBLIC_E2E_FIXTURE=1");
for (const key of ["NEXT_PUBLIC_API_BASE_URL", "NEXT_PUBLIC_RPC_URL"]) {
  const value = process.env[key];
  if (!value) continue;
  try {
    const url = new URL(value);
    if (url.username || url.password || url.search || url.hash)
      errors.push(`${key} contains credentials or query material`);
    if (url.protocol !== "https:" && !(anvil && url.protocol === "http:"))
      errors.push(`${key} must use https outside Anvil`);
  } catch {
    errors.push(`${key} is not a valid URL`);
  }
}
if (errors.length) {
  console.error("Release validation failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}
console.log(
  `Release configuration validated (${production ? "production" : anvil ? "Anvil" : "development"}).`,
);
