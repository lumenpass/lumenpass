import { describe, expect, it } from "vitest";
import { parseCardExpiry } from "./credit-card-fields";

describe("credit card expiry parsing", () => {
  it("accepts common slash and dash formats", () => {
    expect(parseCardExpiry("03/30")).toEqual({ month: "03", year: "2030" });
    expect(parseCardExpiry("03/2030")).toEqual({ month: "03", year: "2030" });
    expect(parseCardExpiry("2030-03")).toEqual({ month: "03", year: "2030" });
  });

  it("accepts display-formatted expiry values with spaces", () => {
    expect(parseCardExpiry("03 / 30")).toEqual({ month: "03", year: "2030" });
    expect(parseCardExpiry("3 / 2030")).toEqual({ month: "03", year: "2030" });
    expect(parseCardExpiry("03 30")).toEqual({ month: "03", year: "2030" });
  });

  it("rejects invalid months", () => {
    expect(parseCardExpiry("30 / 03")).toBeNull();
    expect(parseCardExpiry("00 / 30")).toBeNull();
  });
});
