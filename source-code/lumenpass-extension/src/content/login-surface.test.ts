/**
 * Unit tests for the pure login-surface detector.
 *
 * The detector is the single gate that decides whether the LumenPass
 * extension is allowed to display a passkey or autofill prompt on the
 * current page. A false-positive here is a critical UX bug because it
 * surfaces a "Sign in with passkey" picker on already-authenticated pages
 * (homepages, dashboards, admin consoles, …).
 *
 * The test suite is deliberately exhaustive about authenticated pages:
 * the regression that motivated the fix was `console.cloud.google.com/auth/clients`,
 * a logged-in admin URL whose path contained `/auth/` and incorrectly
 * matched the previous URL-only heuristic.
 */

import { describe, expect, it } from "vitest";
import {
  decideLoginSurface,
  isLikelyLoginSurfaceFromSignals,
  isLoginPath,
  isPasskeyManagementText,
  type LoginSurfaceSignals,
} from "./login-surface";

function makeSignals(overrides: Partial<LoginSurfaceSignals> = {}): LoginSurfaceSignals {
  return {
    pathname: "/",
    hostname: "example.com",
    pageTitle: "",
    passwordFieldCount: 0,
    usernameFieldCount: 0,
    otpFieldCount: 0,
    hasLoginActionButton: false,
    hasPasskeyActionButton: false,
    pageTextSample: "",
    detectedLoggedInEmail: "",
    isRegistrationSurface: false,
    isPasskeyManagementPage: false,
    ...overrides,
  };
}

describe("isLoginPath", () => {
  it("matches canonical login routes", () => {
    expect(isLoginPath("/login")).toBe(true);
    expect(isLoginPath("/login/")).toBe(true);
    expect(isLoginPath("/signin")).toBe(true);
    expect(isLoginPath("/sign-in")).toBe(true);
    expect(isLoginPath("/users/sign_in")).toBe(true);
    expect(isLoginPath("/account/login")).toBe(true);
    expect(isLoginPath("/sso")).toBe(true);
    expect(isLoginPath("/auth/login")).toBe(true);
    expect(isLoginPath("/auth/signin")).toBe(true);
    expect(isLoginPath("/oauth/authorize")).toBe(true);
  });

  it("does not treat registration routes as login routes", () => {
    expect(isLoginPath("/signup")).toBe(false);
    expect(isLoginPath("/sign-up")).toBe(false);
    expect(isLoginPath("/registration-email")).toBe(false);
  });

  it("does NOT match generic /auth admin paths (regression: console.cloud.google.com/auth/clients)", () => {
    expect(isLoginPath("/auth/clients")).toBe(false);
    expect(isLoginPath("/auth/branding")).toBe(false);
    expect(isLoginPath("/auth/audience")).toBe(false);
    expect(isLoginPath("/auth/data-access")).toBe(false);
    expect(isLoginPath("/auth/verification-center")).toBe(false);
    expect(isLoginPath("/auth/settings")).toBe(false);
  });

  it("does not match unrelated paths", () => {
    expect(isLoginPath("/")).toBe(false);
    expect(isLoginPath("/dashboard")).toBe(false);
    expect(isLoginPath("/users/123/profile")).toBe(false);
    expect(isLoginPath("")).toBe(false);
  });
});

describe("isPasskeyManagementText", () => {
  it("identifies passkey-management copy", () => {
    expect(isPasskeyManagementText("here you can add a passkey to your account")).toBe(true);
    expect(isPasskeyManagementText("manage passkeys")).toBe(true);
    expect(isPasskeyManagementText("your passkeys")).toBe(true);
  });

  it("ignores generic content", () => {
    expect(isPasskeyManagementText("welcome to my blog")).toBe(false);
    expect(isPasskeyManagementText("")).toBe(false);
  });
});

