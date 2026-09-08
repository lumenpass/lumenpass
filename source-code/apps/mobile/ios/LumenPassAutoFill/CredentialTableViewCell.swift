// CredentialTableViewCell.swift
//
// Autofill picker row: favicon / initials, title + passkey, subtitle, optional TOTP.

import UIKit

final class CredentialTableViewCell: UITableViewCell {

    static let reuseId = "CredentialTableViewCell"

    private let iconView = UIImageView()
    private let passkeyView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let totpLabel = UILabel()
    private let titleRow = UIStackView()

    private var faviconTask: URLSessionDataTask?
    private var boundCredentialId: String?

    private static let faviconCache = NSCache<NSString, UIImage>()
    private static let iconPayloadCache = NSCache<NSString, UIImage>()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        accessoryType = .disclosureIndicator

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.layer.cornerRadius = 6
        iconView.clipsToBounds = true
        iconView.contentMode = .scaleAspectFill
        iconView.backgroundColor = UIColor.secondarySystemFill

        passkeyView.translatesAutoresizingMaskIntoConstraints = false
        passkeyView.contentMode = .scaleAspectFit
        passkeyView.tintColor = .secondaryLabel
        if let img = UIImage(systemName: "key.fill") {
            passkeyView.image = img
            passkeyView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        }
        passkeyView.isHidden = true

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1

        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1

        totpLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        totpLabel.textColor = .label
        totpLabel.textAlignment = .right
        totpLabel.setContentHuggingPriority(.required, for: .horizontal)
        totpLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleRow.axis = .horizontal
        titleRow.spacing = 6
        titleRow.alignment = .center
        titleRow.addArrangedSubview(titleLabel)
        titleRow.addArrangedSubview(passkeyView)

        let textStack = UIStackView(arrangedSubviews: [titleRow, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let mainRow = UIStackView(arrangedSubviews: [iconView, textStack, totpLabel])
        mainRow.axis = .horizontal
        mainRow.spacing = 10
        mainRow.alignment = .center
        mainRow.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(mainRow)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            passkeyView.widthAnchor.constraint(equalToConstant: 18),
            passkeyView.heightAnchor.constraint(equalToConstant: 18),
            mainRow.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            mainRow.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            mainRow.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            mainRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        faviconTask?.cancel()
        faviconTask = nil
        boundCredentialId = nil
        iconView.image = nil
        passkeyView.isHidden = true
        totpLabel.text = nil
        totpLabel.isHidden = true
    }

    func configure(credential: LumenPassCredential, totpCode: String?) {
        faviconTask?.cancel()
        boundCredentialId = credential.id

        titleLabel.text = credential.title.isEmpty ? credential.serviceIdentifier : credential.title
        subtitleLabel.text = CredentialTableViewCell.subtitle(for: credential)
        passkeyView.isHidden = !credential.hasPasskey

        if let code = totpCode, !code.isEmpty {
            totpLabel.text = code
            totpLabel.isHidden = false
        } else {
            totpLabel.text = nil
            totpLabel.isHidden = true
        }

        let bg = UIColor(argb: credential.avatarBackgroundArgb) ?? UIColor.secondarySystemFill
        let fg = UIColor(argb: credential.avatarForegroundArgb) ?? UIColor.secondaryLabel
        let initials = (credential.avatarInitials?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? String(credential.title.prefix(2)).uppercased()

        let placeholder = CredentialTableViewCell.initialsImage(
            text: String(initials.prefix(2)),
            background: bg,
            foreground: fg,
            size: CGSize(width: 32, height: 32)
        )
        iconView.image = placeholder

        if let iconPayload = credential.iconPngBase64?.trimmingCharacters(in: .whitespacesAndNewlines),
           !iconPayload.isEmpty {
            let key = iconPayload as NSString
            if let cached = Self.iconPayloadCache.object(forKey: key) {
                iconView.image = cached
                return
            }
            if let data = Data(base64Encoded: iconPayload), let image = UIImage(data: data) {
                Self.iconPayloadCache.setObject(image, forKey: key)
                iconView.image = image
                return
            }
            iconView.image = placeholder
            return
        }

        guard let fav = credential.faviconUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !fav.isEmpty,
              let url = URL(string: fav) else {
            iconView.image = placeholder
            return
        }

        let key = fav as NSString
        if let cached = Self.faviconCache.object(forKey: key) {
            iconView.image = cached
            return
        }

        faviconTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let img = UIImage(data: data) else { return }
            Self.faviconCache.setObject(img, forKey: key)
            DispatchQueue.main.async {
                guard let self, self.boundCredentialId == credential.id else { return }
                self.iconView.image = img
            }
        }
        faviconTask?.resume()
    }

    private static func subtitle(for c: LumenPassCredential) -> String {
        let host = c.serviceIdentifier
        if c.username.isEmpty {
            return host
        }
        return "\(c.username) · \(host)"
    }

    private static func initialsImage(
        text: String,
        background: UIColor,
        foreground: UIColor,
        size: CGSize
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            background.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.width * 0.19).fill()
            let font = UIFont.systemFont(ofSize: size.width * 0.36, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: foreground,
            ]
            let s = text as NSString
            let t = s.size(withAttributes: attrs)
            let r = CGRect(
                x: (size.width - t.width) / 2,
                y: (size.height - t.height) / 2,
                width: t.width,
                height: t.height
            )
            s.draw(in: r, withAttributes: attrs)
        }
    }
}

private extension UIColor {
    convenience init?(argb: Int?) {
        guard let v = argb else { return nil }
        let a = CGFloat((v >> 24) & 0xFF) / 255
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
