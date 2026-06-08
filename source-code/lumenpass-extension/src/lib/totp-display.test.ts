import { describe, expect, it } from "vitest";
import {
  buildFeaturedTotps,
  isCanonicalTotpStorageLabel,
  totpDisplayIdentity,
} from "./totp-display";

describe("TOTP display fields", () => {
  it("uses the canonical desktop TOTP instead of showing storage fields twice", () => {
    expect(buildFeaturedTotps({
      standardTotp: "181490",
      customFields: [
        { label: "OTP", value: "181490" },
        { label: "OTPAuth", value: "otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP" },
      ],
    })).toEqual([
      { key: "__std_totp", label: "one-time password", totp: "181490" },
    ]);
  });

  it("still shows an OTP custom field when desktop did not send a canonical TOTP", () => {
    expect(buildFeaturedTotps({
      standardTotp: "",
      customFields: [{ label: "OTP", value: "181490" }],
    })).toEqual([
      { key: "custom_totp:0:OTP", label: "OTP", totp: "181490", customFieldIndex: 0 },
    ]);
  });

  it("keeps additional non-storage TOTP fields when their values are distinct", () => {
    expect(buildFeaturedTotps({
      standardTotp: "111111",
      customFields: [
        { label: "OTP", value: "111111" },
        { label: "backup_totp", value: "222222" },
      ],
    })).toEqual([
      { key: "__std_totp", label: "one-time password", totp: "111111" },
      { key: "custom_totp:1:backup_totp", label: "backup_totp", totp: "222222", customFieldIndex: 1 },
    ]);
  });

  it("normalizes equivalent otpauth URIs by secret and generation settings", () => {
    expect(totpDisplayIdentity("otpauth://totp/A?secret=JBSW Y3DP EHPK3PXP&issuer=A")).toBe(
      totpDisplayIdentity("otpauth://totp/B?secret=JBSWY3DPEHPK3PXP&period=30&digits=6&algorithm=SHA1"),
    );
  });

  it("recognizes common canonical TOTP storage labels", () => {
    expect(isCanonicalTotpStorageLabel("OTP")).toBe(true);
    expect(isCanonicalTotpStorageLabel("OTPAuth")).toBe(true);
    expect(isCanonicalTotpStorageLabel("time-otp")).toBe(true);
    expect(isCanonicalTotpStorageLabel("backup_totp")).toBe(false);
  });
});