describe("decideLoginSurface", () => {
  describe("authenticated pages – MUST never show a prompt", () => {
    it("regression: console.cloud.google.com/auth/clients with logged-in email", () => {
      // This is the exact scenario reported by the user.
      const decision = decideLoginSurface(makeSignals({
        hostname: "console.cloud.google.com",
        pathname: "/auth/clients",
        passwordFieldCount: 0,
        usernameFieldCount: 0,
        hasLoginActionButton: true, // "Request access" button is present
        pageTextSample: "you need additional access to the project: lumenpass",
        detectedLoggedInEmail: "trantuan@example.com",
      }));
      expect(decision).toEqual({ isLoginSurface: false, reason: "logged-in-email" });
    });

    it("homepage with no login signals", () => {
      const decision = decideLoginSurface(makeSignals({
        hostname: "lumenpass.app",
        pathname: "/",
      }));
      expect(decision.isLoginSurface).toBe(false);
    });

    it("dashboard with logged-in email", () => {
      const decision = decideLoginSurface(makeSignals({
        pathname: "/dashboard",
        detectedLoggedInEmail: "user@example.com",
        hasLoginActionButton: true,
      }));
      expect(decision).toEqual({ isLoginSurface: false, reason: "logged-in-email" });
    });

    it("logged-in email overrides a visible password field (e.g. change-password page)", () => {
      const decision = decideLoginSurface(makeSignals({
        pathname: "/account/security",
        passwordFieldCount: 1,
        detectedLoggedInEmail: "user@example.com",
      }));
      expect(decision.isLoginSurface).toBe(false);
      expect(decision.reason).toBe("logged-in-email");
    });

    it("passkey-management settings page", () => {
      const decision = decideLoginSurface(makeSignals({
        pathname: "/account/security/passkeys",
        pageTextSample: "your passkeys – add a passkey to sign in faster next time",
      }));
      expect(decision.isLoginSurface).toBe(false);
      expect(decision.reason).toBe("passkey-management-page");
    });

    it("admin /auth/* page WITHOUT a password input or username field", () => {
      // No logged-in email is detected, but there's also no actual login
      // form. Under the OLD logic the URL alone would have triggered a
      // passkey prompt. The new logic requires a form signal.
      const decision = decideLoginSurface(makeSignals({
        pathname: "/auth/clients",
        hasLoginActionButton: true, // generic action button on the page
        pageTextSample: "missing or blocked permissions",
      }));
      expect(decision.isLoginSurface).toBe(false);
    });

    it("documentation page that mentions sign-in but has no form", () => {
      const decision = decideLoginSurface(makeSignals({
        pathname: "/docs/authentication",
        pageTextSample: "users can sign in to your application using passkeys",
      }));
      expect(decision.isLoginSurface).toBe(false);
    });

    it("Trello board reload with Google UI text is not a login surface", () => {
      const decision = decideLoginSurface(makeSignals({
        hostname: "trello.com",
        pathname: "/b/abc123/product-board",
        hasLoginActionButton: true,
        pageTextSample: "blocked add a card google drive power-up mobile bugs high extension",
      }));
      expect(decision.isLoginSurface).toBe(false);
    });

    it("OTP-only verification page is not a credential autofill surface", () => {
      const decision = decideLoginSurface(makeSignals({
        hostname: "www.lumenpass.app",
        pathname: "/login",
        otpFieldCount: 6,
        hasLoginActionButton: true,
        pageTextSample: "enter verification code 6-digit verification code verify and sign in",
      }));
      expect(decision).toEqual({ isLoginSurface: false, reason: "otp-challenge" });
    });

    it("registration page with password fields is not a login autofill surface", () => {
      const decision = decideLoginSurface(makeSignals({
        hostname: "fill.dev",
        pathname: "/form/registration-email",
        passwordFieldCount: 0,
        usernameFieldCount: 0,
        hasLoginActionButton: false,
        isRegistrationSurface: true,
        pageTextSample: "register email password confirm password register",
      }));
      expect(decision).toEqual({ isLoginSurface: false, reason: "registration-surface" });
    });
  });

  describe("unauthenticated login pages – MUST allow the prompt", () => {
    it("classic /login page with username + password", () => {
      const decision = decideLoginSurface(makeSignals({
        pathname: "/login",
        passwordFieldCount: 1,
        usernameFieldCount: 1,
        hasLoginActionButton: true,
        pageTextSample: "log in to acme",
      }));
      expect(decision.isLoginSurface).toBe(true);
      expect(decision.reason).toBe("password-field");
    });

    it("Google-style /signin with username only (passwordless)", () => {
      const decision = decideLoginSurface(makeSignals({
        hostname: "accounts.google.com",
        pathname: "/signin/v2/identifier",
        usernameFieldCount: 1,
        hasLoginActionButton: true,
        pageTextSample: "sign in to continue to gmail",
      }));
      expect(decision.isLoginSurface).toBe(true);
    });

    it("/sso landing page with a 'Sign in with passkey' button", () => {
      const decision = decideLoginSurface(makeSignals({
        pathname: "/sso",
        hasPasskeyActionButton: true,
        hasLoginActionButton: true,
      }));
      expect(decision.isLoginSurface).toBe(true);
    });

    it("/auth/login (a real login page nested under /auth)", () => {
      const decision = decideLoginSurface(makeSignals({
        pathname: "/auth/login",
        passwordFieldCount: 1,
        usernameFieldCount: 1,
      }));
      expect(decision.isLoginSurface).toBe(true);
      expect(decision.reason).toBe("password-field");
    });

    it("welcome-back screen with no /login URL but strong text + form", () => {
      const decision = decideLoginSurface(makeSignals({
        pathname: "/",
        usernameFieldCount: 1,
        hasLoginActionButton: true,
        pageTextSample: "welcome back. enter your password to continue.",
      }));
      expect(decision.isLoginSurface).toBe(true);
    });

    it("Cursor-style email-first sign-in page on / with a Sign in title", () => {
      const decision = decideLoginSurface(makeSignals({
        hostname: "authenticator.cursor.sh",
        pathname: "/",
        pageTitle: "sign in",
        usernameFieldCount: 1,
        hasLoginActionButton: true,
        pageTextSample: "sign in email continue continue with google continue with github",
      }));
      expect(decision.isLoginSurface).toBe(true);
      expect(decision.reason).toBe("login-text");
    });
  });

  describe("edge cases", () => {
    it("returns false for a completely blank page", () => {
      expect(decideLoginSurface(makeSignals()).isLoginSurface).toBe(false);
    });

    it("`isLikelyLoginSurfaceFromSignals` mirrors `decideLoginSurface`", () => {
      const loginSignals = makeSignals({ pathname: "/login", passwordFieldCount: 1 });
      const authedSignals = makeSignals({
        pathname: "/auth/clients",
        detectedLoggedInEmail: "u@e.com",
      });
      expect(isLikelyLoginSurfaceFromSignals(loginSignals)).toBe(true);
      expect(isLikelyLoginSurfaceFromSignals(authedSignals)).toBe(false);
    });

    it("treats empty detectedLoggedInEmail as 'no email'", () => {
      const decision = decideLoginSurface(makeSignals({
        pathname: "/login",
        passwordFieldCount: 1,
        detectedLoggedInEmail: "",
      }));
      expect(decision.isLoginSurface).toBe(true);
    });

    it("ignores URL keywords without any DOM form signal", () => {
      // A blog post titled "/articles/login-best-practices" should never
      // trigger a passkey prompt.
      const decision = decideLoginSurface(makeSignals({
        pathname: "/articles/login-best-practices",
        pageTextSample: "an article about login systems",
      }));
      expect(decision.isLoginSurface).toBe(false);
    });

    it("does not trust a Sign in title without a visible auth field", () => {
      const decision = decideLoginSurface(makeSignals({
        pathname: "/",
        pageTitle: "sign in",
        hasLoginActionButton: true,
      }));
      expect(decision.isLoginSurface).toBe(false);
    });
  });

  describe("multi-site authenticated regressions", () => {
    const authedScenarios: Array<{ name: string; signals: Partial<LoginSurfaceSignals> }> = [
      {
        name: "GitHub /settings/keys (logged in)",
        signals: {
          hostname: "github.com",
          pathname: "/settings/keys",
          detectedLoggedInEmail: "octocat@github.com",
          hasLoginActionButton: true,
        },
      },
      {
        name: "AWS IAM /iam/home with logged-in chrome",
        signals: {
          hostname: "us-east-1.console.aws.amazon.com",
          pathname: "/iam/home",
          detectedLoggedInEmail: "admin@acme.com",
        },
      },
      {
        name: "GitLab /-/profile/account",
        signals: {
          hostname: "gitlab.com",
          pathname: "/-/profile/account",
          detectedLoggedInEmail: "dev@acme.com",
        },
      },
      {
        name: "Notion homepage when authenticated",
        signals: {
          hostname: "www.notion.so",
          pathname: "/",
          detectedLoggedInEmail: "team@acme.com",
        },
      },
    ];

    for (const scenario of authedScenarios) {
      it(`never prompts on: ${scenario.name}`, () => {
        const decision = decideLoginSurface(makeSignals(scenario.signals));
        expect(decision.isLoginSurface).toBe(false);
      });
    }
  });
});
