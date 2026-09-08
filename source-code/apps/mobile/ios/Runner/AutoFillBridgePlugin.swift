// AutoFillBridgePlugin.swift
//
// Method-channel bridge that exposes the LumenPass AutoFill functionality
// to the Flutter side. Mirrors `AutoFillBridge` in
// `apps/mobile/lib/features/autofill/application/autofill_bridge.dart`.

import AuthenticationServices
import Flutter
import UIKit

private func afLog(_ message: String) {
    // NSLog goes to both the system log AND to the Flutter run output,
    // which makes the sync flow observable without Console.app.
    NSLog("[LumenPassAutoFill] %@", message)
}

final class AutoFillBridgePlugin: NSObject, FlutterPlugin {
    static let channelName = "lumenpass/autofill"

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = AutoFillBridgePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getStatus":
            getStatus(result: result)
        case "syncCredentials":
            guard let args = call.arguments as? [String: Any],
                  let credentials = args["credentials"] as? [[String: Any]] else {
                result(FlutterError(code: "BAD_ARGS",
                                    message: "Expected credentials list",
                                    details: nil))
                return
            }
            syncCredentials(from: credentials, result: result)
        case "clearCredentials":
            clearCredentials(result: result)
        case "openSystemSettings":
            openSystemSettings(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Implementations

    private func getStatus(result: @escaping FlutterResult) {
        if #available(iOS 12.0, *) {
            ASCredentialIdentityStore.shared.getState { state in
                DispatchQueue.main.async {
                    result(state.isEnabled ? "enabled" : "disabled")
                }
            }
        } else {
            result("notSupported")
        }
    }

    private func syncCredentials(from credentials: [[String: Any]],
                                 result: @escaping FlutterResult) {
        let parsed = credentials.compactMap { dict -> LumenPassCredential? in
            guard let id = dict["id"] as? String,
                  let title = dict["title"] as? String,
                  let password = dict["password"] as? String,
                  let url = dict["url"] as? String else { return nil }
            let username = (dict["username"] as? String) ?? ""
            let otpAuthUrl = dict["otpAuthUrl"] as? String
            let iconPngBase64 = dict["iconPngBase64"] as? String
            let faviconUrl = dict["faviconUrl"] as? String
            let avatarInitials = dict["avatarInitials"] as? String
            let bg = dict["avatarBackgroundArgb"] as? Int
            let fg = dict["avatarForegroundArgb"] as? Int
            let hasPasskey = dict["hasPasskey"] as? Bool ?? false
            let pkCred = dict["passkeyCredentialIdB64url"] as? String
            let pkPem = dict["passkeyPrivateKeyPem"] as? String
            let pkRp = dict["passkeyRpId"] as? String
            let pkUh = dict["passkeyUserHandleB64url"] as? String
            return LumenPassCredential(
                id: id,
                title: title,
                username: username,
                password: password,
                url: url,
                otpAuthUrl: otpAuthUrl,
                iconPngBase64: iconPngBase64,
                faviconUrl: faviconUrl,
                avatarInitials: avatarInitials,
                avatarBackgroundArgb: bg,
                avatarForegroundArgb: fg,
                hasPasskey: hasPasskey,
                passkeyCredentialIdB64url: pkCred,
                passkeyPrivateKeyPem: pkPem,
                passkeyRpId: pkRp,
                passkeyUserHandleB64url: pkUh
            )
        }

        afLog("syncCredentials: received \(parsed.count) credentials")

        do {
            try LumenPassSharedStore.save(credentials: parsed)
        } catch {
            afLog("syncCredentials: failed to persist credential cache: \(error)")
            result(FlutterError(code: "STORE_FAILED",
                                message: error.localizedDescription,
                                details: nil))
            return
        }

        guard #available(iOS 12.0, *) else {
            result(nil)
            return
        }

        let store = ASCredentialIdentityStore.shared
        let passwordIdentities = Self.buildPasswordIdentities(from: parsed)
        afLog("syncCredentials: built \(passwordIdentities.count) password identities " +
              "from \(parsed.count) credentials")

