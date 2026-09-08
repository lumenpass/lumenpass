import Flutter
import UIKit
import AuthenticationServices

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var privacyBlurView: UIVisualEffectView?
  private var credentialExchangeChannel: FlutterMethodChannel?
  private var pendingCredentialPayload: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let runtimeInfoChannel = FlutterMethodChannel(
        name: "app.runtime.info",
        binaryMessenger: controller.binaryMessenger
      )
      runtimeInfoChannel.setMethodCallHandler { call, result in
        guard call.method == "getInfo" else {
          result(FlutterMethodNotImplemented)
          return
        }

        result([
          "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
          "version": Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
          ) as? String ?? "",
          "buildNumber": Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
          ) as? String ?? "",
        ])
      }

      let cxpChannel = FlutterMethodChannel(
        name: "lumenpass/credential_exchange",
        binaryMessenger: controller.binaryMessenger
      )
      self.credentialExchangeChannel = cxpChannel

      // If a CXP payload arrived before the channel was ready, flush it now.
      cxpChannel.setMethodCallHandler { [weak self] call, result in
        if call.method == "getPending" {
          let pending = self?.pendingCredentialPayload
          self?.pendingCredentialPayload = nil
          result(pending)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    GeneratedPluginRegistrant.register(with: self)

    if let registrar = self.registrar(forPlugin: "AutoFillBridgePlugin") {
      AutoFillBridgePlugin.register(with: registrar)
    }
    if let registrar = self.registrar(forPlugin: "NativeBannerPlugin") {
      NativeBannerPlugin.register(with: registrar)
    }

    // Handle CXP cold launch: when iOS starts the app specifically for a
    // credential exchange, the NSUserActivity is delivered in launchOptions
    // rather than via application(_:continue:restorationHandler:).
    //
    // NOTE: The Apple constant `ASCredentialExchangeActivity` is iOS 26.0+
    // only, but its runtime string value is `ASCredentialExchangeActivityType`
    // (the value declared in NSUserActivityTypes in Info.plist). We compare
    // against that literal here so the activity is recognised on iOS 18.2+.
    if #available(iOS 18.2, *) {
      if let userActivity = launchOptions?[.userActivityDictionary] as? [String: Any],
         let activity = userActivity["UIApplicationLaunchOptionsUserActivityKey"] as? NSUserActivity,
         Self.isCredentialExchangeActivity(activity)
      {
        debugPrint("[CXP] Cold launch with credential exchange activity")
        handleCredentialExchange(userActivity: activity)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "lumenpass", url.host == "autofill" {
      // Extension may have set this before calling UIApplication.open; keep it
      // latched so Flutter can react on the next resume even if the URL was
      // already consumed by the system.
      LumenPassSharedStore.markPendingAutofillUnlock()
    }
    return super.application(app, open: url, options: options)
  }

  // MARK: - Credential Exchange Protocol (CXP)

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    debugPrint("[CXP] continue userActivity: \(userActivity.activityType)")
    if #available(iOS 18.2, *) {
      if Self.isCredentialExchangeActivity(userActivity) {
        debugPrint("[CXP] Warm continuation with credential exchange activity")
        handleCredentialExchange(userActivity: userActivity)
        return true
      }
    }
    return super.application(
      application,
      continue: userActivity,
      restorationHandler: restorationHandler
    )
  }

  /// Check whether a user activity is a CXP credential exchange.
  ///
  /// On iOS 26.0+ the framework exposes the `ASCredentialExchangeActivity`
  /// constant, but on iOS 18.2–25.x we must compare against the raw string
  /// `"ASCredentialExchangeActivityType"` (the value declared in the app's
  /// `NSUserActivityTypes` Info.plist entry).
  private static func isCredentialExchangeActivity(_ activity: NSUserActivity) -> Bool {
    if #available(iOS 26.0, *) {
      return activity.activityType == ASCredentialExchangeActivity
    }
    return activity.activityType == "ASCredentialExchangeActivityType"
  }

  @available(iOS 18.2, *)
  private func handleCredentialExchange(userActivity: NSUserActivity) {
    // Extract the import token. On iOS 26.0+ we use the framework constant;
    // on earlier betas we fall back to the raw key string.
    let token: UUID?
    if #available(iOS 26.0, *) {
      token = userActivity.userInfo?[ASCredentialImportToken] as? UUID
    } else {
      token = userActivity.userInfo?["ASCredentialImportToken"] as? UUID
    }

    guard let token else {
      debugPrint("[CXP] Missing ASCredentialImportToken in userActivity.userInfo: \(String(describing: userActivity.userInfo))")
      return
    }

    debugPrint("[CXP] Got import token: \(token)")

    if #available(iOS 26.0, *) {
      Task { @MainActor in
        do {
          let manager = ASCredentialImportManager()
          let data = try await manager.importCredentials(token: token)

          let encoder = JSONEncoder()
          encoder.dateEncodingStrategy = .iso8601
          let jsonData = try encoder.encode(data)
          let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

          debugPrint("[CXP] Import succeeded, payload length: \(jsonString.count)")

          if let channel = self.credentialExchangeChannel {
            channel.invokeMethod("onImport", arguments: jsonString)
          } else {
            self.pendingCredentialPayload = jsonString
          }
        } catch {
          debugPrint("[CXP] Credential import failed: \(error)")
        }
      }
    } else {
      debugPrint("[CXP] ASCredentialImportManager requires iOS 26.0+")
    }
  }

  // MARK: - App Switcher Privacy Cover
  //
  // iOS snapshots the app window during `applicationWillResignActive` to use
  // as the App Switcher / Recents thumbnail. Installing a blur overlay at that
  // moment ensures the captured snapshot does not expose vault contents.

  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    showPrivacyBlur()
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    hidePrivacyBlur()
  }

  private func showPrivacyBlur() {
    guard privacyBlurView == nil, let window = self.window else { return }
    let effect: UIBlurEffect
    if #available(iOS 13.0, *) {
      effect = UIBlurEffect(style: .systemMaterial)
    } else {
      effect = UIBlurEffect(style: .light)
    }
    let blurView = UIVisualEffectView(effect: effect)
    blurView.frame = window.bounds
    blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    blurView.tag = 0x10BEBEEF
    window.addSubview(blurView)
    window.bringSubviewToFront(blurView)
    privacyBlurView = blurView
  }

  private func hidePrivacyBlur() {
    privacyBlurView?.removeFromSuperview()
    privacyBlurView = nil
  }
}
