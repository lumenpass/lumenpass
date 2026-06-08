import { describe, expect, it } from "vitest";
import {
  getCredentialIdentifierKind,
  isCredentialIdentifierPurpose,
  isOneTimeCodeAutocomplete,
  isOneTimeCodeDescriptor,
} from "./field-purpose";

describe("one-time code field detection", () => {
  it("detects autocomplete one-time-code even with section tokens", () => {
    expect(isOneTimeCodeAutocomplete("one-time-code")).toBe(true);
    expect(isOneTimeCodeAutocomplete("section-login one-time-code")).toBe(true);
  });

  it("detects email/SMS verification code copy", () => {
    expect(isOneTimeCodeDescriptor("6-digit verification code Digit 1")).toBe(true);
    expect(isOneTimeCodeDescriptor("Enter the SMS code")).toBe(true);
    expect(isOneTimeCodeDescriptor("one-time password")).toBe(true);
    expect(isOneTimeCodeDescriptor("2FA authentication code")).toBe(true);
  });

  it("does not treat credit-card verification fields as OTP fields", () => {
    expect(isOneTimeCodeDescriptor("Card Verification Code")).toBe(false);
    expect(isOneTimeCodeDescriptor("Credit card security code")).toBe(false);
    expect(isOneTimeCodeDescriptor("CVV code")).toBe(false);
  });

  it("identifies email/username credential fields even when their ids contain otp", () => {
    expect(isOneTimeCodeDescriptor("otp-email-input")).toBe(true);

    expect(isCredentialIdentifierPurpose("email", "email")).toBe(true);
    expect(isCredentialIdentifierPurpose("text", "section-login email")).toBe(true);
    expect(isCredentialIdentifierPurpose("text", "section-login username")).toBe(true);
  });

  it("does not identify ordinary text or OTP fields as credential identifiers", () => {
    expect(isCredentialIdentifierPurpose("text", "")).toBe(false);
    expect(isCredentialIdentifierPurpose("text", "one-time-code")).toBe(false);
  });

  it("classifies identifier fields by email vs username intent", () => {
    expect(getCredentialIdentifierKind("email", "", "work email")).toBe("email");
    expect(getCredentialIdentifierKind("text", "section-login username", "username")).toBe("username");
    expect(getCredentialIdentifierKind("text", "", "username or email")).toBe("any");
    expect(getCredentialIdentifierKind("text", "", "account login")).toBe("any");
  });
});
