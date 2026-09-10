import type { QueryClient, QueryKey } from "@tanstack/react-query";
import type { ApiEvent } from "./types";

export type EventSourceLike = {
  addEventListener: (type: string, listener: (event: MessageEvent<string>) => void) => void;
  close: () => void;
};
export type EventSourceFactory = (url: string) => EventSourceLike;

/** SSE is a best-effort invalidation hint. Canonical data always comes from REST. */
export class SseInvalidationStream {
  private source: EventSourceLike | null = null;
  private reconnecting = false;
  private stopped = false;
  constructor(
    private readonly options: {
      url: string;
      queryClient: Pick<QueryClient, "invalidateQueries">;
      refetchSnapshot: () => Promise<void>;
      eventSourceFactory?: EventSourceFactory;
      queryKeyForEvent?: (event: ApiEvent) => QueryKey | undefined;
    },
  ) {}

  start() {
    this.stopped = false;
    this.connect();
    return () => this.stop();
  }

  stop() {
    this.stopped = true;
    this.source?.close();
    this.source = null;
  }

  private connect() {
    if (this.stopped) return;
    const factory = this.options.eventSourceFactory ?? ((url) => new EventSource(url));
    const source = factory(this.options.url);
    this.source = source;
    for (const eventType of ["launch", "token", "reorg"]) {
      source.addEventListener(eventType, (event) => this.handleEvent(eventType, event));
    }
    source.addEventListener("error", () => {
      void this.reconnect();
    });
  }

  private handleEvent(eventType: string, event: MessageEvent<string>) {
    let data: unknown;
    try {
      data = JSON.parse(event.data) as unknown;
    } catch {
      return;
    }
    if (!isApiEvent(eventType, data)) return;
    const queryKey = this.options.queryKeyForEvent?.({ event: eventType, data } as ApiEvent);
    if (queryKey) void this.options.queryClient.invalidateQueries({ queryKey });
  }

  private async reconnect() {
    if (this.reconnecting || this.stopped) return;
    this.reconnecting = true;
    this.source?.close();
    this.source = null;
    try {
      // Ordering is intentional: refill canonical REST state before accepting new hints.
      await this.options.refetchSnapshot();
      if (!this.stopped) this.connect();
    } finally {
      this.reconnecting = false;
    }
  }
}

function isApiEvent(event: string, data: unknown): data is ApiEvent["data"] {
  if (event !== "launch" && event !== "token" && event !== "reorg") return false;
  return (
    typeof data === "object" &&
    data !== null &&
    typeof (data as { chain_id?: unknown }).chain_id === "number" &&
    typeof (data as { deployment_id?: unknown }).deployment_id === "string"
  );
}
