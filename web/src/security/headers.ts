const localHosts = new Set(["localhost", "127.0.0.1", "[::1]"]);

function originOf(value: string | undefined) {
  if (!value?.trim()) return null;
  try {
    const url = new URL(value);
    if (url.username || url.password || url.search || url.hash) return null;
    if (url.protocol !== "https:" && !(url.protocol === "http:" && localHosts.has(url.hostname)))
      return null;
    return url.origin;
  } catch {
    return null;
  }
}

/** Build the production policy from reviewed public endpoints, never from an unrestricted scheme. */
export function contentSecurityPolicy(env: Record<string, string | undefined> = {}) {
  const origins = [
    originOf(env.NEXT_PUBLIC_API_BASE_URL),
    originOf(env.NEXT_PUBLIC_RPC_URL),
  ].filter((origin): origin is string => Boolean(origin));
  const connect = [
    "'self'",
    ...origins,
    "https://*.privy.io",
    "wss://*.privy.io",
    "https://*.walletconnect.com",
    "wss://*.walletconnect.com",
  ];
  // Token metadata accepts user-supplied HTTPS image URLs. SafeImage still
  // rejects non-HTTPS/non-local URLs and uses referrerPolicy=no-referrer.
  const images = ["'self'", "data:", "blob:", "https:", ...origins];
  return [
    "default-src 'self'",
    "base-uri 'self'",
    "object-src 'none'",
    "frame-ancestors 'none'",
    "form-action 'self'",
    "script-src 'self' 'unsafe-inline'",
    "style-src 'self' 'unsafe-inline'",
    `img-src ${images.join(" ")}`,
    "font-src 'self' data:",
    `connect-src ${connect.join(" ")}`,
    "frame-src 'self' https://*.privy.io https://*.walletconnect.com",
    "worker-src 'self' blob:",
  ].join("; ");
}

export const securityHeaders = (env: Record<string, string | undefined> = {}) => [
  { key: "Content-Security-Policy", value: contentSecurityPolicy(env) },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=(), payment=()" },
];

export const cacheHeaders = [
  { key: "Cache-Control", value: "no-store, max-age=0" },
  { key: "Vary", value: "Accept-Encoding" },
];

export const immutableAssetHeaders = [
  { key: "Cache-Control", value: "public, max-age=31536000, immutable" },
];
