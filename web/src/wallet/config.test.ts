import { describe, expect, it } from "vitest";
import { publicConfiguration } from "@/config/public";
import { createWeb3Config } from "./config";

describe("wallet configuration", () => {
  it("does not construct a provider config when public configuration is unavailable", () => {
    expect(createWeb3Config(publicConfiguration({}))).toBeNull();
  });
});
