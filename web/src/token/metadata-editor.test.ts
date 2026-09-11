import { describe, expect, it, vi } from "vitest";
import type { ApiClient } from "@/api/client";
import { recoverMetadataConflict } from "./metadata-editor";

describe("metadata conflict recovery", () => {
  it("refreshes token DTO, metadata ETag/revision, and image revision before review", async () => {
    const onConflict = vi.fn(async () => ({
      description: "token DTO",
      x_url: "https://x.com/token",
      telegram_url: "https://t.me/token",
    }));
    const client = {
      getTokenMetadata: vi.fn(async () => ({
        body: {
          description: "latest metadata",
          x_url: "https://x.com/latest",
          telegram_url: "",
          revision: 9,
        },
        etag: '"9"',
      })),
      getTokenImageRevision: vi.fn(async () => ({ revision: 4, etag: '"sha256-latest"' })),
    } as unknown as ApiClient;

    await expect(recoverMetadataConflict(client, "0xabc", onConflict)).resolves.toEqual({
      description: "latest metadata",
      xUrl: "https://x.com/latest",
      telegramUrl: "",
      metadataRevision: 9,
      metadataEtag: '"9"',
      imageRevision: 4,
    });
    expect(onConflict).toHaveBeenCalledOnce();
    expect(client.getTokenMetadata).toHaveBeenCalledWith("0xabc");
    expect(client.getTokenImageRevision).toHaveBeenCalledWith("0xabc");
  });

  it("resets a missing image validator instead of retaining a stale revision", async () => {
    const client = {
      getTokenMetadata: async () => ({
        body: { description: "latest", x_url: "", telegram_url: "", revision: 3 },
        etag: '"3"',
      }),
      getTokenImageRevision: async () => {
        throw new Error("image not found");
      },
    } as unknown as ApiClient;
    await expect(recoverMetadataConflict(client, "0xabc", () => undefined)).resolves.toMatchObject({
      metadataRevision: 3,
      metadataEtag: '"3"',
      imageRevision: 0,
    });
  });
});
