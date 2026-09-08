// PasskeyAssertionHelper.swift
//
// Builds WebAuthn assertions compatible with the LumenPass browser extension
// (`generatePasskeyAssertion` in service-worker.ts): ES256 over
// SHA256(authenticatorData || clientDataHash), DER signature, 37-byte
// authenticatorData (rpIdHash || flags 0x05 || signCount 0) — same as extension.

import AuthenticationServices
import CryptoKit
import Foundation
import Security

@available(iOS 17.0, *)
enum PasskeyAssertionHelper {

    /// Authenticator data flags byte for assertion responses.
    ///
    /// UP (0x01) | UV (0x04) | BE (0x08) | BS (0x10) = 0x1D.
    //
    // BE=1 (Backup Eligible) and BS=1 (Backup State) signal that the credential
    // is a multi-device / cloud-synced passkey, which is what LumenPass stores
    // (the KDBX vault is synced across devices). Safari/WebKit on iOS validates
    // the AutoFill provider's assertion and rejects it with `NotAllowedError`
    // before the response ever reaches the RP when BE=0 on the passkey path —
    // regardless of whether the subsequent signature would verify. Chrome on
    // desktop historically accepts BE=0, which is why the desktop browser
    // extension's legacy `0x05` flags still work there.
    private static let extensionAuthenticatorFlags: UInt8 = 0x1D