        // Only hit `replaceCredentialIdentities` when the store is enabled.
        // When disabled, the system ignores the call anyway and we'd be wasting
        // a round-trip; it also prevents a confusing log when AutoFill is off.
        store.getState { state in
            afLog("syncCredentials: ASCredentialIdentityStore.isEnabled = \(state.isEnabled)")

            guard state.isEnabled else {
                DispatchQueue.main.async { result(nil) }
                return
            }

            if #available(iOS 17.0, *) {
                let passkeyIdentities = Self.buildPasskeyIdentities(from: parsed)
                var combined: [any ASCredentialIdentity] = []
                combined.reserveCapacity(passwordIdentities.count + passkeyIdentities.count)
                combined.append(contentsOf: passwordIdentities)
                combined.append(contentsOf: passkeyIdentities)
                afLog("syncCredentials: registering \(combined.count) identities " +
                      "(\(passwordIdentities.count) password + \(passkeyIdentities.count) passkey)")
                store.replaceCredentialIdentities(combined) { success, error in
                    DispatchQueue.main.async {
                        if success {
                            afLog("syncCredentials: replaceCredentialIdentities succeeded (\(combined.count))")
                            result(nil)
                        } else {
                            afLog("syncCredentials: replaceCredentialIdentities FAILED: \(error?.localizedDescription ?? "unknown")")
                            result(FlutterError(
                                code: "IDENTITY_STORE_FAILED",
                                message: error?.localizedDescription ?? "Unknown error",
                                details: nil
                            ))
                        }
                    }
                }
            } else {
                store.replaceCredentialIdentities(with: passwordIdentities) { success, error in
                    DispatchQueue.main.async {
                        if success {
                            afLog("syncCredentials: replaceCredentialIdentities succeeded (\(passwordIdentities.count))")
                            result(nil)
                        } else {
                            afLog("syncCredentials: replaceCredentialIdentities FAILED: \(error?.localizedDescription ?? "unknown")")
                            result(FlutterError(
                                code: "IDENTITY_STORE_FAILED",
                                message: error?.localizedDescription ?? "Unknown error",
                                details: nil
                            ))
                        }
                    }
                }
            }
        }
    }

    private func clearCredentials(result: @escaping FlutterResult) {
        LumenPassSharedStore.clear()
        if #available(iOS 12.0, *) {
            ASCredentialIdentityStore.shared.removeAllCredentialIdentities { _, _ in
                DispatchQueue.main.async { result(nil) }
            }
        } else {
            result(nil)
        }
    }

    private func openSystemSettings(result: @escaping FlutterResult) {
        // Best-effort deep-link into Settings → Passwords → AutoFill.
        // Notes:
        // - `App-Prefs:` is not a public API; it may stop working on future iOS.
        // - `canOpenURL` requires LSApplicationQueriesSchemes. We prefer attempting
        //   to open and using the completion callback as truth.
        let rawUrls: [String] = [
            "App-Prefs:root=PASSWORDS",
            "App-Prefs:PASSWORDS",
            UIApplication.openSettingsURLString, // fallback: app-specific settings
        ]

        func tryOpen(_ idx: Int) {
            guard idx < rawUrls.count else {
                DispatchQueue.main.async { result(false) }
                return
            }
            guard let url = URL(string: rawUrls[idx]) else {
                tryOpen(idx + 1)
                return
            }
            UIApplication.shared.open(url, options: [:]) { ok in
                if ok {
                    DispatchQueue.main.async { result(true) }
                } else {
                    tryOpen(idx + 1)
                }
            }
        }

        tryOpen(0)
    }

    // MARK: - Identity building

    /// One `ASPasswordCredentialIdentity` per credential. We register a single
    /// `.domain` identifier when a host can be parsed (Safari matches by host),
    /// avoiding duplicate QuickType rows from registering both URL and domain.
    @available(iOS 12.0, *)
    private static func buildPasswordIdentities(
        from credentials: [LumenPassCredential]
    ) -> [ASPasswordCredentialIdentity] {
        var identities: [ASPasswordCredentialIdentity] = []
        identities.reserveCapacity(credentials.count)

        for cred in credentials {
            let user = cred.username.isEmpty ? cred.title : cred.username
            if user.isEmpty { continue }

            for service in serviceIdentifiers(for: cred) {
                identities.append(
                    ASPasswordCredentialIdentity(
                        serviceIdentifier: service,
                        user: user,
                        recordIdentifier: cred.id
                    )
                )
            }
        }
        return identities
    }

    @available(iOS 17.0, *)
    private static func buildPasskeyIdentities(
        from credentials: [LumenPassCredential]
    ) -> [ASPasskeyCredentialIdentity] {
        var out: [ASPasskeyCredentialIdentity] = []
        out.reserveCapacity(credentials.count)

        // Diagnostics: we want to know why candidates get rejected.
        var flaggedHasPasskey = 0
        var missingPem = 0
        var missingCredId = 0
        var missingRp = 0
        var badCredIdB64 = 0
        var missingDisplayUser = 0

        for cred in credentials {
            if cred.hasPasskey { flaggedHasPasskey += 1 }

            // Field-by-field so we can see which field is blank for entries
            // the vault advertises as passkey-capable.
            let pem = cred.passkeyPrivateKeyPem?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let credIdB64Raw = cred.passkeyCredentialIdB64url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let rpRaw = cred.passkeyRpId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if cred.hasPasskey {
                if pem.isEmpty { missingPem += 1 }
                if credIdB64Raw.isEmpty { missingCredId += 1 }
                if rpRaw.isEmpty { missingRp += 1 }
            }

            guard cred.canSupplyPasskeyAssertion,
                  !credIdB64Raw.isEmpty,
                  !rpRaw.isEmpty else { continue }

            guard let credIdData = try? LumenPassBase64URL.decode(credIdB64Raw) else {
                badCredIdB64 += 1
                afLog("buildPasskeyIdentities: DROP id=\(cred.id) rp=\(rpRaw) reason=badCredIdB64 len=\(credIdB64Raw.count)")
                continue
            }
            let user = cred.username.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayUser = user.isEmpty ? cred.title : user
            guard !displayUser.isEmpty else {
                missingDisplayUser += 1
                continue
            }
            let userHandle: Data? = {
                guard let uh = cred.passkeyUserHandleB64url?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !uh.isEmpty else { return nil }
                return try? LumenPassBase64URL.decode(uh)
            }()
            afLog("buildPasskeyIdentities: KEEP id=\(cred.id) rp=\(rpRaw) user=\(displayUser) credIdLen=\(credIdB64Raw.count) pemLen=\(pem.count) uh=\(userHandle?.count ?? -1)")
            out.append(ASPasskeyCredentialIdentity(
                relyingPartyIdentifier: rpRaw,
                userName: displayUser,
                credentialID: credIdData,
                userHandle: userHandle ?? Data(),
                recordIdentifier: cred.id
            ))
        }

        afLog("buildPasskeyIdentities: summary total=\(credentials.count) " +
              "hasPasskeyFlag=\(flaggedHasPasskey) kept=\(out.count) " +
              "missingPem=\(missingPem) missingCredId=\(missingCredId) missingRp=\(missingRp) " +
              "badCredIdB64=\(badCredIdB64) missingDisplayUser=\(missingDisplayUser)")

        return out
    }

    /// Registers **one** service identifier per credential. Registering both
    /// `.URL` and `.domain` for the same login caused iOS QuickType to show the
    /// same account twice (same `recordIdentifier`, two identities).
    @available(iOS 12.0, *)
    private static func serviceIdentifiers(
        for cred: LumenPassCredential
    ) -> [ASCredentialServiceIdentifier] {
        let rawUrl = cred.url.trimmingCharacters(in: .whitespacesAndNewlines)

        // No URL at all – there's nothing we can meaningfully register with
        // the OS. Surfacing the title as a fake domain would just pollute the
        // store with non-matching identities.
        guard !rawUrl.isEmpty else { return [] }

        if rawUrl.contains("://") {
            if let host = URL(string: rawUrl)?.host, !host.isEmpty {
                return [
                    ASCredentialServiceIdentifier(
                        identifier: host.lowercased(),
                        type: .domain
                    ),
                ]
            }
            return [
                ASCredentialServiceIdentifier(identifier: rawUrl, type: .URL),
            ]
        }

        // Bare host like `pencil.dev` or `sub.pencil.dev/login`.
        let host = rawUrl
            .split(separator: "/")
            .first
            .map(String.init)?
            .lowercased() ?? rawUrl.lowercased()
        return [
            ASCredentialServiceIdentifier(identifier: host, type: .domain),
        ]
    }
}
