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
  private retryTimer: ReturnType<typeof setTimeout> | null = null;
  private retryAttempt = 0;
  private recoveryAbortController: AbortController | null = null;
  constructor(
    private readonly options: {
      url: string;
      queryClient: Pick<QueryClient, "invalidateQueries">;
      refetchSnapshot: (signal?: AbortSignal) => Promise<void>;
      eventSourceFactory?: EventSourceFactory;
      queryKeyForEvent?: (event: ApiEvent) => QueryKey | undefined;
      retry?: { maxAttempts?: number; baseDelayMs?: number; maxDelayMs?: number };
      onRecoveryExhausted?: () => void;
    },
  ) {}

  start() {
    this.stopped = false;
    this.connect();
    return () => this.stop();
  }

  stop() {
    this.stopped = true;
    this.recoveryAbortController?.abort();
    this.recoveryAbortController = null;
    if (this.retryTimer) clearTimeout(this.retryTimer);
    this.retryTimer = null;
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
    this.scheduleRecovery();
    this.reconnecting = false;
  }

  private scheduleRecovery() {
    if (this.stopped || this.retryTimer) return;
    const retry = this.options.retry ?? {};
    const maxAttempts = retry.maxAttempts ?? 5;
    if (this.retryAttempt >= maxAttempts) {
      this.options.onRecoveryExhausted?.();
      return;
    }
    const baseDelay = retry.baseDelayMs ?? 250;
    const maxDelay = retry.maxDelayMs ?? 5_000;
    const delay =
      this.retryAttempt === 0 ? 0 : Math.min(maxDelay, baseDelay * 2 ** (this.retryAttempt - 1));
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null;
      void this.performRecovery();
    }, delay);
  }

  private async performRecovery() {
    if (this.stopped) return;
    const abortController = new AbortController();
    this.recoveryAbortController = abortController;
    try {
      // Ordering is intentional: refill canonical REST state before accepting new hints.
      await this.options.refetchSnapshot(abortController.signal);
      this.retryAttempt = 0;
      if (!this.stopped) this.connect();
    } catch {
      this.retryAttempt += 1;
      this.scheduleRecovery();
    } finally {
      if (this.recoveryAbortController === abortController) this.recoveryAbortController = null;
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
