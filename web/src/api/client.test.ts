import { describe, expect, it } from "vitest";
import { ApiClient } from "./client";

describe("generated API wrapper", () => {
  it("maps RFC problem responses and never places auth in the URL", async () => {
    let requested = "";
    const client = new ApiClient({
      baseUrl: "https://api.example/",
      fetch: async (input, init) => {
        requested = String(input);
        expect((init?.headers as Headers).get("Authorization")).toBe("Bearer secret");
        return new Response(
          JSON.stringify({
            type: "urn:launchpad:problem:cursor_invalidated",
            detail: "internal detail",
          }),
          { status: 409, headers: { "content-type": "application/problem+json" } },
        );
      },
    });
    await expect(
      client.request("/v1/tokens?cursor=public", {}, { accessToken: "secret" }),
    ).rejects.toMatchObject({ code: "cursor_invalidated", status: 409 });
    expect(requested).toBe("https://api.example/v1/tokens?cursor=public");
    expect(requested).not.toContain("secret");
  });

  it("rejects sensitive query parameter names", async () => {
    const client = new ApiClient({ baseUrl: "https://api.example" });
    await expect(client.request("/v1/tokens?access_token=secret")).rejects.toThrow(
      "Sensitive values",
    );
  });
});
