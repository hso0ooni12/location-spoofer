import SwiftUI

enum XSAppLanguage: String, CaseIterable, Identifiable {
    case arabic = "ar"
    case english = "en"

    var id: String { rawValue }
    var shortTitle: String { self == .arabic ? "عربي" : "EN" }
    var accessibilityTitle: LocalizedStringKey { self == .arabic ? "Arabic" : "English" }
}

final class AppLanguageStore: ObservableObject {
    static let shared = AppLanguageStore()
    private let storageKey = "xs-location.language"

    @Published private(set) var language: XSAppLanguage

    private init() {
        if let saved = UserDefaults.standard.string(forKey: storageKey),
           let language = XSAppLanguage(rawValue: saved) {
            self.language = language
        } else if Locale(identifier: Locale.preferredLanguages.first ?? "en").languageCode == "ar" {
            self.language = .arabic
        } else {
            self.language = .english
        }
    }

    var languageCode: String { language.rawValue }
    var locale: Locale { Locale(identifier: language.rawValue) }
    var layoutDirection: LayoutDirection {
        language == .arabic ? .rightToLeft : .leftToRight
    }

    func select(_ language: XSAppLanguage) {
        if self.language != language {
            self.language = language
        }
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
    }
}

enum XSTheme {
    static let ink = Color(red: 0.09, green: 0.13, blue: 0.22)
    static let accent = Color(red: 0.17, green: 0.36, blue: 0.91)
    static let accentDeep = Color(red: 0.11, green: 0.25, blue: 0.73)
    static let sky = Color(red: 0.91, green: 0.95, blue: 1.00)
    static let canvas = Color(red: 0.97, green: 0.98, blue: 1.00)
    static let border = Color(red: 0.87, green: 0.90, blue: 0.96)
    static let orange = Color(red: 1.00, green: 0.62, blue: 0.27)
    static let secondaryText = Color(red: 0.39, green: 0.45, blue: 0.55)
}

struct XSBrandMark: View {
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [XSTheme.accent, XSTheme.accentDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .stroke(.white.opacity(0.34), lineWidth: max(1, size * 0.035))
                .frame(width: size * 0.70, height: size * 0.70)
            Image(systemName: "mappin")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .offset(y: -size * 0.015)
            Circle()
                .fill(XSTheme.orange)
                .frame(width: size * 0.13, height: size * 0.13)
                .overlay(Circle().stroke(XSTheme.accentDeep, lineWidth: 1.5))
                .offset(x: size * 0.23, y: -size * 0.23)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct XSLanguagePicker: View {
    @ObservedObject private var language = AppLanguageStore.shared

    var body: some View {
        HStack(spacing: 3) {
            ForEach(XSAppLanguage.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        language.select(option)
                    }
                } label: {
                    Text(option.shortTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(language.language == option ? .white : XSTheme.secondaryText)
                        .frame(minWidth: 38, minHeight: 34)
                        .background {
                            if language.language == option {
                                Capsule().fill(XSTheme.accent)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(option.accessibilityTitle))
                .accessibilityAddTraits(language.language == option ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.white, in: Capsule())
        .overlay(Capsule().stroke(XSTheme.border, lineWidth: 1))
        .shadow(color: XSTheme.ink.opacity(0.06), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("App language"))
    }
}

enum XSSetupIllustrationKind: Equatable {
    case proxy
    case profile

    var steps: [(String, LocalizedStringKey)] {
        switch self {
        case .proxy:
            return [
                ("iphone", "iPhone"),
                ("wifi", "Wi-Fi"),
                ("checkmark.circle.fill", "Ready")
            ]
        case .profile:
            return [
                ("arrow.down.doc.fill", "Download"),
                ("gearshape.fill", "Install"),
                ("checkmark.shield.fill", "Trust")
            ]
        }
    }
}

struct XSSetupIllustration: View {
    let kind: XSSetupIllustrationKind

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(kind.steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(XSTheme.accent.opacity(0.55))
                        .frame(maxWidth: 18)
                        .accessibilityHidden(true)
                }
                VStack(spacing: 8) {
                    Image(systemName: step.0)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(XSTheme.accent)
                        .frame(width: 48, height: 48)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(XSTheme.border, lineWidth: 1)
                        )
                    Text(step.1)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(XSTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [.white, XSTheme.sky],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(XSTheme.border, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(XSTheme.orange.opacity(0.85))
                .frame(width: 8, height: 8)
                .padding(13)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(kind == .proxy ? "Wi-Fi proxy setup illustration" : "Profile installation illustration"))
    }
}

enum XSSettingsGuideKind {
    case proxy
    case install
    case trust

    var screenTitle: LocalizedStringKey {
        switch self {
        case .proxy: return "Wi-Fi Settings"
        case .install: return "VPN & Device Management"
        case .trust: return "Certificate Trust Settings"
        }
    }

    var rows: [(LocalizedStringKey, LocalizedStringKey?, Bool)] {
        switch self {
        case .proxy:
            return [
                ("Current network", "Connected", false),
                ("Configure Proxy", "Manual", true),
                ("Server", "127.0.0.1", false),
                ("Port", "8888", false)
            ]
        case .install:
            return [
                ("General", nil, false),
                ("VPN & Device Management", nil, true),
                ("Location Spoofer CA", nil, false),
                ("Install", nil, true)
            ]
        case .trust:
            return [
                ("General", nil, false),
                ("About", nil, false),
                ("Certificate Trust Settings", nil, true),
                ("Location Spoofer CA", "ON", true)
            ]
        }
    }
}

struct XSSettingsGuidePreview: View {
    let kind: XSSettingsGuideKind

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(XSTheme.accent)
                    .frame(width: 32, height: 32)
                    .background(XSTheme.sky, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("iOS Settings · Guide")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(XSTheme.ink)
                    Text(kind.screenTitle)
                        .font(.caption2)
                        .foregroundStyle(XSTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XSTheme.secondaryText)
            }

            VStack(spacing: 0) {
                ForEach(Array(kind.rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 8) {
                        Text(row.0)
                            .font(.caption)
                            .foregroundStyle(XSTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        if let detail = row.1 {
                            Text(detail)
                                .font(.caption.weight(row.2 ? .semibold : .regular))
                                .foregroundStyle(row.2 ? XSTheme.accent : XSTheme.secondaryText)
                                .lineLimit(1)
                        }
                        Image(systemName: row.2 ? "checkmark.circle.fill" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(row.2 ? XSTheme.accent : XSTheme.secondaryText.opacity(0.45))
                    }
                    .padding(.horizontal, 11)
                    .frame(minHeight: 36)
                    .background(row.2 ? XSTheme.sky.opacity(0.75) : .white)
                    if index < kind.rows.count - 1 {
                        Divider().padding(.leading, 11)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(XSTheme.border, lineWidth: 1))
        }
        .padding(13)
        .background(XSTheme.sky.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(XSTheme.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct XSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [XSTheme.accent, XSTheme.accentDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
