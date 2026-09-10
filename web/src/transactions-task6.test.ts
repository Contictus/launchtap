import { describe, expect, it } from "vitest";
import {
  calculateLaunchValue,
  canonicalObservationState,
  claimIsExecutable,
  decodeTransactionError,
  minimumOutput,
  parseQuoteQuantity,
  reviewedRouterAddress,
  sameWriteIntent,
  transactionDeadline,
  validateLaunchInput,
} from "./transactions";

describe("task 6 transaction math and safety", () => {
  it("requires exact launch fee plus developer buy", () => {
    expect(calculateLaunchValue(100n, 25n)).toBe(125n);
    expect(() => calculateLaunchValue(-1n, 0n)).toThrow();
  });

  it("validates names, symbols, and HTTPS metadata", () => {
    expect(
      validateLaunchInput({
        name: "",
        symbol: "bad symbol",
        imageUrl: "http://x",
        developerBuyGross: 0n,
      }),
    ).toMatchObject({
      name: "Enter a token name.",
      symbol: "Use 1–16 letters or numbers for the symbol.",
      imageUrl: "Use a valid HTTPS URL.",
    });
    expect(
      validateLaunchInput({
        name: "Token",
        symbol: "TOK",
        imageUrl: "https://x.test/image",
        developerBuyGross: 0n,
      }),
    ).toEqual({});
  });

  it("rounds minimum output down at boundaries", () => {
    expect(minimumOutput(101n, 0n)).toBe(101n);
    expect(minimumOutput(101n, 500n)).toBe(95n);
    expect(minimumOutput(1n, 10_000n)).toBe(0n);
    expect(() => minimumOutput(1n, 10_001n)).toThrow();
  });

  it("rejects malformed or negative runtime quote quantities", () => {
    expect(parseQuoteQuantity("0")).toBe(0n);
    expect(parseQuoteQuantity("100")).toBe(100n);
    expect(() => parseQuoteQuantity("01")).toThrow();
    expect(() => parseQuoteQuantity("-1")).toThrow();
    expect(() => parseQuoteQuantity("1.5")).toThrow();
  });

  it("rejects invalid deadline and preserves exact simulation intent", () => {
    expect(transactionDeadline(100n, 900n)).toBe(1000n);
    expect(() => transactionDeadline(100n, 0n)).toThrow();
    const intent = {
      account: "0xAb",
      target: "0xCd",
      value: 1n,
      args: ["0x01", 2n],
      deadline: 10n,
      minimumOutput: 3n,
    };
    expect(sameWriteIntent(intent, { ...intent, account: "0xab" })).toBe(true);
    expect(sameWriteIntent(intent, { ...intent, value: 2n })).toBe(false);
  });

  it("maps known custom errors and redacts unknown provider payloads", () => {
    expect(
      decodeTransactionError(new Error("reverted with custom error DeadlineExpired(1,2)")),
    ).toMatchObject({ code: "DeadlineExpired" });
    const unknown = decodeTransactionError(
      new Error("secret=abc authorization Bearer hidden provider payload"),
    );
    expect(unknown.code).toBe("UnknownTransactionError");
    expect(unknown.message).not.toContain("hidden");
  });

  it("fails closed for routers and claims without reviewed eligibility", () => {
    expect(
      reviewedRouterAddress(
        {
          enabled: false,
          chainId: 1,
          uniswapV2Router02: "0x0000000000000000000000000000000000000001",
        },
        1,
      ),
    ).toBeNull();
    expect(
      reviewedRouterAddress(
        {
          enabled: true,
          chainId: 2,
          uniswapV2Router02: "0x0000000000000000000000000000000000000001",
        },
        1,
      ),
    ).toBeNull();
    expect(
      claimIsExecutable({ serverEligible: true, onChainEligible: true, selectedWalletReady: true }),
    ).toBe(true);
    expect(
      claimIsExecutable({
        serverEligible: false,
        onChainEligible: true,
        selectedWalletReady: true,
      }),
    ).toBe(false);
  });

  it("keeps receipt success in indexing until a canonical snapshot observes it", () => {
    const state = { status: "indexing" as const, hash: "0x123" as `0x${string}` };
    expect(canonicalObservationState(state, false).status).toBe("indexing");
    expect(canonicalObservationState(state, true).status).toBe("indexed");
  });
});
