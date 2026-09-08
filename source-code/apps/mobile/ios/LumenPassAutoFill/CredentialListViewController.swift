// CredentialListViewController.swift
//
// Lightweight UIKit list shown when iOS asks the LumenPass AutoFill
// extension to let the user pick a credential for the current service.

import AuthenticationServices
import UIKit

final class CredentialListViewController: UIViewController {

    typealias CredentialHandler = (LumenPassCredential) -> Void

    // MARK: - Input

    // These are `var` rather than `let` because the list can be rebuilt in
    // place when the shared credential cache becomes available while the
    // extension is still on screen (see `refreshFromSharedCache`).
    private var matching: [LumenPassCredential]
    private var all: [LumenPassCredential]
    /// True when iOS passed a page/service — we filtered by URL host (see desktop bridge).
    private var domainContextActive: Bool
    private let onSelect: CredentialHandler
    private let onCancel: () -> Void

    // MARK: - State

    private var visible: [LumenPassCredential]
    private var showingAll = false

    // MARK: - Views

    private let tableView: UITableView
    private var totpRefreshTimer: Timer?
    private let searchController = UISearchController(searchResultsController: nil)

    // Empty-state UI — split into two flavours:
    // 1. `lockedStateView`: shown when the shared credential cache is empty,
    //    i.e. the user hasn't unlocked LumenPass on this device yet. Acts as a
    //    full-screen inline unlock CTA with a prominent "Unlock LumenPass"
    //    button that deep-links into the host app.
    // 2. `searchEmptyLabel`: shown when the cache IS populated but the
    //    current query / filter produced no matches. Lightweight plain text.
    private let lockedStateView = LockedStateView()
    private let searchEmptyLabel = UILabel()

    init(matching: [LumenPassCredential],
         all: [LumenPassCredential],
         domainContextActive: Bool = false,
         onSelect: @escaping CredentialHandler,
         onCancel: @escaping () -> Void) {
        self.matching = matching
        self.all = all
        self.domainContextActive = domainContextActive
        self.onSelect = onSelect
        self.onCancel = onCancel
        if domainContextActive && matching.isEmpty {
            self.visible = []
            self.showingAll = false
        } else {
            self.visible = matching.isEmpty ? all : matching
            self.showingAll = matching.isEmpty
        }
        self.tableView = UITableView(frame: .zero, style: .insetGrouped)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGroupedBackground
        title = "LumenPass"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        if !all.isEmpty && (!matching.isEmpty || domainContextActive) {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: showingAll ? "Matching" : "All",
                style: .plain,
                target: self,
                action: #selector(toggleAll)
            )
        }

        configureSearch()
        configureTableView()
        configureEmptyState()
        applyVisibleFromCurrentSource()
        updateEmptyState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startTotpRefreshTimer()
        // When the user comes back from the LumenPass app (after unlocking
        // their vault), re-read the shared credential cache and refresh the
        // list in place — avoids the "close & reopen Safari password sheet"
        // shuffle the original UX required.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshFromSharedCache),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshFromSharedCache),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        totpRefreshTimer?.invalidate()
        totpRefreshTimer = nil
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Configuration

    private func configureSearch() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search all saved logins"
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.autocorrectionType = .no
        definesPresentationContext = true
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.register(
            CredentialTableViewCell.self,
            forCellReuseIdentifier: CredentialTableViewCell.reuseId
        )
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureEmptyState() {
        // Locked-state card: large icon + title + subtitle + primary CTA.
        lockedStateView.translatesAutoresizingMaskIntoConstraints = false
        lockedStateView.onPrimaryTap = { [weak self] in self?.openHostApp() }
        lockedStateView.onTroubleshootTap = { [weak self] in self?.presentTroubleshootingAlert() }
        view.addSubview(lockedStateView)

        // Plain search-empty label — lives inside the table when `all` is not
        // empty so search results feel native, but we reuse it for the
        // "no saved logins for this site" case as well.
        searchEmptyLabel.numberOfLines = 0
        searchEmptyLabel.textAlignment = .center
        searchEmptyLabel.textColor = .secondaryLabel
        searchEmptyLabel.font = .preferredFont(forTextStyle: .subheadline)
        searchEmptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchEmptyLabel)

