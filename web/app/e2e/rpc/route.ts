import { NextResponse } from "next/server";

export async function POST(request: Request) {
  const endpoint = process.env.TASK6_ANVIL_RPC_URL ?? process.env.NEXT_PUBLIC_TASK6_ANVIL_RPC_URL;
  if (process.env.NEXT_PUBLIC_E2E_FIXTURE !== "1" || !endpoint) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  const body = await request.text();
  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body,
    cache: "no-store",
  });
  return new NextResponse(await response.text(), {
    status: response.status,
    headers: { "content-type": "application/json" },
  });
}
