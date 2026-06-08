import { describe, expect, it } from "vitest";
import { findBestSelectOptionIndex } from "./select-option-match";

describe("findBestSelectOptionIndex", () => {
  it("prefers the exact state name over short code substrings", () => {
    const options = [
      { text: "Nebraska", value: "NE" },
      { text: "New York", value: "NY" },
    ];

    expect(findBestSelectOptionIndex(options, "New York")).toBe(1);
  });

  it("prefers the exact country name over short code substrings", () => {
    const options = [
      { text: "Austria", value: "AT" },
      { text: "United States", value: "US" },
    ];

    expect(findBestSelectOptionIndex(options, "United States")).toBe(1);
  });

  it("still supports exact short-code matches when that is the target", () => {
    const options = [
      { text: "Austria", value: "AT" },
      { text: "United States", value: "US" },
    ];

    expect(findBestSelectOptionIndex(options, "US")).toBe(1);
  });
});
