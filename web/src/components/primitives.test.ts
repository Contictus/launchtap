import { describe, expect, it } from "vitest";
import { getNextTabIndex } from "./primitives";

describe("Tabs keyboard navigation", () => {
  const tabs = [{ disabled: false }, { disabled: true }, { disabled: false }];

  it("wraps between enabled tabs and skips disabled tabs", () => {
    expect(getNextTabIndex(tabs, 0, "ArrowRight")).toBe(2);
    expect(getNextTabIndex(tabs, 2, "ArrowRight")).toBe(0);
    expect(getNextTabIndex(tabs, 0, "ArrowLeft")).toBe(2);
  });

  it("supports Home and End", () => {
    expect(getNextTabIndex(tabs, 2, "Home")).toBe(0);
    expect(getNextTabIndex(tabs, 0, "End")).toBe(2);
  });
});
