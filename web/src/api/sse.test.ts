import { afterEach, describe, expect, it, vi } from "vitest";
import { SseInvalidationStream, type EventSourceLike } from "./sse";

afterEach(() => vi.useRealTimers());

function sourceHarness(order: string[]) {
  let currentError: (() => void) | undefined;
  const sources: EventSourceLike[] = [];
  const factory = () => {
    order.push("connect");
    const source: EventSourceLike = {
      addEventListener: (name, listener) => {
        if (name === "error") currentError = () => listener(new MessageEvent("error"));
      },
      close: () => order.push("close"),
    };
    sources.push(source);
    return source;
  };
  return { factory, sources, triggerError: () => currentError?.() };
}

describe("SSE invalidation", () => {
  it("refetches REST before reconnecting", async () => {
    vi.useFakeTimers();
    const order: string[] = [];
    const harness = sourceHarness(order);
    const stream = new SseInvalidationStream({
      url: "https://api.example/events",
      eventSourceFactory: harness.factory,
      queryClient: { invalidateQueries: async () => undefined },
      refetchSnapshot: async () => {
        order.push("rest");
      },
    });
    stream.start();
    harness.triggerError();
    await vi.advanceTimersByTimeAsync(0);
    expect(order.indexOf("rest")).toBeLessThan(order.lastIndexOf("connect"));
    stream.stop();
    expect(harness.sources.length).toBe(2);
  });

  it("retries REST after transient failure and reconnects only after success", async () => {
    vi.useFakeTimers();
    const order: string[] = [];
    const harness = sourceHarness(order);
    let attempts = 0;
    const stream = new SseInvalidationStream({
      url: "https://api.example/events",
      eventSourceFactory: harness.factory,
      queryClient: { invalidateQueries: async () => undefined },
      retry: { baseDelayMs: 100, maxAttempts: 3 },
      refetchSnapshot: async () => {
        attempts += 1;
        order.push(`rest-${attempts}`);
        if (attempts === 1) throw new Error("temporary");
      },
    });
    stream.start();
    harness.triggerError();
    await vi.advanceTimersByTimeAsync(0);
    expect(harness.sources.length).toBe(1);
    await vi.advanceTimersByTimeAsync(100);
    expect(harness.sources.length).toBe(2);
    expect(order.indexOf("rest-2")).toBeLessThan(order.lastIndexOf("connect"));
    stream.stop();
  });

  it("disposal cancels pending recovery retries", async () => {
    vi.useFakeTimers();
    const order: string[] = [];
    const harness = sourceHarness(order);
    let attempts = 0;
    const stream = new SseInvalidationStream({
      url: "https://api.example/events",
      eventSourceFactory: harness.factory,
      queryClient: { invalidateQueries: async () => undefined },
      retry: { baseDelayMs: 100 },
      refetchSnapshot: async () => {
        attempts += 1;
        throw new Error("offline");
      },
    });
    stream.start();
    harness.triggerError();
    await vi.advanceTimersByTimeAsync(0);
    stream.stop();
    await vi.advanceTimersByTimeAsync(10_000);
    expect(attempts).toBe(1);
    expect(harness.sources.length).toBe(1);
  });

  it("aborts an in-flight REST refetch on disposal", async () => {
    vi.useFakeTimers();
    const order: string[] = [];
    const harness = sourceHarness(order);
    let signal: AbortSignal | undefined;
    const stream = new SseInvalidationStream({
      url: "https://api.example/events",
      eventSourceFactory: harness.factory,
      queryClient: { invalidateQueries: async () => undefined },
      refetchSnapshot: (nextSignal) =>
        new Promise<void>((_, reject) => {
          signal = nextSignal;
          nextSignal?.addEventListener("abort", () => reject(new Error("aborted")));
        }),
    });
    stream.start();
    harness.triggerError();
    await vi.advanceTimersByTimeAsync(0);
    stream.stop();
    expect(signal?.aborted).toBe(true);
  });
});
