/** Accept only a canonical EVM address; malformed route segments fail closed. */
export function parseTokenAddress(value: string | null | undefined): `0x${string}` | null {
  if (!value || !/^0x[0-9a-fA-F]{40}$/.test(value)) return null;
  return value.toLowerCase() as `0x${string}`;
}

export function shortAddress(address: string, edge = 6) {
  if (!parseTokenAddress(address) || edge < 2) return "Unavailable";
  return `${address.slice(0, edge + 2)}…${address.slice(-edge)}`;
}
