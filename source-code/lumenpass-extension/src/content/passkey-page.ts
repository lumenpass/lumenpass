/**
 * LumenPass Passkey Page-World Payload.
 *
 * This file is loaded directly into the page context (MAIN world) either:
 *   – via `chrome.scripting` MAIN-world content_script (Chrome), OR
 *   – as a `<script src="extension://…/content/passkey-page.js">` injected
 *     by `passkey-inject.ts` from the isolated world (Safari/Firefox).
 *
 * Loading via extension URL bypasses the page's CSP (unlike inline scripts),
 * so this works on strict-CSP pages like accounts.google.com.
 */

(function installLumenPassPasskeyInterceptor(): void {
  const LP = "LUMENPASS_PK";

  // Guard against double-injection (e.g. both content_scripts MAIN world AND
  // the src-based fallback firing).
  const w = window as unknown as { __LUMENPASS_PK_INSTALLED__?: boolean };
  if (w.__LUMENPASS_PK_INSTALLED__) return;
  w.__LUMENPASS_PK_INSTALLED__ = true;

  const origGet = navigator.credentials.get.bind(navigator.credentials);
  const origCreate = navigator.credentials.create.bind(navigator.credentials);

  let pendingGetPayload: object | null = null;
  let pendingCreatePayload: object | null = null;

  window.postMessage({ [LP]: true, type: "PASSKEY_PATCH_READY", direction: "page" }, "*");

  window.addEventListener("message", (evt: MessageEvent) => {
    if (
      evt.source !== window
      || !evt.data?.[LP]
      || evt.data.type !== "CONTENT_SCRIPT_READY"
    ) return;

    if (pendingGetPayload) {
      console.log("[LumenPass Passkey] content script ready – replaying buffered PASSKEY_GET");
      window.postMessage(pendingGetPayload, "*");
      pendingGetPayload = null;
    }

    if (pendingCreatePayload) {
      console.log("[LumenPass Passkey] content script ready – replaying buffered PASSKEY_CREATE");
      window.postMessage(pendingCreatePayload, "*");
      pendingCreatePayload = null;
    }
  });

  navigator.credentials.get = function (options?: CredentialRequestOptions) {
    if (!options?.publicKey) return origGet(options);

    return new Promise<Credential | null>((resolve, reject) => {
      const requestId = Math.random().toString(36).slice(2, 10);

      const pub = options.publicKey!;
      const challenge = Array.from(new Uint8Array(pub.challenge as ArrayBuffer));
      const rpId = pub.rpId ?? window.location.hostname;
      const allowCreds = (pub.allowCredentials ?? []).map((c) => ({
        type: c.type,
        id: Array.from(new Uint8Array(c.id as ArrayBuffer)),
        transports: c.transports,
      }));

      const handler = (evt: MessageEvent) => {
        if (evt.source !== window || !evt.data?.[LP] || evt.data.requestId !== requestId) return;
        if (evt.data.direction === "page") return;
        window.removeEventListener("message", handler);
        clearTimeout(timeout);
        pendingGetPayload = null;
        console.log("[LumenPass Passkey] received response from content script", evt.data);

        if (evt.data.cancel) {
          const { signal: _s, ...rest } = options as CredentialRequestOptions & { signal?: unknown };
          origGet(rest as CredentialRequestOptions).then(resolve).catch(reject);
          return;
        }
        if (evt.data.error) {
          reject(new DOMException(evt.data.error as string, "NotAllowedError"));
          return;
        }
        resolve(buildCredential(evt.data.credential));
      };

      window.addEventListener("message", handler);

      const timeout = setTimeout(() => {
        window.removeEventListener("message", handler);
        pendingGetPayload = null;
        const { signal: _s, ...rest } = options as CredentialRequestOptions & { signal?: unknown };
        origGet(rest as CredentialRequestOptions).then(resolve).catch(reject);
      }, 60_000);

      console.log("[LumenPass Passkey] patched credentials.get fired", { rpId, requestId, allowCreds });

      const payload = {
        [LP]: true,
        direction: "page",
        type: "PASSKEY_GET",
        requestId,
        publicKey: { challenge, rpId, allowCredentials: allowCreds, userVerification: pub.userVerification },
      };

      pendingGetPayload = payload;
      window.postMessage(payload, "*");
    });
  };

  navigator.credentials.create = function (options?: CredentialCreationOptions) {
    if (!options?.publicKey) return origCreate(options);

    return new Promise<Credential | null>((resolve, reject) => {
      const requestId = Math.random().toString(36).slice(2, 10);
      const pub = options.publicKey!;

      const challenge = Array.from(new Uint8Array(pub.challenge as ArrayBuffer));
      const rpId = pub.rp.id ?? window.location.hostname;
      const rpName = pub.rp.name ?? rpId;
      const userId = Array.from(new Uint8Array(pub.user.id as ArrayBuffer));

      const handler = (evt: MessageEvent) => {
        if (evt.source !== window || !evt.data?.[LP] || evt.data.requestId !== requestId) return;
        if (evt.data.direction === "page") return;
        window.removeEventListener("message", handler);
        clearTimeout(timeout);
        pendingCreatePayload = null;
        console.log("[LumenPass Passkey] create response received", evt.data);

        if (evt.data.cancel) {
          const { signal: _s, ...rest } = options as CredentialCreationOptions & { signal?: unknown };
          origCreate(rest as CredentialCreationOptions).then(resolve).catch(reject);
          return;
        }
        if (evt.data.error) {
          reject(new DOMException(evt.data.error as string, "NotAllowedError"));
          return;
        }
        resolve(buildAttestationCredential(evt.data.credential));
      };

      window.addEventListener("message", handler);
      const timeout = setTimeout(() => {
        window.removeEventListener("message", handler);
        pendingCreatePayload = null;
        const { signal: _s, ...rest } = options as CredentialCreationOptions & { signal?: unknown };
        origCreate(rest as CredentialCreationOptions).then(resolve).catch(reject);
      }, 60_000);

      console.log("[LumenPass Passkey] credentials.create fired", { rpId, userName: pub.user.name, requestId });

      const payload = {
        [LP]: true,
        direction: "page",
        type: "PASSKEY_CREATE",
        requestId,
        publicKey: {
          challenge,
          rpId,
          rpName,
          userId,
          userName: pub.user.name,
          userDisplayName: pub.user.displayName,
          pubKeyCredParams: pub.pubKeyCredParams,
          authenticatorSelection: pub.authenticatorSelection,
        },
      };

      pendingCreatePayload = payload;
      window.postMessage(payload, "*");
    });
  };

  function toBuffer(arr: number[]): ArrayBuffer {
    return new Uint8Array(arr).buffer;
  }

  function b64url(arr: number[]): string {
    return btoa(String.fromCharCode(...arr))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
  }

  function buildCredential(r: {
    credentialId: number[];
    clientDataJSON: number[];
    authenticatorData: number[];
    signature: number[];
    userHandle: number[] | null;
  }): PublicKeyCredential {
    const response = Object.create(
      AuthenticatorAssertionResponse.prototype,
    ) as AuthenticatorAssertionResponse;

    Object.defineProperties(response, {
      clientDataJSON: { value: toBuffer(r.clientDataJSON), enumerable: true, configurable: true },
      authenticatorData: { value: toBuffer(r.authenticatorData), enumerable: true, configurable: true },
      signature: { value: toBuffer(r.signature), enumerable: true, configurable: true },
      userHandle: { value: r.userHandle ? toBuffer(r.userHandle) : null, enumerable: true, configurable: true },
    });

    const adBuf = toBuffer(r.authenticatorData);
    (response as unknown as Record<string, unknown>).getAuthenticatorData = () => adBuf;
    (response as unknown as Record<string, unknown>).getPublicKey = () => null;
    (response as unknown as Record<string, unknown>).getPublicKeyAlgorithm = () => -7;
    (response as unknown as Record<string, unknown>).getTransports = () => ["internal"];

    const cred = Object.create(PublicKeyCredential.prototype) as PublicKeyCredential;

    Object.defineProperties(cred, {
      id: { value: b64url(r.credentialId), enumerable: true, configurable: true },
      rawId: { value: toBuffer(r.credentialId), enumerable: true, configurable: true },
      type: { value: "public-key", enumerable: true, configurable: true },
      authenticatorAttachment: { value: "platform", enumerable: true, configurable: true },
      response: { value: response, enumerable: true, configurable: true },
    });

    (cred as unknown as Record<string, unknown>).getClientExtensionResults = () => ({});

    console.log("[LumenPass Passkey] built credential id:", b64url(r.credentialId).slice(0, 12) + "…");
    return cred;
  }

  function buildAttestationCredential(r: {
    credentialId: number[];
    clientDataJSON: number[];
    attestationObject: number[];
    authData: number[];
  }): PublicKeyCredential {
    const response = Object.create(
      AuthenticatorAttestationResponse.prototype,
    ) as AuthenticatorAttestationResponse;

    const adBuf = toBuffer(r.authData);
    Object.defineProperties(response, {
      clientDataJSON: { value: toBuffer(r.clientDataJSON), enumerable: true, configurable: true },
      attestationObject: { value: toBuffer(r.attestationObject), enumerable: true, configurable: true },
    });
    (response as unknown as Record<string, unknown>).getAuthenticatorData = () => adBuf;
    (response as unknown as Record<string, unknown>).getPublicKey = () => null;
    (response as unknown as Record<string, unknown>).getPublicKeyAlgorithm = () => -7;
    (response as unknown as Record<string, unknown>).getTransports = () => ["internal"];

    const cred = Object.create(PublicKeyCredential.prototype) as PublicKeyCredential;
    Object.defineProperties(cred, {
      id: { value: b64url(r.credentialId), enumerable: true, configurable: true },
      rawId: { value: toBuffer(r.credentialId), enumerable: true, configurable: true },
      type: { value: "public-key", enumerable: true, configurable: true },
      authenticatorAttachment: { value: "platform", enumerable: true, configurable: true },
      response: { value: response, enumerable: true, configurable: true },
    });
    (cred as unknown as Record<string, unknown>).getClientExtensionResults = () => ({});

    console.log("[LumenPass Passkey] built attestation credential id:", b64url(r.credentialId).slice(0, 12) + "…");
    return cred;
  }
})();
