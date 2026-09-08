// CredentialProviderViewController.swift
//
// Root view controller for the LumenPass AutoFill credential provider
// extension. Handles password fill (all supported iOS versions) and passkey
// assertions on iOS 17+ using the same WebAuthn material as the desktop
// browser extension.

import AuthenticationServices
import CryptoKit
import UIKit

final class CredentialProviderViewController: ASCredentialProviderViewController {

    private var serviceIdentifiers: [ASCredentialServiceIdentifier] = []

    // MARK: - View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        lpLog("[LumenPassAutoFill] viewDidLoad")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        lpLog("[LumenPassAutoFill] viewDidAppear animated=\(animated)")
    }

    // MARK: - Lifecycle (password list — Safari / apps without passkey request)

    override func prepareCredentialList(
        for serviceIdentifiers: [ASCredentialServiceIdentifier]
    ) {
        lpLog("[LumenPassAutoFill] prepareCredentialList(password) sids=\(serviceIdentifiers.map { $0.identifier })")
        self.serviceIdentifiers = serviceIdentifiers
        resetChildUI()
        renderPasswordPicker(for: serviceIdentifiers)
    }

    // MARK: - Passkey list (iOS 17+)

    @available(iOS 17.0, *)
    override func prepareCredentialList(
        for serviceIdentifiers: [ASCredentialServiceIdentifier],
        requestParameters: ASPasskeyCredentialRequestParameters
    ) {
        lpLog("[LumenPassAutoFill] prepareCredentialList(passkey) rpId=\(requestParameters.relyingPartyIdentifier) allowed=\(requestParameters.allowedCredentials.count) sids=\(serviceIdentifiers.map { $0.identifier })")
        self.serviceIdentifiers = serviceIdentifiers
        resetChildUI()
        renderPasskeyPicker(
            for: serviceIdentifiers,
            relyingPartyIdentifier: requestParameters.relyingPartyIdentifier,
            clientDataHash: requestParameters.clientDataHash,
            allowedCredentialIds: requestParameters.allowedCredentials,
            userVerificationPreference: requestParameters.userVerificationPreference
        )
    }

    // MARK: - QuickType / zero-interaction (legacy password API)

    override func provideCredentialWithoutUserInteraction(
        for credentialIdentity: ASPasswordCredentialIdentity
    ) {
        lpLog("[LumenPassAutoFill] provideCredentialWithoutUserInteraction(password) record=\(credentialIdentity.recordIdentifier ?? "nil") svc=\(credentialIdentity.serviceIdentifier.identifier)")
        let store = LumenPassSharedStore.load()
        guard
            let recordId = credentialIdentity.recordIdentifier,
            let credential = store.first(where: { $0.id == recordId })
        else {
            extensionContext.cancelRequest(withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.userInteractionRequired.rawValue
            ))
            return
        }
        completePassword(with: credential)
    }

    // MARK: - QuickType unified (iOS 17+ — password or passkey)

    @available(iOS 17.0, *)
    override func provideCredentialWithoutUserInteraction(
        for credentialRequest: ASCredentialRequest
    ) {
        lpLog("[LumenPassAutoFill] provideCredentialWithoutUserInteraction(unified) requestType=\(type(of: credentialRequest)) record=\(credentialRequest.credentialIdentity.recordIdentifier ?? "nil")")
        let store = LumenPassSharedStore.load()

        if let passReq = credentialRequest as? ASPasskeyCredentialRequest {
            let _rpForLog = (passReq.credentialIdentity as? ASPasskeyCredentialIdentity)?.relyingPartyIdentifier ?? "nil"
            lpLog("[LumenPassAutoFill] unified -> passkey rpId=\(_rpForLog) clientDataHashLen=\(passReq.clientDataHash.count)")
            guard let recordId = passReq.credentialIdentity.recordIdentifier,
                  let credential = store.first(where: { $0.id == recordId }) else {
                extensionContext.cancelRequest(withError: NSError(
                    domain: ASExtensionErrorDomain,
                    code: ASExtensionError.userInteractionRequired.rawValue
                ))
                return
            }
            guard credential.canSupplyPasskeyAssertion else {
                extensionContext.cancelRequest(withError: NSError(
                    domain: ASExtensionErrorDomain,
                    code: ASExtensionError.userInteractionRequired.rawValue
                ))
                return
            }
            guard passRequestMatchesCredential(request: passReq, credential: credential) else {
                extensionContext.cancelRequest(withError: NSError(
                    domain: ASExtensionErrorDomain,
                    code: ASExtensionError.userInteractionRequired.rawValue
                ))
                return
            }
            let rp = (passReq.credentialIdentity as? ASPasskeyCredentialIdentity)?
                .relyingPartyIdentifier
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
            guard !rp.isEmpty else {
                extensionContext.cancelRequest(withError: NSError(
                    domain: ASExtensionErrorDomain,
                    code: ASExtensionError.userInteractionRequired.rawValue
                ))
                return
            }
            completePasskeyAssertion(
                credential: credential,
                relyingPartyIdentifier: rp,
                clientDataHash: passReq.clientDataHash,
                userVerificationPreference: passReq.userVerificationPreference,
                allowedCredentialsEmpty: true
            )
            return
        }

        if let pwReq = credentialRequest as? ASPasswordCredentialRequest,
           let pwIdentity = pwReq.credentialIdentity as? ASPasswordCredentialIdentity,
           let recordId = pwIdentity.recordIdentifier,
           let credential = store.first(where: { $0.id == recordId }) {
            completePassword(with: credential)
            return
        }

        extensionContext.cancelRequest(withError: NSError(
            domain: ASExtensionErrorDomain,
            code: ASExtensionError.userInteractionRequired.rawValue
        ))
    }

    // MARK: - UI password path

    override func prepareInterfaceToProvideCredential(
        for credentialIdentity: ASPasswordCredentialIdentity
    ) {
        lpLog("[LumenPassAutoFill] prepareInterfaceToProvideCredential(password) record=\(credentialIdentity.recordIdentifier ?? "nil")")
        let store = LumenPassSharedStore.load()
        if let recordId = credentialIdentity.recordIdentifier,
           let credential = store.first(where: { $0.id == recordId }) {
            completePassword(with: credential)
            return
        }
        resetChildUI()
        renderPasswordPicker(for: serviceIdentifiers)
    }

    @available(iOS 17.0, *)
    override func prepareInterfaceToProvideCredential(
        for credentialRequest: ASCredentialRequest
    ) {
        lpLog("[LumenPassAutoFill] prepareInterfaceToProvideCredential(unified) requestType=\(type(of: credentialRequest))")
        if let passReq = credentialRequest as? ASPasskeyCredentialRequest {
            let store = LumenPassSharedStore.load()
            if let recordId = passReq.credentialIdentity.recordIdentifier,
               let credential = store.first(where: { $0.id == recordId }),
               credential.canSupplyPasskeyAssertion,
               passRequestMatchesCredential(request: passReq, credential: credential) {
                let rp = (passReq.credentialIdentity as? ASPasskeyCredentialIdentity)?
                    .relyingPartyIdentifier
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
                if !rp.isEmpty {
                    completePasskeyAssertion(
                        credential: credential,
                        relyingPartyIdentifier: rp,
                        clientDataHash: passReq.clientDataHash,
                        userVerificationPreference: passReq.userVerificationPreference,
                        allowedCredentialsEmpty: true
                    )
                    return
                }
            }
            let rp = (passReq.credentialIdentity as? ASPasskeyCredentialIdentity)?
                .relyingPartyIdentifier
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
            resetChildUI()
            renderPasskeyPicker(
                for: serviceIdentifiers,
                relyingPartyIdentifier: rp,
                clientDataHash: passReq.clientDataHash,
                allowedCredentialIds: [],
                userVerificationPreference: passReq.userVerificationPreference
            )
            return
        }

        if let pwReq = credentialRequest as? ASPasswordCredentialRequest,
           let pwIdentity = pwReq.credentialIdentity as? ASPasswordCredentialIdentity {
            prepareInterfaceToProvideCredential(for: pwIdentity)
            return
        }

        extensionContext.cancelRequest(withError: NSError(
            domain: ASExtensionErrorDomain,
            code: ASExtensionError.userInteractionRequired.rawValue
        ))
    }

    // MARK: - Passkey registration (iOS 17+)

    @available(iOS 17.0, *)
    override func prepareInterface(
        forPasskeyRegistration registrationRequest: any ASCredentialRequest
    ) {
        lpLog("[LumenPassAutoFill] prepareInterface(forPasskeyRegistration:) ENTRY requestType=\(type(of: registrationRequest))")
        if let pkReq = registrationRequest as? ASPasskeyCredentialRequest {
            lpLog("[LumenPassAutoFill] prepareInterface(forPasskeyRegistration:) IS ASPasskeyCredentialRequest clientDataHashLen=\(pkReq.clientDataHash.count)")
            if let pkId = pkReq.credentialIdentity as? ASPasskeyCredentialIdentity {
                lpLog("[LumenPassAutoFill] prepareInterface(forPasskeyRegistration:) rpId=\(pkId.relyingPartyIdentifier) user=\(pkId.userName) credIDLen=\(pkId.credentialID.count) record=\(pkId.recordIdentifier ?? "nil")")
            } else {
                lpLog("[LumenPassAutoFill] prepareInterface(forPasskeyRegistration:) identity is NOT ASPasskeyCredentialIdentity — type=\(type(of: pkReq.credentialIdentity))")
            }
        } else {
            lpLog("[LumenPassAutoFill] prepareInterface(forPasskeyRegistration:) NOT ASPasskeyCredentialRequest — type=\(type(of: registrationRequest))")
        }
        guard let request = registrationRequest as? ASPasskeyCredentialRequest else {
            lpLog("[LumenPassAutoFill] prepareInterface(forPasskeyRegistration:) ABORT: cast to ASPasskeyCredentialRequest failed")
            extensionContext.cancelRequest(withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.failed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported passkey registration request type"]
            ))
            return
        }
        completePasskeyRegistration(request)
    }

    @available(iOS 17.0, *)
    override func performWithoutUserInteractionIfPossible(
        passkeyRegistration registrationRequest: ASPasskeyCredentialRequest
    ) {
        let rp = (registrationRequest.credentialIdentity as? ASPasskeyCredentialIdentity)?
            .relyingPartyIdentifier ?? "unknown"
        lpLog("[LumenPassAutoFill] performWithoutUserInteractionIfPossible(passkeyRegistration:) ENTRY rp=\(rp) — requesting user interaction")
        extensionContext.cancelRequest(withError: NSError(
            domain: ASExtensionErrorDomain,
            code: ASExtensionError.userInteractionRequired.rawValue
        ))
    }

    // MARK: - UI builders

    private func resetChildUI() {
        for child in children {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
    }

    private func renderPasswordPicker(
        for serviceIdentifiers: [ASCredentialServiceIdentifier]
    ) {
        let all = LumenPassSharedStore.load()
        let (matches, domainContextActive) = matchingCredentials(
            credentials: all,
            for: serviceIdentifiers
        )

        let picker = CredentialListViewController(
            matching: matches,
            all: all,
            domainContextActive: domainContextActive,
            onSelect: { [weak self] credential in
                self?.completePassword(with: credential)
            },
            onCancel: { [weak self] in
                self?.extensionContext.cancelRequest(withError: NSError(
                    domain: ASExtensionErrorDomain,
                    code: ASExtensionError.userCanceled.rawValue
                ))
            }
        )

        embed(picker)
    }

    @available(iOS 17.0, *)
    private func renderPasskeyPicker(
        for serviceIdentifiers: [ASCredentialServiceIdentifier],
        relyingPartyIdentifier: String,
        clientDataHash: Data,
        allowedCredentialIds: [Data],
        userVerificationPreference: ASAuthorizationPublicKeyCredentialUserVerificationPreference
    ) {
        // Match passkeys by WebAuthn rpId only. The vault URL host filter used
        // for password autofill is wrong here: a freshly-registered passkey may
        // store `passkeyRpId=google.com` while its entry URL is
        // `accounts.google.com/...` (or empty), which would wrongly exclude it.
        let all = LumenPassSharedStore.load()
        let rp = relyingPartyIdentifier.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let allowed = allowedCredentialIds
        let passkeyMatches = all.filter { credential in
            guard credential.canSupplyPasskeyAssertion else { return false }
            let storedRp = credential.passkeyRpId?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
            guard !rp.isEmpty, storedRp.lowercased() == rp.lowercased() else { return false }
            if allowed.isEmpty { return true }
            guard let b64 = credential.passkeyCredentialIdB64url,
                  let cid = try? LumenPassBase64URL.decode(b64) else { return false }
            return allowed.contains(where: { $0 == cid })
        }

        lpLog("[LumenPassAutoFill] renderPasskeyPicker rp=\(rp) allowed=\(allowed.count) storeSize=\(all.count) passkeyMatches=\(passkeyMatches.count)")

        // In the passkey flow the picker must NEVER surface non-passkey entries,
        // even when `passkeyMatches` is empty. Pass the same filtered array to both
        // `matching` and `all` so `CredentialListViewController`'s empty-state
        // fallback can't swap in password-only records.
        let picker = CredentialListViewController(
            matching: passkeyMatches,
            all: passkeyMatches,
            domainContextActive: true,
            onSelect: { [weak self] credential in
                guard let self else { return }
                self.completePasskeyAssertion(
                    credential: credential,
                    relyingPartyIdentifier: rp,
                    clientDataHash: clientDataHash,
                    userVerificationPreference: userVerificationPreference,
                    allowedCredentialsEmpty: allowed.isEmpty
                )
            },
            onCancel: { [weak self] in
                self?.extensionContext.cancelRequest(withError: NSError(
                    domain: ASExtensionErrorDomain,
                    code: ASExtensionError.userCanceled.rawValue
                ))
            }
        )

        embed(picker)
    }

    private func embed(_ root: UIViewController) {
        let nav = UINavigationController(rootViewController: root)
        nav.navigationBar.prefersLargeTitles = false
        addChild(nav)
        nav.view.frame = view.bounds
        nav.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(nav.view)
        nav.didMove(toParent: self)
    }

    // MARK: - Completion

    private func completePassword(with credential: LumenPassCredential) {
        let _rpForLog = credential.passkeyRpId ?? "-"
        lpLog("[LumenPassAutoFill] completePassword id=\(credential.id) user=\(credential.username) rp=\(_rpForLog)")
        let pwCredential = ASPasswordCredential(
            user: credential.username,
            password: credential.password
        )
        extensionContext.completeRequest(
            withSelectedCredential: pwCredential,
            completionHandler: nil
        )
    }

    @available(iOS 17.0, *)
    private func completePasskeyAssertion(
        credential: LumenPassCredential,
        relyingPartyIdentifier: String,
        clientDataHash: Data,
        userVerificationPreference: ASAuthorizationPublicKeyCredentialUserVerificationPreference,
        allowedCredentialsEmpty: Bool
    ) {
        do {
            let assertion = try PasskeyAssertionHelper.makeAssertion(
                credential: credential,
                relyingPartyIdentifier: relyingPartyIdentifier,
                clientDataHash: clientDataHash,
                userVerificationPreference: userVerificationPreference,
                allowedCredentialsEmpty: allowedCredentialsEmpty
            )
            extensionContext.completeAssertionRequest(
                using: assertion,
                completionHandler: nil
            )
        } catch {
            lpLog("[LumenPassAutoFill] passkey assertion failed: \(error)")
            extensionContext.cancelRequest(withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.failed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
            ))
        }
    }

    @available(iOS 17.0, *)
    private func completePasskeyRegistration(_ request: ASPasskeyCredentialRequest) {
        lpLog("[LumenPassAutoFill] completePasskeyRegistration BEGIN requestType=\(type(of: request)) identityType=\(type(of: request.credentialIdentity))")
        lpLog("[LumenPassAutoFill] completePasskeyRegistration clientDataHash len=\(request.clientDataHash.count) b64=\(request.clientDataHash.base64EncodedString())")
        lpLog("[LumenPassAutoFill] completePasskeyRegistration uvPref=\(String(describing: request.userVerificationPreference)) supportedAlgs=\(request.supportedAlgorithms)")

        guard let identity = request.credentialIdentity as? ASPasskeyCredentialIdentity else {
            lpLog("[LumenPassAutoFill] completePasskeyRegistration ABORT: identity is NOT ASPasskeyCredentialIdentity — actual type=\(type(of: request.credentialIdentity))")
            extensionContext.cancelRequest(withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.failed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "Passkey registration identity is not ASPasskeyCredentialIdentity"]
            ))
            return
        }

        let rpId = identity.relyingPartyIdentifier
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .lowercased()
        let userName = identity.userName
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let recordId = identity.recordIdentifier?.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines
        )
        let userHandle = identity.userHandle

        lpLog("[LumenPassAutoFill] completePasskeyRegistration rpId=\(rpId) userName=\(userName) recordId=\(recordId ?? "nil") userHandleLen=\(userHandle.count) credentialIDLen=\(identity.credentialID.count)")

        guard !rpId.isEmpty else {
            lpLog("[LumenPassAutoFill] completePasskeyRegistration ABORT: rpId is empty")
            extensionContext.cancelRequest(withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.failed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "Passkey registration missing relying party identifier"]
            ))
            return
        }

        do {
            lpLog("[LumenPassAutoFill] completePasskeyRegistration generating key material…")
            let generated = try makePasskeyRegistrationMaterial(
                relyingPartyIdentifier: rpId,
                userVerificationPreference: request.userVerificationPreference
            )
            lpLog("[LumenPassAutoFill] completePasskeyRegistration key material OK credId=\(generated.credentialIdB64url) pemLen=\(generated.privateKeyPem.count) attestObjLen=\(generated.attestationObject.count)")

            var store = LumenPassSharedStore.load()
            lpLog("[LumenPassAutoFill] completePasskeyRegistration store loaded count=\(store.count)")

            let existingIndex: Int? = {
                if let recordId, !recordId.isEmpty,
                   let idx = store.firstIndex(where: { $0.id == recordId }) {
                    return idx
                }
                if !userName.isEmpty,
                   let idx = store.firstIndex(where: {
                       let rp = $0.passkeyRpId?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased() ?? ""
                       return rp == rpId && $0.username.caseInsensitiveCompare(userName) == .orderedSame
                   }) {
                    return idx
                }
                return nil
            }()
            lpLog("[LumenPassAutoFill] completePasskeyRegistration existingIndex=\(existingIndex.map(String.init) ?? "nil")")

            let base: LumenPassCredential = {
                if let idx = existingIndex { return store[idx] }
                let newId = "ios-passkey-\(UUID().uuidString.lowercased())"
                return LumenPassCredential(
                    id: newId,
                    title: rpId,
                    username: userName,
                    password: "",
                    url: "https://\(rpId)",
                    otpAuthUrl: nil
                )
            }()

            // Use the userHandle from the OS registration identity when present
            let userHandleB64url: String = {
                if !userHandle.isEmpty {
                    return userHandle.base64URLEncodedString()
                }
                return generated.userHandleB64url
            }()

            let merged = LumenPassCredential(
                id: base.id,
                title: base.title.isEmpty ? rpId : base.title,
                username: userName.isEmpty ? base.username : userName,
                password: base.password,
                url: base.url.isEmpty ? "https://\(rpId)" : base.url,
                otpAuthUrl: base.otpAuthUrl,
                iconPngBase64: base.iconPngBase64,
                faviconUrl: base.faviconUrl,
                avatarInitials: base.avatarInitials,
                avatarBackgroundArgb: base.avatarBackgroundArgb,
                avatarForegroundArgb: base.avatarForegroundArgb,
                hasPasskey: true,
                passkeyCredentialIdB64url: generated.credentialIdB64url,
                passkeyPrivateKeyPem: generated.privateKeyPem,
                passkeyRpId: rpId,
                passkeyUserHandleB64url: userHandleB64url
            )
            lpLog("[LumenPassAutoFill] completePasskeyRegistration merged credential id=\(merged.id) rpId=\(rpId) user=\(merged.username)")

            if let idx = existingIndex {
                store[idx] = merged
            } else {
                store.append(merged)
            }
            do {
                try LumenPassSharedStore.save(credentials: store)
                lpLog("[LumenPassAutoFill] completePasskeyRegistration store saved count=\(store.count)")
            } catch {
                lpLog("[LumenPassAutoFill] completePasskeyRegistration WARN: store save failed: \(error.localizedDescription) — continuing with registration anyway")
            }

            let registration = ASPasskeyRegistrationCredential(
                relyingParty: rpId,
                clientDataHash: request.clientDataHash,
                credentialID: generated.credentialId,
                attestationObject: generated.attestationObject
            )
            lpLog("[LumenPassAutoFill] completePasskeyRegistration calling completeRegistrationRequest rp=\(rpId) credIDLen=\(generated.credentialId.count) attestObjLen=\(generated.attestationObject.count) clientDataHashLen=\(request.clientDataHash.count)")
            lpLog("[LumenPassAutoFill] completePasskeyRegistration attestObjB64=\(generated.attestationObject.base64EncodedString())")

            extensionContext.completeRegistrationRequest(using: registration) { expired in
                lpLog("[LumenPassAutoFill] completePasskeyRegistration completionHandler expired=\(expired) rp=\(rpId) record=\(merged.id)")
            }
            lpLog("[LumenPassAutoFill] completePasskeyRegistration completeRegistrationRequest dispatched")
        } catch {
            lpLog("[LumenPassAutoFill] completePasskeyRegistration FAILED: \(error) — \(error.localizedDescription)")
            extensionContext.cancelRequest(withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.failed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
            ))
        }
    }

    // MARK: - Passkey request helpers

    @available(iOS 17.0, *)
    private func passRequestMatchesCredential(
        request: ASPasskeyCredentialRequest,
        credential: LumenPassCredential
    ) -> Bool {
        guard let identity = request.credentialIdentity as? ASPasskeyCredentialIdentity else {
            return false
        }
        let rpReq = identity.relyingPartyIdentifier.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let rpStored = credential.passkeyRpId?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        guard !rpReq.isEmpty, rpReq.lowercased() == rpStored.lowercased() else { return false }
        guard let b64 = credential.passkeyCredentialIdB64url,
              let ourCid = try? LumenPassBase64URL.decode(b64) else { return false }
        return identity.credentialID == ourCid
    }

    /// Mirrors [BrowserExtensionService] domain filtering: compare entry URL
    /// host to the page host only — no title/username substring heuristics
    /// (those caused unrelated sites like `www.zendesk.com` to match `pencil.dev`
    /// when titles contained `www` or similar).
    private func matchingCredentials(
        credentials: [LumenPassCredential],
        for serviceIdentifiers: [ASCredentialServiceIdentifier]
    ) -> (matches: [LumenPassCredential], domainContextActive: Bool) {
        let pageHosts = Self.normalizedPageHosts(from: serviceIdentifiers)
        if serviceIdentifiers.isEmpty || pageHosts.isEmpty {
            return (credentials, false)
        }

        var filtered = credentials.filter { credential in
            guard let entryHost = Self.extractDomain(from: credential.url) else { return false }
            return pageHosts.contains { pageHost in
                Self.domainsMatch(entryHost: entryHost, pageHost: pageHost, subdomainStrict: false)
            }
        }

        filtered.sort { a, b in
            let ah = a.serviceIdentifier
            let bh = b.serviceIdentifier
            if ah != bh { return ah < bh }
            if a.title.lowercased() != b.title.lowercased() {
                return a.title.lowercased() < b.title.lowercased()
            }
            return a.id < b.id
        }

        return (filtered, true)
    }

    // MARK: - Domain helpers (aligned with `browser_extension_service.dart`)

    private static func extractDomain(from url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let uri = URL(string: withScheme), let host = uri.host, !host.isEmpty else {
            return nil
        }
        return host.lowercased()
    }

    private static func normalizedPageHosts(
        from serviceIdentifiers: [ASCredentialServiceIdentifier]
    ) -> Set<String> {
        var hosts = Set<String>()
        for sid in serviceIdentifiers {
            let raw = sid.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { continue }
            if let host = extractDomain(from: raw) {
                hosts.insert(host)
            }
        }
        return hosts
    }

    private static func rootDomain(_ host: String) -> String {
        let parts = host.split(separator: ".")
        guard parts.count >= 2 else { return host }
        return "\(parts[parts.count - 2]).\(parts[parts.count - 1])"
    }

    /// Same rules as `_domainsMatchWithSetting(..., 'default')` on desktop.
    private static func domainsMatch(
        entryHost: String,
        pageHost: String,
        subdomainStrict: Bool
    ) -> Bool {
        if subdomainStrict { return entryHost == pageHost }
        if entryHost == pageHost { return true }
        let r1 = rootDomain(entryHost)
        let r2 = rootDomain(pageHost)
        return !r1.isEmpty && r1 == r2
    }
}

