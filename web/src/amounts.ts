const DECIMAL = /^\d+(?:\.\d+)?$/;
const INTEGER = /^\d+$/;

export function parseBaseUnits(value: string, decimals = 18): bigint {
  if (!Number.isInteger(decimals) || decimals < 0 || decimals > 255 || !INTEGER.test(value))
    throw new Error("Invalid integer amount");
  return BigInt(value);
}

export function parseDecimal(value: string, decimals = 18): bigint {
  if (!Number.isInteger(decimals) || decimals < 0 || decimals > 255 || !DECIMAL.test(value.trim()))
    throw new Error("Invalid decimal amount");
  const normalized = value.trim();
  const [whole = "", fraction = ""] = normalized.split(".");
  if (fraction.length > decimals) throw new Error("Too many decimal places");
  return (
    BigInt(whole) * 10n ** BigInt(decimals) +
    BigInt((fraction + "0".repeat(decimals)).slice(0, decimals) || "0")
  );
}

export function formatBaseUnits(
  value: bigint,
  decimals = 18,
  maxFractionDigits = decimals,
): string {
  if (
    !Number.isInteger(decimals) ||
    decimals < 0 ||
    decimals > 255 ||
    !Number.isInteger(maxFractionDigits) ||
    maxFractionDigits < 0 ||
    maxFractionDigits > decimals
  )
    throw new Error("Invalid decimals");
  if (value < 0n) return `-${formatBaseUnits(-value, decimals, maxFractionDigits)}`;
  const scale = 10n ** BigInt(decimals);
  const whole = value / scale;
  if (decimals === 0 || maxFractionDigits === 0) return whole.toString();
  const fraction = (value % scale)
    .toString()
    .padStart(decimals, "0")
    .slice(0, maxFractionDigits)
    .replace(/0+$/, "");
  return fraction ? `${whole}.${fraction}` : whole.toString();
}

export function formatDisplayAmount(value: bigint, decimals = 18, maxFractionDigits = 4): string {
  const raw = formatBaseUnits(value, decimals, maxFractionDigits);
  const [whole = "", fraction] = raw.split(".");
  const sign = whole.startsWith("-") ? "-" : "";
  const digits = sign ? whole.slice(1) : whole;
  const grouped = digits.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return fraction ? `${sign}${grouped}.${fraction}` : `${sign}${grouped}`;
}
