import { describe, expect, it } from "vitest";
import { isSensitiveFinancialField } from "./sensitive-financial-field";

describe("isSensitiveFinancialField", () => {
  it.each([
    ["Card Number", "credit-card"],
    ["Number", "credit-card"],
    ["Account Number", "unknown"],
    ["Routing Number", "unknown"],
    ["IBAN", "unknown"],
    ["SWIFT / BIC", "unknown"],
  ])("masks %s on %s items", (label, kind) => {
    expect(isSensitiveFinancialField(label, kind)).toBe(true);
  });

  it.each(["Account Holder", "Account Type", "Issuing Bank", "Expiry Date"])(
    "leaves %s readable",
    (label) => expect(isSensitiveFinancialField(label, "unknown")).toBe(false),
  );
});