@available(iOS 17.0, *)
private struct PasskeyRegistrationMaterial {
    let credentialId: Data
    let credentialIdB64url: String
    let privateKeyPem: String
    let userHandleB64url: String
    let attestationObject: Data
}

@available(iOS 17.0, *)
private func makePasskeyRegistrationMaterial(
    relyingPartyIdentifier rpId: String,
    userVerificationPreference: ASAuthorizationPublicKeyCredentialUserVerificationPreference
) throws -> PasskeyRegistrationMaterial {
    let privateKey = P256.Signing.PrivateKey()
    let publicKeyRaw = privateKey.publicKey.x963Representation
    guard publicKeyRaw.count == 65 else {
        throw NSError(domain: "PasskeyRegistration", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Unexpected P-256 public key length"])
    }
    let x = publicKeyRaw[1..<33]
    let y = publicKeyRaw[33..<65]

    let credentialId = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
    let userHandle = Data((0..<16).map { _ in UInt8.random(in: 0...255) })

    let aaguid = Data(repeating: 0, count: 16)
    let credIdLen = Data([UInt8((credentialId.count >> 8) & 0xff), UInt8(credentialId.count & 0xff)])
    let coseKey = cborMap([
        (.unsigned(1), .unsigned(2)), // kty: EC2
        (.unsigned(3), .negative(-7)), // alg: ES256
        (.negative(-1), .unsigned(1)), // crv: P-256
        (.negative(-2), .bytes(Data(x))),
        (.negative(-3), .bytes(Data(y))),
    ])

    let rpHash = Data(SHA256.hash(data: Data(rpId.utf8)))
    // UP | AT plus BE | BS (multi-device / cloud-synced passkey), and UV when
    // requested/preferred. WebKit on iOS rejects passkey registrations whose
    // authenticator data reports BE=0 with `NotAllowedError` ("The request is
    // not allowed by the user agent...") — matching the assertion flags in
    // `PasskeyAssertionHelper.extensionAuthenticatorFlags` (0x1D).
    let uvBit: UInt8 = (userVerificationPreference == .required || userVerificationPreference == .preferred) ? 0x04 : 0x00
    let flags: UInt8 = 0x41 | 0x08 | 0x10 | uvBit
    let signCount = Data([0, 0, 0, 0])
    let authData = rpHash + Data([flags]) + signCount + aaguid + credIdLen + credentialId + coseKey
    let attestationObject = cborMap([
        (.text("fmt"), .text("none")),
        (.text("attStmt"), .map([])),
        (.text("authData"), .bytes(authData)),
    ])

    let pkcs8Der = privateKey.derRepresentation
    let pemBody = pkcs8Der.base64EncodedString().chunked(into: 64).joined(separator: "\n")
    let pem = "-----BEGIN PRIVATE KEY-----\n\(pemBody)\n-----END PRIVATE KEY-----"

    return PasskeyRegistrationMaterial(
        credentialId: credentialId,
        credentialIdB64url: credentialId.base64URLEncodedString(),
        privateKeyPem: pem,
        userHandleB64url: userHandle.base64URLEncodedString(),
        attestationObject: attestationObject
    )
}

private enum CborValue {
    case unsigned(Int)
    case negative(Int)
    case bytes(Data)
    case text(String)
    case map([(CborValue, CborValue)])
}

private func cborMap(_ pairs: [(CborValue, CborValue)]) -> Data {
    cborEncode(.map(pairs))
}

private func cborEncode(_ value: CborValue) -> Data {
    switch value {
    case .unsigned(let n):
        return cborMajorType(0, value: n)
    case .negative(let n):
        let transformed = -1 - n
        return cborMajorType(1, value: transformed)
    case .bytes(let data):
        return cborMajorType(2, value: data.count) + data
    case .text(let s):
        let bytes = Data(s.utf8)
        return cborMajorType(3, value: bytes.count) + bytes
    case .map(let pairs):
        var out = cborMajorType(5, value: pairs.count)
        for (k, v) in pairs {
            out += cborEncode(k)
            out += cborEncode(v)
        }
        return out
    }
}

private func cborMajorType(_ major: UInt8, value: Int) -> Data {
    if value < 24 {
        return Data([UInt8((Int(major) << 5) | value)])
    }
    if value <= 0xff {
        return Data([UInt8((Int(major) << 5) | 24), UInt8(value)])
    }
    if value <= 0xffff {
        return Data([
            UInt8((Int(major) << 5) | 25),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ])
    }
    return Data([
        UInt8((Int(major) << 5) | 26),
        UInt8((value >> 24) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff),
    ])
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    func chunked(into size: Int) -> [String] {
        guard size > 0 else { return [self] }
        var chunks: [String] = []
        chunks.reserveCapacity((count + size - 1) / size)
        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[start..<end]))
            start = end
        }
        return chunks
    }
}
