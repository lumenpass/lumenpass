import { afterEach, describe, expect, it, vi } from "vitest";

type MessagePayload = Record<string, unknown>;

describe("passkey page credential serialization", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.resetModules();
  });

  it("serializes a created credential without invoking native methods on a synthetic object", async () => {
    const listeners = new Set<(event: { source: unknown; data: MessagePayload }) => void>();
    const page = {
      location: { hostname: "admin.boltai.com" },
      addEventListener: (_type: string, listener: (event: { source: unknown; data: MessagePayload }) => void) => listeners.add(listener),
      removeEventListener: (_type: string, listener: (event: { source: unknown; data: MessagePayload }) => void) => listeners.delete(listener),
      postMessage(payload: MessagePayload) {
        if (payload.type === "PASSKEY_CREATE") {
          queueMicrotask(() => page.postMessage({
            LUMENPASS_PK: true,
            requestId: payload.requestId,
            credential: {
              credentialId: [1, 2, 3],
              clientDataJSON: [4, 5],
              attestationObject: [6, 7],
              authData: [8, 9],
              publicKey: [12, 13],
            },
          }));
        }
        for (const listener of [...listeners]) listener({ source: page, data: payload });
      },
    };

    class BrowserCredential {
      toJSON() { throw new TypeError("Illegal invocation"); }
    }
    class BrowserAttestationResponse {
      toJSON() { throw new TypeError("Illegal invocation"); }
    }
    class BrowserAssertionResponse {
      toJSON() { throw new TypeError("Illegal invocation"); }
    }
    const credentials = {
      create: vi.fn(async (_options?: CredentialCreationOptions): Promise<Credential | null> => null),
      get: vi.fn(async (_options?: CredentialRequestOptions): Promise<Credential | null> => null),
    };
    vi.stubGlobal("window", page);
    vi.stubGlobal("navigator", { credentials });
    vi.stubGlobal("PublicKeyCredential", BrowserCredential);
    vi.stubGlobal("AuthenticatorAttestationResponse", BrowserAttestationResponse);
    vi.stubGlobal("AuthenticatorAssertionResponse", BrowserAssertionResponse);

    await import("./passkey-page" as string);
    const credential = await credentials.create({ publicKey: {
      challenge: new Uint8Array([10]),
      rp: { id: "boltai.com", name: "BoltAI" },
      user: { id: new Uint8Array([11]), name: "test@example.com", displayName: "Test" },
      pubKeyCredParams: [{ type: "public-key", alg: -7 }],
    } } as CredentialCreationOptions) as PublicKeyCredential;

    expect(credential.toJSON()).toMatchObject({
      id: "AQID",
      rawId: "AQID",
      type: "public-key",
      response: {
        clientDataJSON: "BAU",
        attestationObject: "Bgc",
        authenticatorData: "CAk",
        publicKey: "DA0",
      },
    });
    expect(JSON.parse(JSON.stringify(credential))).toMatchObject({ id: "AQID" });
  });
});
