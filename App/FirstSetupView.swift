import SwiftUI
import UIKit

private struct SetupScreenshotPreview: Identifiable {
    let id = UUID()
    let image: UIImage
    let title: String
}

private struct CertificateDownloadDestination: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ThirdPartyConnectionTestFailure {
    let message: String
}

enum SetupStep: Int, CaseIterable {
    case mode
    case proxy
    case cert
    case thirdPartyClient
    case thirdPartyImport

    var title: String {
        switch self {
        case .mode: return "选择模式"
        case .proxy: return "Wi-Fi"
        case .cert: return "Profile"
        case .thirdPartyClient: return "选择客户端"
        case .thirdPartyImport: return "导入并检测"
        }
    }
}

struct FirstSetupView: View {
    @ObservedObject var setup: SetupCoordinator
    let onComplete: () -> Void

    @State private var step: SetupStep
    @State private var downloadedDone = false
    @State private var installedDone = false
    @State private var trustedDone = false
    @State private var result: VerificationResult?
    @State private var isVerifying = false
    @State private var isPreparingMode = false
    @State private var manualHint = ""
    @State private var setupActionError = ""
    @State private var showDiagnostics = false
    @StateObject private var diagnosticActions = LocationActionCoordinator()
    @ObservedObject private var runtimeMode = ProxyRuntimeModeStore.shared
    @ObservedObject private var thirdPartyProxy = ThirdPartyProxyManager.shared
    @ObservedObject private var thirdPartyClient = ThirdPartyProxyClientStore.shared
    @State private var copiedSubscriptionURL = false
    @State private var copiedMITMHostname: String?
    @State private var screenshotPreview: SetupScreenshotPreview?
    @State private var certificateDownloadDestination: CertificateDownloadDestination?
    @State private var thirdPartyTestFailure: ThirdPartyConnectionTestFailure?
    @State private var showThirdPartyRepairReason: Bool
    @State private var showsVerificationResult: Bool
    @State private var showsThirdPartyFailureLog: Bool

    init(setup: SetupCoordinator, onComplete: @escaping () -> Void) {
        self.setup = setup
        self.onComplete = onComplete
        _step = State(initialValue: setup.setupStep)
        _showThirdPartyRepairReason = State(
            initialValue: setup.setupStep == .thirdPartyImport && !setup.message.isEmpty
        )
        _showsVerificationResult = State(
            initialValue: [.proxy, .cert].contains(setup.setupStep)
                && setup.lastVerificationResult != nil
        )
        _showsThirdPartyFailureLog = State(
            initialValue: setup.setupStep == .thirdPartyImport && !setup.message.isEmpty
        )
    }