        NSLayoutConstraint.activate([
            lockedStateView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            lockedStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lockedStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            lockedStateView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            searchEmptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            searchEmptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -24),
            searchEmptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 28),
            searchEmptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28),
        ])
    }

    /// Attempts to launch the LumenPass host app from the credential-provider
    /// extension. Apple documents `NSExtensionContext.open(_:)` only for Today
    /// and iMessage extensions — credential providers must use the responder-
    /// chain `UIApplication.open` workaround (Bitwarden, 1Password, etc.).
    /// On iOS 18+, the legacy `perform(openURL:)` path silently no-ops, so we
    /// must call `UIApplication.open(_:options:completionHandler:)` directly.
    private func openHostApp() {
        // Path tells the host app to jump straight to its unlock screen when
        // LumenPass resumes, instead of dropping the user on whatever was the
        // last active tab.
        guard let url = URL(string: "lumenpass://autofill/unlock") else { return }

        lpLog("[LumenPassAutoFill] openHostApp: opening \(url.absoluteString)")

        // Signal the host app (via App Group) before we attempt the hand-off.
        LumenPassSharedStore.markPendingAutofillUnlock()

        openContainingApp(url: url, from: self) { [weak self] ok in
            lpLog("[LumenPassAutoFill] openHostApp: finished ok=\(ok)")
            guard !ok else { return }
            self?.presentManualOpenNotice()
        }
    }

    private func findCredentialProviderController() -> ASCredentialProviderViewController? {
        var vc: UIViewController? = self
        while let current = vc {
            if let cpvc = current as? ASCredentialProviderViewController {
                return cpvc
            }
            vc = current.parent
        }
        return nil
    }

    /// Opens the containing app from an extension process. Tries, in order:
    /// 1) `UIApplication.open` via the responder chain (works on device, iOS 18+)
    /// 2) `extensionContext.open` (occasionally succeeds on older iOS)
    /// 3) Legacy `perform(openURL:)` pre-iOS 18 only
    private func openContainingApp(
        url: URL,
        from responder: UIResponder,
        completion: @escaping (Bool) -> Void
    ) {
        var chain: UIResponder? = responder
        while let node = chain {
            if let application = node as? UIApplication {
                lpLog("[LumenPassAutoFill] openContainingApp: UIApplication.open")
                application.open(url, options: [:]) { ok in
                    DispatchQueue.main.async { completion(ok) }
                }
                return
            }
            chain = node.next
        }

        if let cpvc = findCredentialProviderController() {
            lpLog("[LumenPassAutoFill] openContainingApp: trying extensionContext.open")
            cpvc.extensionContext.open(url) { ok in
                DispatchQueue.main.async {
                    if ok {
                        completion(true)
                        return
                    }
                    if #available(iOS 18.0, *) {
                        completion(false)
                    } else {
                        completion(Self.legacyPerformOpenURL(url: url, from: responder))
                    }
                }
            }
            return
        }

        if #available(iOS 18.0, *) {
            lpLog("[LumenPassAutoFill] openContainingApp: no UIApplication in responder chain")
            completion(false)
        } else {
            completion(Self.legacyPerformOpenURL(url: url, from: responder))
        }
    }

    /// Pre-iOS 18 fallback — `perform(openURL:)` on a responder that is not
    /// typed as `UIApplication`. Cannot observe success; treat as best-effort.
    private static func legacyPerformOpenURL(url: URL, from responder: UIResponder) -> Bool {
        let selector = sel_registerName("openURL:")
        var chain: UIResponder? = responder
        while let node = chain {
            if node.responds(to: selector), !(node is UIApplication) {
                lpLog("[LumenPassAutoFill] legacyPerformOpenURL: perform on \(type(of: node))")
                _ = node.perform(selector, with: url)
                return true
            }
            chain = node.next
        }
        lpLog("[LumenPassAutoFill] legacyPerformOpenURL: no responder")
        return false
    }

    private func presentManualOpenNotice() {
        let alert = UIAlertController(
            title: "Switch to LumenPass",
            message: "iOS doesn't allow password extensions to launch apps directly. " +
                     "Swipe up to open LumenPass, unlock your vault, then swipe back here — " +
                     "your logins will appear automatically.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Got it", style: .default))
        present(alert, animated: true)
    }

    private func presentTroubleshootingAlert() {
        let alert = UIAlertController(
            title: "Still not seeing your logins?",
            message: """
            If you already unlocked LumenPass but still see this screen, it's \
            usually one of:

            • The AutoFill provider is off in Settings → Passwords → AutoFill.
            • The Keychain Sharing or App Group entitlement isn't enabled on \
            both targets (development builds only).

            Open LumenPass once, unlock your vault, then swipe back to Safari.
            """,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    /// Called when the autofill popup returns to the foreground — typically
    /// after the user opened LumenPass, unlocked, and swiped back. If the
    /// shared credential cache is now populated, re-load it in place so the
    /// UI updates without the user having to close/reopen Safari's key icon.
    @objc private func refreshFromSharedCache() {
        let fresh = LumenPassSharedStore.load()
        // Skip when nothing has meaningfully changed. We compare by id set so
        // we also catch "same count but entries changed" (e.g. the user
        // locked + unlocked + edited something in between).
        let currentIds = Set(all.map { $0.id })
        let freshIds = Set(fresh.map { $0.id })
        guard !fresh.isEmpty, currentIds != freshIds else {
            return
        }
        lpLog("[LumenPassAutoFill] refreshFromSharedCache: cache rehydrated count=\(fresh.count) (was \(all.count)) — rebuilding list")

        let newMatching: [LumenPassCredential]
        let newDomainContextActive: Bool
        if domainContextActive {
            // Preserve the host-filtered view the controller was originally
            // built with by re-running the same matching rules on the fresh
            // credential set.
            let pageHosts = matching.compactMap { extractHost(from: $0.url) }
            let hostSet = Set(pageHosts.map { $0.lowercased() })
            newMatching = fresh.filter { cred in
                guard let host = extractHost(from: cred.url) else { return false }
                return hostSet.contains(host.lowercased())
            }
            newDomainContextActive = true
        } else {
            newMatching = fresh
            newDomainContextActive = false
        }

        rebuild(matching: newMatching, all: fresh, domainContextActive: newDomainContextActive)
    }

    private func rebuild(matching: [LumenPassCredential],
                         all: [LumenPassCredential],
                         domainContextActive: Bool) {
        self.matching = matching
        self.all = all
        self.domainContextActive = domainContextActive
        if domainContextActive && matching.isEmpty {
            self.visible = []
            self.showingAll = false
        } else {
            self.visible = matching.isEmpty ? all : matching
            self.showingAll = matching.isEmpty
        }
        if !all.isEmpty && (!matching.isEmpty || domainContextActive) {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: showingAll ? "Matching" : "All",
                style: .plain,
                target: self,
                action: #selector(toggleAll)
            )
        } else {
            navigationItem.rightBarButtonItem = nil
        }
        applyVisibleFromCurrentSource()
        tableView.reloadData()
        updateEmptyState()
        startTotpRefreshTimer()
    }

    private func extractHost(from url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return URL(string: withScheme)?.host?.lowercased()
    }

    // MARK: - Actions

    @objc private func cancelTapped() { onCancel() }

    @objc private func toggleAll() {
        showingAll.toggle()
        navigationItem.rightBarButtonItem?.title = showingAll ? "Matching" : "All"
        applyVisibleFromCurrentSource()
        tableView.reloadData()
        updateEmptyState()
        startTotpRefreshTimer()
    }

    private func startTotpRefreshTimer() {
        totpRefreshTimer?.invalidate()
        guard !visible.isEmpty,
              visible.contains(where: { otp in
                  guard let u = otp.otpAuthUrl else { return false }
                  return !u.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            return
        }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tableView.reloadData()
        }
        RunLoop.main.add(timer, forMode: .common)
        totpRefreshTimer = timer
    }

    private func searchQuery() -> String {
        searchController.searchBar.text ?? ""
    }

    private func applyVisibleFromCurrentSource() {
        let trimmedQuery = searchQuery().trimmingCharacters(in: .whitespacesAndNewlines)
        // Typing in the search field always scans the full cached vault so you
        // can pick any login when domain suggestions were wrong or incomplete.
        // (Using only `matching` here left `source` empty when there were zero
        // domain matches, so search appeared broken.)
        let source: [LumenPassCredential]
        if !trimmedQuery.isEmpty {
            source = all
        } else {
            source = showingAll ? all : matching
        }
        visible = filter(source: source, query: searchQuery())
    }

    private func filter(source: [LumenPassCredential], query: String) -> [LumenPassCredential] {
        let needle = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return source }
        return source.filter {
            $0.title.lowercased().contains(needle)
                || $0.username.lowercased().contains(needle)
                || $0.url.lowercased().contains(needle)
                || $0.serviceIdentifier.lowercased().contains(needle)
                || $0.id.lowercased().contains(needle)
        }
    }

    private func updateEmptyState() {
        let hasRows = !visible.isEmpty

        // Locked state = cache is empty → treat as "vault locked on this
        // device" and render the full-screen unlock CTA card.
        let showLockedCard = !hasRows && all.isEmpty

        // Search-only empty = cache is populated but current query/filter
        // produced no rows. Render the small inline label instead.
        let showSearchEmpty = !hasRows && !all.isEmpty

        tableView.isHidden = !hasRows
        lockedStateView.isHidden = !showLockedCard
        searchEmptyLabel.isHidden = !showSearchEmpty
        searchController.searchBar.isHidden = showLockedCard
        navigationItem.searchController = showLockedCard ? nil : searchController

        if !showSearchEmpty { return }

        if !searchQuery().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchEmptyLabel.text = "No matching entries. Try another search or clear the search field."
        } else if domainContextActive && matching.isEmpty {
            searchEmptyLabel.text = "No saved logins for this website.\n\nTap \"All\" to search your full vault."
        } else {
            searchEmptyLabel.text = "No saved logins for this site. Tap \"All\" to browse your vault."
        }
    }
}

