import { describe, expect, it } from "vitest";
import { ADDRESS_FIELD_MATCHERS } from "./address-field-match";

describe("address field detection", () => {
  it("recognizes prefixed city, state, and country fields on shipping forms", () => {
    expect(ADDRESS_FIELD_MATCHERS.city.test("shipping_city shipping city")).toBe(true);
    expect(ADDRESS_FIELD_MATCHERS.city.test("shippingcity")).toBe(true);
    expect(ADDRESS_FIELD_MATCHERS.state.test("shipping_state shipping state")).toBe(true);
    expect(ADDRESS_FIELD_MATCHERS.state.test("shippingstate")).toBe(true);
    expect(ADDRESS_FIELD_MATCHERS.country.test("shipping_country shipping country")).toBe(true);
    expect(ADDRESS_FIELD_MATCHERS.country.test("shippingcountry")).toBe(true);
  });

  it("does not classify an unrelated email field as an address component", () => {
    for (const matcher of Object.values(ADDRESS_FIELD_MATCHERS)) {
      expect(matcher.test("identity_email email")).toBe(false);
    }
  });
});
