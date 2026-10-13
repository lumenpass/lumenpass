import { describe, expect, it } from "vitest";
import { selectCredentialPair } from "./credential-pair";

type Field = { name: string; kind: "email" | "password"; form: object | null };

describe("selectCredentialPair", () => {
  it("keeps both credentials in the sign-in form when registration is also present", () => {
    const signIn = {};
    const registration = {};
    const signInEmail: Field = { name: "sign-in email", kind: "email", form: signIn };
    const signInPassword: Field = { name: "sign-in password", kind: "password", form: signIn };
    const registrationEmail: Field = { name: "registration email", kind: "email", form: registration };
    const registrationPassword: Field = { name: "registration password", kind: "password", form: registration };
    const fields = [signInEmail, signInPassword, registrationEmail, registrationPassword];

    const pair = selectCredentialPair(
      fields,
      signInPassword,
      (field) => field.kind === "email",
      (field) => field.kind === "password",
      (field) => field.kind === "email",
    );

    expect(pair).toEqual({ username: signInEmail, password: signInPassword });
  });

  it("never falls back to an email in another form", () => {
    const signIn = {};
    const registration = {};
    const signInPassword: Field = { name: "sign-in password", kind: "password", form: signIn };
    const registrationEmail: Field = { name: "registration email", kind: "email", form: registration };

    const pair = selectCredentialPair(
      [registrationEmail, signInPassword],
      signInPassword,
      (field) => field.kind === "email",
      (field) => field.kind === "password",
      (field) => field.kind === "email",
    );

    expect(pair).toEqual({ username: null, password: signInPassword });
  });

  it("keeps a focused sign-in email paired with its password beside an identity form", () => {
    const signIn = {};
    const identity = {};
    const signInEmail: Field = { name: "sign-in email", kind: "email", form: signIn };
    const signInPassword: Field = { name: "sign-in password", kind: "password", form: signIn };
    const identityEmail: Field = { name: "identity email", kind: "email", form: identity };

    const pair = selectCredentialPair(
      [signInEmail, signInPassword, identityEmail],
      signInEmail,
      (field) => field.kind === "email",
      (field) => field.kind === "password",
      (field) => field.kind === "email",
    );

    expect(pair).toEqual({ username: signInEmail, password: signInPassword });
  });
});