// MARK: - LockedStateView

/// Full-screen "Vault locked" hero shown when the shared credential cache is
/// empty. Mirrors the visual language used by the desktop + mobile unlock
/// screens (LumenPass app-icon mark, short copy, primary CTA in brand teal).
private final class LockedStateView: UIView {

    var onPrimaryTap: (() -> Void)?
    var onTroubleshootTap: (() -> Void)?

    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let primaryButton = UIButton(type: .system)
    private let secondaryButton = UIButton(type: .system)
    private let footnoteLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configure() {
        backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1.0)
                : UIColor(red: 0.96, green: 0.97, blue: 1.0, alpha: 1.0)
        }

        // Actual LumenPass app icon, masked into an iOS-style rounded "squircle"
        // and bedded on a soft drop shadow so it reads as an app-icon tile
        // rather than a floating bitmap. The image ships with the extension
        // bundle as LumenPassAppIcon.png (see project.pbxproj).
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFill
        iconImageView.clipsToBounds = true
        // ~22% of 56pt matches Apple's default icon corner radius (squircle).
        iconImageView.layer.cornerRadius = 12
        iconImageView.layer.cornerCurve = .continuous
        iconImageView.layer.borderWidth = 1.0 / UIScreen.main.scale
        iconImageView.layer.borderColor = UIColor.separator.withAlphaComponent(0.3).cgColor
        iconImageView.image = UIImage(named: "LumenPassAppIcon")

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Vault locked"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Unlock LumenPass to see your saved logins and passkeys here."
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.filled()
        config.title = "Unlock LumenPass"
        config.image = UIImage(
            systemName: "arrow.up.right.square.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        )
        config.imagePlacement = .trailing
        config.imagePadding = 8
        // Brand dark-teal — matches the LumenPass primary accent used across
        // the desktop + mobile unlock surfaces.
        config.baseBackgroundColor = UIColor(red: 0.039, green: 0.231, blue: 0.282, alpha: 1.0) // #0A3B48
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        primaryButton.configuration = config
        primaryButton.configurationUpdateHandler = { button in
            guard var cfg = button.configuration else { return }
            var attrs = AttributeContainer()
            attrs.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
            cfg.attributedTitle = AttributedString(cfg.title ?? "", attributes: attrs)
            button.configuration = cfg
        }
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)

        secondaryButton.translatesAutoresizingMaskIntoConstraints = false
        secondaryButton.setTitle("Having trouble?", for: .normal)
        secondaryButton.setTitleColor(.secondaryLabel, for: .normal)
        secondaryButton.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        secondaryButton.addTarget(self, action: #selector(troubleshootTapped), for: .touchUpInside)

        footnoteLabel.translatesAutoresizingMaskIntoConstraints = false
        footnoteLabel.text = "After unlocking, swipe back to Safari — your logins will appear here automatically."
        footnoteLabel.font = .preferredFont(forTextStyle: .caption1)
        footnoteLabel.textColor = .tertiaryLabel
        footnoteLabel.textAlignment = .center
        footnoteLabel.numberOfLines = 0

        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(primaryButton)
        addSubview(secondaryButton)
        addSubview(footnoteLabel)

        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 56),
            iconImageView.heightAnchor.constraint(equalToConstant: 56),
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.bottomAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -20),

            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 44),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -44),

            primaryButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 28),
            primaryButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            primaryButton.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            primaryButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            secondaryButton.topAnchor.constraint(equalTo: primaryButton.bottomAnchor, constant: 12),
            secondaryButton.centerXAnchor.constraint(equalTo: centerXAnchor),

            footnoteLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 36),
            footnoteLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36),
            footnoteLabel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    @objc private func primaryTapped() { onPrimaryTap?() }
    @objc private func troubleshootTapped() { onTroubleshootTap?() }
}

extension CredentialListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visible.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: CredentialTableViewCell.reuseId,
            for: indexPath
        ) as? CredentialTableViewCell else {
            return UITableViewCell()
        }
        let credential = visible[indexPath.row]
        let totp = TotpAuthCode.currentCode(otpAuthUrl: credential.otpAuthUrl)
        cell.configure(credential: credential, totpCode: totp)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelect(visible[indexPath.row])
    }
}

extension CredentialListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        applyVisibleFromCurrentSource()
        tableView.reloadData()
        updateEmptyState()
        startTotpRefreshTimer()
    }
}