    static func makeAssertion(
        credential: LumenPassCredential,
        relyingPartyIdentifier: String,
        clientDataHash: Data,
        userVerificationPreference: ASAuthorizationPublicKeyCredentialUserVerificationPreference,
        allowedCredentialsEmpty: Bool
    ) throws -> ASPasskeyAssertionCredential {
        guard credential.canSupplyPasskeyAssertion,
              let pem = credential.passkeyPrivateKeyPem,
              let credIdB64 = credential.passkeyCredentialIdB64url else {
            throw NSError(domain: "PasskeyAssertion", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Incomplete passkey material"])
        }

        // Always hash/sign with the RP id from the OS — it matches the WebAuthn challenge.
        let rpRequest = relyingPartyIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !rpRequest.isEmpty else {
            throw NSError(domain: "PasskeyAssertion", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Empty rpId"])
        }
        let rpStored = credential.passkeyRpId?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if rpStored != rpRequest {
            lpLog("[LumenPassAutoFill] rpId vault vs request differs (vault=\(rpStored) request=\(rpRequest)) — signing with request")
        }
        let rpId = rpRequest

        // Log PEM fingerprint so we can verify the exact bytes on iOS match
        // what the desktop extension sees in the KDBX for this entry.
        let pemDigest = Data(SHA256.hash(data: Data(pem.utf8))).base64EncodedString()
        let pemPreview = pem.replacingOccurrences(of: "\n", with: "\\n")
            .prefix(60)
        let pemTail = pem.replacingOccurrences(of: "\n", with: "\\n").suffix(40)
        lpLog("[LumenPassAutoFill] makeAssertion begin rpId=\(rpId) allowCredEmpty=\(allowedCredentialsEmpty) uvPref=\(String(describing: userVerificationPreference)) credIdLen=\(credIdB64.count) pemLen=\(pem.count) clientDataHashLen=\(clientDataHash.count) pemSha256=\(pemDigest) pemHead=\(pemPreview) pemTail=\(pemTail)")
        lpLog("[LumenPassAutoFill] credIdB64=\(credIdB64) clientDataHashB64=\(clientDataHash.base64EncodedString())")
        let privateKey: P256.Signing.PrivateKey
        do {
            privateKey = try importP256PrivateKeyFromPKCS8PEM(pem)
            lpLog("[LumenPassAutoFill] P-256 PKCS#8 import OK; pubKey=\(privateKey.publicKey.rawRepresentation.base64EncodedString())")
        } catch {
            lpLog("[LumenPassAutoFill] P-256 import FAILED: \(error.localizedDescription)")
            throw error
        }
        let rpIdHash = Data(SHA256.hash(data: Data(rpId.utf8)))
        let flags = Self.extensionAuthenticatorFlags
        lpLog("[LumenPassAutoFill] authFlags=0x\(String(format: "%02x", flags)) (UP|UV|BE|BS)")

        var authenticatorData = Data()
        authenticatorData.append(rpIdHash)
        authenticatorData.append(flags)
        authenticatorData.append(contentsOf: [0, 0, 0, 0]) // signCount BE = 0

        precondition(authenticatorData.count == 37)

        // ES256: SHA-256 hash is computed internally by CryptoKit; `.derRepresentation`
        // matches what WebAuthn RPs expect (same as Android `SHA256withECDSA` + DER,
        // and the desktop extension's `p1363ToDer(rawSig)`).
        let message = authenticatorData + clientDataHash
        let signature: Data
        do {
            let sig = try privateKey.signature(for: message)
            signature = sig.derRepresentation

            // Self-verify: if CryptoKit verification succeeds, the signature
            // is mathematically valid against our derived public key. If it
            // still fails server-side, Google has a different pubKey on file.
            let verifyOk = privateKey.publicKey.isValidSignature(sig, for: message)
            lpLog("[LumenPassAutoFill] signature bytes: authDataB64=\(authenticatorData.base64EncodedString()) messageB64=\(message.base64EncodedString()) sigDerB64=\(signature.base64EncodedString()) sigRawB64=\(sig.rawRepresentation.base64EncodedString()) selfVerify=\(verifyOk)")
        } catch {
            throw NSError(domain: "PasskeyAssertion", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "ECDSA sign failed: \(error.localizedDescription)"])
        }

        let credentialID = try LumenPassBase64URL.decode(credIdB64)

        let userHandleBytes: Data
        if let uhRaw = credential.passkeyUserHandleB64url?.trimmingCharacters(in: .whitespacesAndNewlines),
           !uhRaw.isEmpty {
            do {
                userHandleBytes = try LumenPassBase64URL.decode(uhRaw)
            } catch {
                throw NSError(domain: "PasskeyAssertion", code: 20,
                              userInfo: [NSLocalizedDescriptionKey:
                                "passkeyUserHandle base64url decode failed: \(error.localizedDescription)"])
            }
            lpLog("[LumenPassAutoFill] userHandleLen=\(userHandleBytes.count)")
        } else {
            userHandleBytes = Data()
            lpLog("[LumenPassAutoFill] userHandleLen=0 (none in vault)")
        }

        return ASPasskeyAssertionCredential(
            userHandle: userHandleBytes,
            relyingParty: rpId,
            signature: signature,
            clientDataHash: clientDataHash,
            authenticatorData: authenticatorData,
            credentialID: credentialID
        )
    }

    // MARK: - PKCS#8 PEM → CryptoKit P-256 private key
    //
    // NOTE: We intentionally do NOT use `SecKeyCreateWithData` here because it
    // does not accept PKCS#8 DER for EC keys — it requires ANSI X9.63
    // (`0x04 || X || Y || K`). Feeding PKCS#8 bytes to it historically
    // produced a bogus key whose signatures never verified server-side
    // (Google would reply "Something went wrong. Try again."). CryptoKit's
    // `P256.Signing.PrivateKey(derRepresentation:)` natively parses PKCS#8
    // DER, matching the desktop extension (WebCrypto `importKey("pkcs8", …)`)
    // and Android (`PKCS8EncodedKeySpec`) behavior.
    private static func importP256PrivateKeyFromPKCS8PEM(
        _ pem: String
    ) throws -> P256.Signing.PrivateKey {
        let body = pem
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN EC PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END EC PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let der = Data(base64Encoded: body) else {
            throw NSError(domain: "PasskeyAssertion", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid PEM base64"])
        }

        // Prefer PEM-native initializer when the caller actually provides a
        // PEM string; fall back to DER. Both paths accept PKCS#8 on iOS 14+.
        if let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) {
            return key
        }
        do {
            return try P256.Signing.PrivateKey(derRepresentation: der)
        } catch {
            throw NSError(
                domain: "PasskeyAssertion",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey:
                    "P-256 PKCS#8 import failed: \(error.localizedDescription)"]
            )
        }
    }
}
