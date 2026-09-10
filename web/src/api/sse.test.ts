import { describe, expect, it } from "vitest";
import { SseInvalidationStream, type EventSourceLike } from "./sse";

describe("SSE invalidation", () => {
  it("refetches REST before reconnecting", async () => {
    const order: string[] = [];
    const listeners = new Map<string, (event: MessageEvent<string>) => void>();
    const sources: EventSourceLike[] = [];
    const factory = () => {
      order.push("connect");
      const source: EventSourceLike = {
        addEventListener: (name, listener) => listeners.set(name, listener),
        close: () => order.push("close"),
      };
      sources.push(source);
      return source;
    };
    const stream = new SseInvalidationStream({
      url: "https://api.example/events",
      eventSourceFactory: factory,
      queryClient: { invalidateQueries: async () => undefined },
      refetchSnapshot: async () => {
        order.push("rest");
      },
    });
    stream.start();
    listeners.get("error")?.(new MessageEvent("error"));
    await Promise.resolve();
    await Promise.resolve();
    expect(order.indexOf("rest")).toBeGreaterThan(-1);
    expect(order.indexOf("rest")).toBeLessThan(order.lastIndexOf("connect"));
    stream.stop();
    expect(sources.length).toBe(2);
  });
});
