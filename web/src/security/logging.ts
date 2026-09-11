const SENSITIVE_KEY =
  /authorization|token|signature|private|secret|password|cookie|credential|access|rpc.?url|api.?key/i;
const SENSITIVE_VALUE = /(bearer\s+|0x[0-9a-f]{64,}|-----begin|sk_live_|pk_live_|jwt)/i;

export function redactLogValue(value: unknown, key = ""): unknown {
  if (SENSITIVE_KEY.test(key)) return "[REDACTED]";
  if (typeof value === "string") {
    if (SENSITIVE_VALUE.test(value)) return "[REDACTED]";
    return value.length > 500 ? `${value.slice(0, 497)}...` : value;
  }
  if (value instanceof Error)
    return { name: value.name || "Error", message: redactLogValue(value.message, "message") };
  if (Array.isArray(value)) return value.map((item) => redactLogValue(item));
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([entryKey, entryValue]) => [
        entryKey,
        redactLogValue(entryValue, entryKey),
      ]),
    );
  }
  return value;
}

export function safeLog(event: string, context: Record<string, unknown> = {}) {
  // Context is scrubbed before it reaches the console; callers must not pass auth material in URLs.
  if (typeof console !== "undefined") console.info(`[launchpad] ${event}`, redactLogValue(context));
}

export function scrubTelemetry(error: unknown) {
  return redactLogValue(error, "error");
}
