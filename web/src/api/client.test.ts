import { describe, expect, it } from "vitest";
import { ApiClient, resolveApiAssetUrl } from "./client";

describe("generated API wrapper", () => {
  it("resolves API-owned image paths without accepting cross-origin relative URLs", () => {
    expect(resolveApiAssetUrl("https://api.example/", "/v1/tokens/0xabc/image")).toBe(
      "https://api.example/v1/tokens/0xabc/image",
    );
    expect(resolveApiAssetUrl("http://127.0.0.1:18080/", "/v1/image")).toBe(
      "http://127.0.0.1:18080/v1/image",
    );
    expect(resolveApiAssetUrl("https://api.example/", "//attacker.example/image")).toBeNull();
    expect(resolveApiAssetUrl("https://api.example/", "http://attacker.example/image")).toBeNull();
  });

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

  it("serializes token-list filters through the generated response boundary", async () => {
    let requested = "";
    const client = new ApiClient({
      baseUrl: "https://api.example",
      fetch: async (input) => {
        requested = String(input);
        return new Response(
          JSON.stringify({
            items: [],
            snapshot: { chain_id: 1, as_of_block: 4, as_of_block_hash: "0x", finality: "safe" },
          }),
          { status: 200 },
        );
      },
    });
    await client.getTokens({
      phase: "graduated",
      q: "red & blue",
      sort: "volume_24h",
      cursor: "next",
      limit: 20,
    });
    expect(requested).toBe(
      "https://api.example/v1/tokens?phase=graduated&q=red+%26+blue&sort=volume_24h&cursor=next&limit=20",
    );
  });

  it("keeps metadata and image revision validators independent", async () => {
    const requests: Array<{ path: string; ifMatch: string | null }> = [];
    const client = new ApiClient({
      baseUrl: "https://api.example",
      fetch: async (input, init) => {
        const url = new URL(String(input));
        const headers = new Headers(init?.headers);
        requests.push({
          path: `${init?.method ?? "GET"} ${url.pathname}`,
          ifMatch: headers.get("If-Match"),
        });
        if (url.pathname.endsWith("/metadata") && !init?.method) {
          return new Response(JSON.stringify({ revision: 7, description: "latest" }), {
            status: 200,
            headers: { ETag: '"7"', "content-type": "application/json" },
          });
        }
        if (url.pathname.endsWith("/image") && !init?.method) {
          return new Response(new Uint8Array([137, 80, 78, 71]), {
            status: 200,
            headers: { ETag: '"sha256-content"', "X-Revision": "2" },
          });
        }
        if (url.pathname.endsWith("/metadata")) {
          expect(headers.get("Authorization")).toBe("Bearer access");
          expect(headers.get("privy-id-token")).toBe("identity");
          return new Response(JSON.stringify({ revision: 8 }), {
            status: 200,
            headers: { ETag: '"8"', "content-type": "application/json" },
          });
        }
        expect(headers.get("Authorization")).toBe("Bearer access");
        expect(headers.get("privy-id-token")).toBe("identity");
        return new Response(JSON.stringify({ revision: 3 }), {
          status: 200,
          headers: { ETag: '"3"', "content-type": "application/json" },
        });
      },
    });

    const metadata = await client.getTokenMetadata("0xabc");
    const image = await client.getTokenImageRevision("0xabc");
    const file = new File([new Uint8Array([137, 80, 78, 71])], "token.png", {
      type: "image/png",
    });
    const metadataResult = await client.updateTokenMetadata(
      "0xabc",
      { description: "updated" },
      metadata.body.revision,
      metadata.etag,
      { accessToken: "access", identityToken: "identity" },
    );
    const imageResult = await client.updateTokenImage("0xabc", file, image.revision, {
      accessToken: "access",
      identityToken: "identity",
    });

    expect(metadata.etag).toBe('"7"');
    expect(image).toMatchObject({ revision: 2, etag: '"sha256-content"' });
    expect(metadataResult.etag).toBe('"8"');
    expect(imageResult.etag).toBe('"3"');
    expect(requests.map((request) => request.ifMatch)).toEqual([null, null, '"7"', '"2"']);
  });
});
