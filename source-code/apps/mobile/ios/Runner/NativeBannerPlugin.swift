import Flutter
import UIKit

final class NativeBannerPlugin: NSObject, FlutterPlugin {
    static let channelName = "com.tranit.lumenpass/native_banner"

    private let presenter = NativeBannerPresenter()

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = NativeBannerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "show":
            guard let args = call.arguments as? [String: Any],
                  let message = args["message"] as? String,
                  !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                result(false)
                return
            }
            let style = NativeBannerStyle(rawValue: args["style"] as? String ?? "") ?? .info
            DispatchQueue.main.async { [weak self] in
                self?.presenter.show(message: message, style: style)
                result(true)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

private enum NativeBannerStyle: String {
    case success
    case error
    case info

    var backgroundColor: UIColor {
        switch self {
        case .success:
            return UIColor(red: 0.09, green: 0.64, blue: 0.29, alpha: 0.98)
        case .error:
            return UIColor(red: 0.79, green: 0.15, blue: 0.15, alpha: 0.98)
        case .info:
            return UIColor(red: 0.11, green: 0.16, blue: 0.20, alpha: 0.98)
        }
    }

    var iconName: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.circle.fill"
        case .info:
            return "info.circle.fill"
        }
    }
}

private final class NativeBannerPresenter {
    private var overlayWindow: UIWindow?
    private var hideWorkItem: DispatchWorkItem?

    func show(message: String, style: NativeBannerStyle) {
        hideCurrent(animated: false)

        guard let windowScene = activeWindowScene() else { return }

        let window = PassthroughWindow(windowScene: windowScene)
        window.backgroundColor = .clear
        window.windowLevel = .alert + 1

        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        window.rootViewController = controller
        window.isHidden = false

        let banner = buildBanner(message: message, style: style)
        controller.view.addSubview(banner)
        banner.translatesAutoresizingMaskIntoConstraints = false

        let topConstraint = banner.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: -120)
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -16),
            topConstraint,
        ])

        controller.view.layoutIfNeeded()
        overlayWindow = window

        let safeTop = window.safeAreaInsets.top > 0 ? window.safeAreaInsets.top : 12
        topConstraint.constant = safeTop + 8

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0.2,
            options: [.curveEaseOut]
        ) {
            controller.view.layoutIfNeeded()
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.hideCurrent(animated: true)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: workItem)
    }

    private func hideCurrent(animated: Bool) {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        guard let window = overlayWindow,
              let controller = window.rootViewController,
              let banner = controller.view.subviews.first else {
            overlayWindow?.isHidden = true
            overlayWindow = nil
            return
        }

        let cleanup = { [weak self] in
            window.isHidden = true
            self?.overlayWindow = nil
        }

        guard animated else {
            cleanup()
            return
        }

        UIView.animate(
            withDuration: 0.22,
            animations: {
                banner.transform = CGAffineTransform(translationX: 0, y: -40)
                banner.alpha = 0
            },
            completion: { _ in
                cleanup()
            }
        )
    }

    private func buildBanner(message: String, style: NativeBannerStyle) -> UIView {
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blurView.clipsToBounds = true
        blurView.layer.cornerRadius = 16

        let tintView = UIView()
        tintView.backgroundColor = style.backgroundColor
        tintView.alpha = 0.9
        tintView.translatesAutoresizingMaskIntoConstraints = false
        blurView.contentView.addSubview(tintView)

        let iconView = UIImageView(image: UIImage(systemName: style.iconName))
        iconView.tintColor = .white
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        blurView.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            tintView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor, constant: -14),
        ])

        return blurView
    }

    private func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}

private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }
}
