import { describe, expect, it } from "vitest";
import { contentSecurityPolicy, securityHeaders } from "./headers";

describe("security headers", () => {
  it("uses only reviewed endpoint origins and no wildcard https connect source", () => {
    const policy = contentSecurityPolicy({
      NEXT_PUBLIC_API_BASE_URL: "https://api.launchpad.example/v1",
      NEXT_PUBLIC_RPC_URL: "https://rpc.launchpad.example",
    });
    expect(policy).toContain("https://api.launchpad.example");
    expect(policy).toContain("https://rpc.launchpad.example");
    expect(policy).not.toMatch(/connect-src 'self' https:(?:\s|;)/);
    expect(policy).toContain("img-src 'self' data: blob: https:");
  });

  it("rejects credentials and query strings in CSP origins", () => {
    const policy = contentSecurityPolicy({
      NEXT_PUBLIC_API_BASE_URL: "https://user:secret@example.test?token=bad",
    });
    expect(policy).not.toContain("example.test");
  });

  it("includes browser hardening headers", () => {
    expect(securityHeaders().map((header) => header.key)).toEqual(
      expect.arrayContaining([
        "Content-Security-Policy",
        "Cross-Origin-Opener-Policy",
        "X-Frame-Options",
      ]),
    );
  });
});
