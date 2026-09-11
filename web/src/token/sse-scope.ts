import type { ApiEvent } from "@/api/types";
import { parseTokenAddress } from "./address";

export function isTokenEventForAddress(event: ApiEvent, address: string) {
  const token = "token" in event.data ? event.data.token : undefined;
  return Boolean(token && parseTokenAddress(token)?.toLowerCase() === address.toLowerCase());
}