    private var certificateStepsComplete: Bool { downloadedDone && installedDone && trustedDone }
    private var diagnosticFavorite: FavoriteLocation {
        FavoriteLocation(name: "诊断位置", latitude: 22.544577, longitude: 113.94114, accuracy: 25)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    XSBrandMark(size: 42)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("XS Location")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(XSTheme.ink)
                        Text("Simple setup. Precise selection.")
                            .font(.caption)
                            .foregroundStyle(XSTheme.secondaryText)
                    }
                    Spacer(minLength: 4)
                    XSLanguagePicker()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)

                progress
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            switch step {
                            case .mode: modeStep
                            case .proxy: proxyStep
                            case .cert: certificateStep
                            case .thirdPartyClient: thirdPartyClientStep
                            case .thirdPartyImport: thirdPartyImportStep
                            }
                            if let displayedVerificationResult { resultView(displayedVerificationResult) }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                    .onChange(of: thirdPartyFailureLog) { failureLog in
                        guard step == .thirdPartyImport, failureLog != nil else { return }
                        DispatchQueue.main.async {
                            withAnimation {
                                scrollProxy.scrollTo("thirdPartyFailureLog", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: step) { _ in
                        showsVerificationResult = false
                        showsThirdPartyFailureLog = false
                    }
                }
                Divider()
                if step != .mode {
                    HStack(spacing: 12) {
                        Button {
                            returnToPreviousStep()
                        } label: {
                            Label("上一步", systemImage: "chevron.left")
                                .frame(minHeight: 48)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(XSTheme.border, lineWidth: 1))
                        .disabled(isVerifying || thirdPartyProxy.isRequesting)
                        Spacer(minLength: 12)
                        primaryAction
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.white)
                }
            }
            .background(XSTheme.canvas.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $showDiagnostics) {
                NavigationView {
                    RuntimeLogsView(
                        setup: setup,
                        actions: diagnosticActions,
                        testFavorite: diagnosticFavorite
                    )
                }
            }
            .sheet(item: $screenshotPreview) { preview in
                NavigationView {
                    ScrollView {
                        Image(uiImage: preview.image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding()
                    }
                    .navigationTitle(LocalizedStringKey(preview.title))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { screenshotPreview = nil }
                        }
                    }
                }
            }
            .sheet(item: $certificateDownloadDestination) { destination in
                SafariView(url: destination.url)
                    .ignoresSafeArea()
            }
            .alert("无法直接跳转", isPresented: Binding(
                get: { !manualHint.isEmpty },
                set: { if !$0 { manualHint = "" } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: { Text(manualHint) }
            .alert("操作失败", isPresented: Binding(
                get: { !setupActionError.isEmpty },
                set: { if !$0 { setupActionError = "" } }
            )) {
                Button("查看诊断日志") { showDiagnostics = true }
                Button("知道了", role: .cancel) {}
            } message: {
                Text(setupActionError)
            }
        }
    }

    private var progress: some View {
        HStack(spacing: 12) {
            ForEach(visibleSteps, id: \.rawValue) { value in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: value.rawValue <= step.rawValue ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(value.rawValue <= step.rawValue ? XSTheme.accent : XSTheme.secondaryText.opacity(0.55))
                        Text(LocalizedStringKey(value.title))
                            .font(.caption.weight(value == step ? .semibold : .medium))
                            .foregroundStyle(value == step ? XSTheme.ink : XSTheme.secondaryText)
                            .lineLimit(1)
                    }
                    Capsule()
                        .fill(value.rawValue <= step.rawValue ? XSTheme.accent : XSTheme.border)
                        .frame(height: 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 10)
    }

    private var visibleSteps: [SetupStep] {
        switch step {
        case .mode:
            return [.proxy, .cert]
        case .proxy, .cert:
            return [.proxy, .cert]
        case .thirdPartyClient, .thirdPartyImport:
            return [.mode, .thirdPartyClient, .thirdPartyImport]
        }
    }

    private var displayedVerificationResult: VerificationResult? {
        guard showsVerificationResult else { return nil }
        return result ?? setup.lastVerificationResult
    }

    private var thirdPartyFailureLog: String? {
        guard showsThirdPartyFailureLog else { return nil }
        if let thirdPartyTestFailure {
            return thirdPartyTestFailure.message
        }
        guard !setup.message.isEmpty else { return nil }
        return [
            AppLocalization.string("======== 第三方代理运行检测 ========"),
            AppLocalization.string("当前客户端：\(thirdPartyClient.selectedClient.name)"),
            AppLocalization.string("触发来源：地图或设置中的第三方代理操作"),
            AppLocalization.string("请求动作：WLOC 配置接口"),
            AppLocalization.string("检测结果：失败"),
            AppLocalization.string("错误详情：\(setup.message)"),
            AppLocalization.string("处理建议：确认模块已启用，并检查 MITM、证书和代理/VPN 连接。")
        ].joined(separator: "\n")
    }

    private var modeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("选择运行模式")
                .font(.title2.bold())
            Text("后续可在“设置 → 运行模式”中切换。两种模式不要同时拦截 WLOC 请求。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            modeCard(
                title: "APP模式",
                icon: "iphone.and.arrow.forward",
                badges: ["仅 Wi-Fi", "无外部依赖"],
                description: "App 在设备本地启动代理，通过当前 Wi-Fi 的手动 HTTP 代理改写定位响应。免费自签应用无法使用系统 VPN 的 Network Extension 能力，因此 APP模式不支持蜂窝网络，需要配置 Wi-Fi 代理并安装 App 生成的 CA。",
                tint: .blue
            ) {
                selectMode(.localWiFi)
            }
            .disabled(isPreparingMode)

            modeCard(
                title: "第三方代理模式",
                icon: "network.badge.shield.half.filled",
                badges: ["Wi-Fi + 4G/5G", "测试模式"],
                description: "App 负责选点，并通过 WLOC 配置接口查询和同步坐标；第三方代理客户端负责网络代理、模块拦截、MITM 和持久化。证书、VPN 与代理连接均由第三方客户端处理。",
                tint: .orange
            ) {
                selectMode(.thirdParty)
            }
            .disabled(isPreparingMode)

            if isPreparingMode {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在准备 APP模式本地服务…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func modeCard(
        title: LocalizedStringKey,
        icon: String,
        badges: [String],
        description: LocalizedStringKey,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                HStack(spacing: 6) {
                    ForEach(badges, id: \.self) { badge in
                        Text(LocalizedStringKey(badge))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(tint.opacity(0.12), in: Capsule())
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.25)))
        }
        .buttonStyle(.plain)
    }

    private var proxyStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("STEP 1 OF 2 · WI-FI")
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(XSTheme.accent)
                Text("Connect your Wi-Fi proxy")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(XSTheme.ink)
                Text("A quick one-time setup lets XS Location work with your current Wi-Fi network.")
                    .font(.subheadline)
                    .foregroundStyle(XSTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            XSSetupIllustration(kind: .proxy)

            if !setup.message.isEmpty {
                Label(setup.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Follow these three steps")
                    .font(.headline)
                    .foregroundStyle(XSTheme.ink)
                instructionRow(1, "Open Settings → Wi-Fi and tap ⓘ beside the connected network.")
                instructionRow(2, "Choose Configure Proxy, then select Manual.")
                instructionRow(3, "Enter the server and port below, then save.")
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(XSTheme.border, lineWidth: 1))

            XSSettingsGuidePreview(kind: .proxy)

            VStack(spacing: 0) {
                HStack {
                    Label("Proxy details", systemImage: "network")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XSTheme.ink)
                    Spacer()
                    Text("LOCAL")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(XSTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(XSTheme.sky, in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 15)
                proxyValueRow(title: "Server", value: "127.0.0.1")
                Divider().padding(.leading, 16)
                proxyValueRow(title: "Port", value: "8888")
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(XSTheme.border, lineWidth: 1))

            Button { openSettings(.wifi) } label: {
                Label("Open Wi-Fi Settings", systemImage: "wifi")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(XSPrimaryButtonStyle())

            Label("When you return, we’ll check that the proxy is ready.", systemImage: "checkmark.shield")
                .font(.footnote)
                .foregroundStyle(XSTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var certificateStep: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 8) {
                Text("STEP 2 OF 2 · PROFILE")
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(XSTheme.accent)
                Text("Install and trust the profile")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(XSTheme.ink)
                Text("Complete these three checks in iOS Settings. Your location stays protected until the profile is trusted.")
                    .font(.subheadline)
                    .foregroundStyle(XSTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            XSSetupIllustration(kind: .profile)

            if !setup.message.isEmpty {
                Label(setup.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            certificateCard(
                stepNumber: 1,
                title: "Download the profile",
                icon: "arrow.down.circle.fill",
                description: "Tap Download. If iOS asks for permission, choose Allow, then open Settings → Profile Downloaded.",
                actionTitle: "Download profile",
                confirmationTitle: "I downloaded it",
                actionIcon: "arrow.down.circle.fill",
                complete: downloadedDone,
                action: {
                    Task {
                        if let url = await setup.proxy.prepareCertificateDownloadURL() {
                            certificateDownloadDestination = CertificateDownloadDestination(url: url)
                        } else {
                            setupActionError = setup.proxy.error ?? AppLocalization.string("无法准备证书下载页面，请查看诊断日志")
                        }
                    }
                },
                markComplete: { downloadedDone = true }
            )
            XSSettingsGuidePreview(kind: .install)
            certificateCard(
                stepNumber: 2,
                title: "Install the profile",
                icon: "gearshape.fill",
                description: "In Settings, open General → VPN & Device Management, select the downloaded profile, then tap Install.",
                actionTitle: "Open Settings",
                confirmationTitle: "I installed it",
                actionIcon: "gearshape.fill",
                complete: installedDone,
                action: { openSettings(.general) },
                markComplete: { installedDone = true }
            )
            XSSettingsGuidePreview(kind: .trust)
            certificateCard(
                stepNumber: 3,
                title: "Enable full trust",
                icon: "checkmark.shield.fill",
                description: "Open General → About → Certificate Trust Settings and turn on full trust for Location Spoofer CA.",
                actionTitle: "Open Settings",
                confirmationTitle: "I enabled trust",
                actionIcon: "checkmark.shield.fill",
                complete: trustedDone,
                action: { openSettings(.general) },
                markComplete: { trustedDone = true }
            )
            Label("When all three steps are checked, XS Location verifies the setup.", systemImage: "checkmark.shield")
                .font(.footnote)
                .foregroundStyle(XSTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func proxyValueRow(title: LocalizedStringKey, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
            }
            Spacer()
            Button {
                UIPasteboard.general.string = value
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.body.weight(.medium))
                    .frame(width: 42, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("复制"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var thirdPartyMITMWarning: some View {
        Label {
            Text("iOS 27 beta 6 起，系统已禁止对 gs-loc.apple.com 进行 MITM 拦截。该版本及之后的 beta 版本暂时无法使用本项目，等待后续适配方案。")
                .font(.footnote)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var thirdPartyClientStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            thirdPartyMITMWarning
            if !setup.message.isEmpty {
                Label(setup.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            GroupBox(label: Label("选择第三方代理客户端", systemImage: "app.badge.checkmark")) {
                VStack(spacing: 0) {
                    ForEach(ThirdPartyProxyClient.allCases) { client in
                        Button {
                            thirdPartyClient.select(client)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(client.name).foregroundStyle(.primary)
                                    if let verificationText = client.verificationText {
                                        Text(verificationText)
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                Image(systemName: thirdPartyClient.selectedClient == client ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(thirdPartyClient.selectedClient == client ? .blue : .secondary)
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if client != ThirdPartyProxyClient.allCases.last { Divider() }
                    }
                }
            }

            Text("除 Shadowrocket 外，当前客户端配置尚未完成真机验证，页面只提供模块导入入口和通用配置提醒。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            DisclosureGroup("第三方客户端适配说明") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("工作原理")
                        .font(.subheadline.bold())
                    Text("App 不连接远程坐标服务器，而是向 Apple 域名发起一个约定请求。第三方客户端需要在本机拦截该请求、保存 WGS-84 坐标并返回 JSON；定位模块再读取同一份数据，修改 Apple WLOC 响应。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("配置接口")
                        .font(.subheadline.bold())
                    Text(ThirdPartyProxyManager.configurationEndpoint.absoluteString)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Text("""
                    查询：GET ?action=query
                    保存：GET ?lon=<经度>&lat=<纬度>&acc=<精度>
                    清除：GET ?action=clear
                    """)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)

                    Text("返回格式")
                        .font(.subheadline.bold())
                    Text(AppLocalization.string("""
                    成功：{"success":true,"longitude":113.0,"latitude":22.0,"accuracy":25}
                    失败：{"success":false,"error":"错误说明"}
                    """))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)

                    Text("适配要求")
                        .font(.subheadline.bold())
                    Text("客户端需要支持请求脚本、持久化存储、HTTP 200 JSON 响应、Apple WLOC 响应脚本，以及 Apple 定位域名（gs-loc.apple.com、gsp-ssl.ls.apple.com、bluedot.is.autonavi.com 等）的 HTTPS 解密。保存接口和 WLOC 响应脚本必须读取同一份持久化数据。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
    }

    private var thirdPartyImportStep: some View {
        let client = thirdPartyClient.selectedClient
        return VStack(alignment: .leading, spacing: 16) {
            thirdPartyMITMWarning
            if showThirdPartyRepairReason {
                Label(
                    "检测到第三方代理连接异常，请检查模块、MITM 和代理连接后重新检测。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(label: Label("第 1 步：导入 \(client.name) 模块", systemImage: "square.and.arrow.down")) {
                VStack(alignment: .leading, spacing: 12) {
                    instructionRow(1, "复制 \(client.name) 的模块订阅地址。")
                    Button {
                        UIPasteboard.general.string = client.subscriptionURL.absoluteString
                        copiedSubscriptionURL = true
                    } label: {
                        (copiedSubscriptionURL ? Label("已复制模块订阅地址", systemImage: "doc.on.doc") : Label("复制模块订阅地址", systemImage: "doc.on.doc"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    instructionRow(2, client == .shadowrocket
                        ? "打开 Shadowrocket，进入“配置 → 模块”。"
                        : "打开 \(client.name)。")
                    Button {
                        openThirdPartyClient(client)
                    } label: {
                        Label("打开 \(client.name)", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if client == .shadowrocket {
                        setupScreenshot(
                            assetName: "ShadowrocketConfigDetails",
                            title: "进入 Shadowrocket 配置",
                            caption: "1 点击「模块」进入模块列表，2 可打开当前本地配置详情。"
                        )
                    }

                    if client == .shadowrocket {
                        instructionRow(3, "点击右上角“+”，粘贴模块订阅地址并导入，然后确认模块已启用。")
                        setupScreenshot(
                            assetName: "ShadowrocketModuleImport",
                            title: "导入 Shadowrocket 模块",
                            caption: "1 点击右上角加号导入模块，2 确认模块已启用。"
                        )
                    } else {
                        instructionRow(3, "在 \(client.name) 中导入刚才复制的模块订阅地址。")
                    }
                }
            }

            if client == .shadowrocket {
                shadowrocketHTTPSDecryptionGuide
            } else {
                GroupBox(label: Label("第 2 步：完成 \(client.name) 配置", systemImage: "slider.horizontal.3")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("请在 \(client.name) 中完成相应配置。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("配置时请复制下方全部解密域名（含 gsp-ssl.ls.apple.com、bluedot.is.autonavi.com）。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        mitmHostnameList(for: client)
                    }
                }
            }

            if let thirdPartyFailureLog {
                testResultView(
                    success: false,
                    title: AppLocalization.string("接口连接失败"),
                    log: thirdPartyFailureLog
                )
                .id("thirdPartyFailureLog")
            }
        }
    }

    private var shadowrocketHTTPSDecryptionGuide: some View {
        GroupBox(label: Label("第 2 步：配置 HTTPS 解密", systemImage: "lock.open")) {
            VStack(alignment: .leading, spacing: 12) {
                instructionRow(1, "进入“配置 → 本地文件”，找到带黄点的配置，点击右侧 i 图标。")
                instructionRow(2, "进入“HTTPS 解密”，开启解密开关。")
                instructionRow(3, "在域名列表中添加下方复制的全部解密域名。")
                setupScreenshot(
                    assetName: "ShadowrocketHTTPSDecryption",
                    title: "配置 HTTPS 解密",
                    caption: "1 开启 HTTPS 解密，2 添加复制的全部解密域名，3 打开证书设置。"
                )

                mitmHostnameList(for: .shadowrocket)

                instructionRow(4, "按 Shadowrocket 提示生成并完成证书授权。")
                setupScreenshot(
                    assetName: "ShadowrocketHTTPSCA",
                    title: "授权 Shadowrocket 证书",
                    caption: "1 打开 Shadowrocket 证书项并按提示安装、授权。"
                )
                instructionRow(5, "返回 HTTPS 解密页面，点击右上角勾号保存，然后开启代理。")

                Text("App 只能唤起 Shadowrocket，无法通过公开接口直接跳转到“模块”或“HTTPS 解密”页面。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func mitmHostnameList(for client: ThirdPartyProxyClient) -> some View {
        VStack(spacing: 8) {
            ForEach(ThirdPartyProxyManager.interceptionHostnames, id: \.self) { hostname in
                HStack(spacing: 8) {
                    Text(hostname)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        UIPasteboard.general.string = hostname
                        copiedMITMHostname = hostname
                    } label: {
                        Image(systemName: copiedMITMHostname == hostname ? "checkmark" : "doc.on.doc")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(
                        copiedMITMHostname == hostname
                            ? Text("已复制 \(hostname)")
                            : Text("复制 \(hostname)")
                    )
                }
            }

            Button {
                openThirdPartyClient(client)
            } label: {
                Label("打开 \(client.name)", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func instructionRow(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 25, height: 25)
                .background(XSTheme.accent, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(XSTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func setupScreenshot(
        assetName: String,
        title: String,
        caption: String
    ) -> some View {
        if let image = UIImage(named: assetName) {
            Button {
                screenshotPreview = SetupScreenshotPreview(
                    image: image,
                    title: title
                )
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                        Text(LocalizedStringKey(caption))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                }
                .padding(8)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.18))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                Text(LocalizedStringKey(title))
                    + Text(": ")
                    + Text(LocalizedStringKey(caption))
            )
            .accessibilityHint("轻点查看大图")
        }
    }

    private func openThirdPartyClient(_ client: ThirdPartyProxyClient) {
        guard let url = client.launchURL else { return }
        UIApplication.shared.open(url, options: [:]) { opened in
            guard !opened else { return }
            Task { @MainActor in
                manualHint = AppLocalization.string("无法打开 \(client.name)，请确认客户端已安装后手动打开。")
            }
        }
    }

    private func returnToPreviousStep() {
        result = nil
        setupActionError = ""
        switch step {
        case .mode:
            break
        case .proxy, .thirdPartyClient:
            step = .mode
        case .cert:
            step = .proxy
        case .thirdPartyImport:
            thirdPartyTestFailure = nil
            step = .thirdPartyClient
        }
    }

    private func certificateCard(
        stepNumber: Int,
        title: LocalizedStringKey,
        icon: String,
        description: LocalizedStringKey,
        actionTitle: LocalizedStringKey,
        confirmationTitle: LocalizedStringKey,
        actionIcon: String,
        complete: Bool,
        action: @escaping () -> Void,
        markComplete: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(complete ? Color.green.opacity(0.12) : XSTheme.sky)
                    Image(systemName: complete ? "checkmark" : icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(complete ? Color.green : XSTheme.accent)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text("\(stepNumber)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(XSTheme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(XSTheme.sky, in: Capsule())
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(XSTheme.ink)
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(XSTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 9) {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionIcon)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(XSTheme.accent)

                Button(action: markComplete) {
                    Label(
                        complete ? "Completed" : confirmationTitle,
                        systemImage: complete ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.bordered)
                .tint(complete ? .green : XSTheme.secondaryText)
            }
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(complete ? Color.green.opacity(0.30) : XSTheme.border, lineWidth: 1))
    }

    @ViewBuilder
    private func resultView(_ result: VerificationResult) -> some View {
        let success = result.isSuccess
        testResultView(
            success: success,
            title: success ? AppLocalization.string("环境检测通过") : failureSummary(result),
            log: setup.testLog
        )
    }

    private func testResultView(success: Bool, title: String, log: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(success ? .green : .red)
                .font(.subheadline.weight(.semibold))
            if !success {
                Text(log).font(.caption.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(8)
                Button {
                    showDiagnostics = true
                } label: {
                    Label("查看诊断日志", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background((success ? Color.green : Color.red).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var primaryAction: some View {
        if step == .mode {
            EmptyView()
        } else if step == .proxy {
            Button {
                verifyAfterProxyConfirmation()
            } label: {
                actionLabel("继续")
            }
            .buttonStyle(XSPrimaryButtonStyle())
            .disabled(isVerifying)
        } else if step == .cert {
            Button {
                verifyAfterCertificateConfirmation()
            } label: {
                actionLabel("继续")
            }
            .buttonStyle(XSPrimaryButtonStyle())
            .disabled(!certificateStepsComplete || isVerifying)
        } else if step == .thirdPartyClient {
            Button {
                step = .thirdPartyImport
            } label: {
                actionLabel("完成")
            }
                .buttonStyle(XSPrimaryButtonStyle())
        } else {
            Button {
                verifyThirdPartyConnection()
            } label: {
                actionLabel("完成")
            }
                .buttonStyle(XSPrimaryButtonStyle())
            .disabled(isVerifying || thirdPartyProxy.isRequesting)
        }
    }

    private func selectMode(_ mode: ProxyRuntimeMode) {
        guard !isPreparingMode else { return }
        runtimeMode.setMode(mode)
        result = nil
        switch mode {
        case .localWiFi:
            isPreparingMode = true
            Task { @MainActor in
                await setup.prepareLocalServices()
                isPreparingMode = false
                step = .proxy
            }
        case .thirdParty:
            setup.proxy.stop()
            BackgroundKeepAlive.shared.stop()
            step = .thirdPartyClient
        }
    }

    private func verifyThirdPartyConnection() {
        guard !isVerifying else { return }
        let client = thirdPartyClient.selectedClient
        let startedAt = Date()
        isVerifying = true
        result = nil
        thirdPartyTestFailure = nil
        showsThirdPartyFailureLog = false
        setup.message = ""
        RuntimeLogger.info("APP", "ThirdPartyProxy", "开始第三方代理连接检测", details: [
            "当前客户端": client.name,
            "请求动作": "WLOC query",
            "检查范围": "模块拦截、MITM、代理/VPN连接"
        ])
        Task { @MainActor in
            defer { isVerifying = false }
            do {
                let response = try await thirdPartyProxy.query()
                let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
                RuntimeLogger.info("APP", "ThirdPartyProxy", "第三方代理连接检测通过", details: [
                    "当前客户端": client.name,
                    "请求动作": "WLOC query",
                    "连接状态": response.latitude == nil || response.longitude == nil ? "已连接，无保存坐标" : "已连接，有保存坐标",
                    "耗时毫秒": String(elapsedMilliseconds)
                ])
                onComplete()
            } catch {
                let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
                let connectionState = thirdPartyConnectionStateDescription
                let errorType = String(describing: type(of: error))
                RuntimeLogger.error(
                    "APP",
                    "ThirdPartyProxy",
                    "第三方代理连接检测失败",
                    error: error,
                    details: [
                        "当前客户端": client.name,
                        "请求动作": "WLOC query",
                        "连接状态": connectionState,
                        "耗时毫秒": String(elapsedMilliseconds),
                        "错误类型": errorType,
                        "处理建议": ThirdPartyProxyError.recoverySuggestion(for: error)
                    ]
                )
                thirdPartyTestFailure = ThirdPartyConnectionTestFailure(message: [
                    AppLocalization.string("======== 第三方代理连接检测 ========"),
                    AppLocalization.string("当前客户端：\(client.name)"),
                    AppLocalization.string("配置接口：/wloc-settings/save"),
                    AppLocalization.string("请求动作：WLOC query"),
                    AppLocalization.string("检查范围：模块拦截、MITM、证书、代理/VPN 连接"),
                    AppLocalization.string("连接状态：\(connectionState)"),
                    AppLocalization.string("检测结果：失败"),
                    AppLocalization.string("耗时：\(elapsedMilliseconds) ms"),
                    AppLocalization.string("错误类型：\(errorType)"),
                    AppLocalization.string("错误详情：\(error.localizedDescription)"),
                    AppLocalization.string("处理建议：\(ThirdPartyProxyError.recoverySuggestion(for: error))。")
                ].joined(separator: "\n"))
                showsThirdPartyFailureLog = true
            }
        }
    }

    private var thirdPartyConnectionStateDescription: String {
        switch thirdPartyProxy.connectionState {
        case .unknown:
            return AppLocalization.string("未检测")
        case .connected(let active):
            return active ? AppLocalization.string("已连接，有保存坐标") : AppLocalization.string("已连接，无保存坐标")
        case .failed(let message):
            return AppLocalization.string("连接失败（\(message)）")
        }
    }

    private func actionLabel(_ title: LocalizedStringKey) -> some View {
        HStack {
            if isVerifying { ProgressView().tint(.white).controlSize(.small) }
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }

    private func verifyAfterProxyConfirmation() {
        runVerification { result in
            if result.isSuccess {
                onComplete()
            } else if result == .certNotTrusted {
                step = .cert
            } else {
                step = .proxy
            }
        }
    }

    private func verifyAfterCertificateConfirmation() {
        runVerification { result in
            if result.isSuccess {
                onComplete()
            } else if result != .certNotTrusted {
                step = .proxy
            }
        }
    }

    private func runVerification(completion: @escaping (VerificationResult) -> Void) {
        guard !isVerifying else { return }
        isVerifying = true
        result = nil
        showsVerificationResult = false
        Task {
            let verification = await setup.runVerificationTest()
            setup.applyVerificationResult(verification)
            guard !Task.isCancelled else { return }
            result = verification
            showsVerificationResult = true
            isVerifying = false
            completion(verification)
        }
    }

    private func failureSummary(_ result: VerificationResult) -> String {
        switch result {
        case .certNotTrusted: return AppLocalization.string("证书尚未安装或信任")
        case .wifiProxyNotConfigured: return AppLocalization.string("Wi-Fi 代理未正确设置")
        case .proxyNotRunning: return AppLocalization.string("本地代理未能启动")
        case .verificationInProgress: return AppLocalization.string("检测仍在进行")
        case .verificationSuperseded: return AppLocalization.string("检测结果已过期")
        case .coordinateWriteFailed: return AppLocalization.string("坐标写入失败")
        case .patchFailed: return AppLocalization.string("定位改写检测失败")
        case .success: return AppLocalization.string("环境检测通过")
        }
    }

    @MainActor
    private func openSettings(_ destination: SystemSettingsDestination) {
        SystemSettingsNavigator.open(destination) { fallbackHint in
            if let fallbackHint { manualHint = fallbackHint }
        }
    }
}
