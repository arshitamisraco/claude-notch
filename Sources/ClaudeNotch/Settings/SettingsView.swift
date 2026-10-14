import AppKit
import SwiftUI

@MainActor
struct SettingsView: View {
    @Bindable var env: AppEnvironment

    var body: some View {
        TabView(selection: $env.settingsTab) {
            GeneralTab(settings: env.settings)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            HooksTab(settings: env.settings, hooks: env.hooks)
                .tabItem { Label("Hooks", systemImage: "link") }
                .tag(SettingsTab.hooks)
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 500, height: 440)
        .onAppear { env.hooks.refresh() }
    }
}

// MARK: General

@MainActor
private struct GeneralTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                if let error = settings.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else if LaunchAtLogin.requiresApproval {
                    Text(LaunchAtLogin.approvalHint).font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Play sounds", isOn: $settings.soundsEnabled)
                Toggle("Peek at new events", isOn: $settings.peekEnabled)
                Toggle("Show tool failures", isOn: $settings.showToolFailures)
                Toggle("Global shortcut (⌃⌥C)", isOn: $settings.globalHotKeyEnabled)
            }
            Section("Display") {
                Picker("Show notch on", selection: $settings.displayPreference) {
                    Text("Built-in display").tag(DisplayPreference.builtIn)
                    Text("Main display").tag(DisplayPreference.main)
                    Text("Display with the mouse").tag(DisplayPreference.mouse)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Approval hold timeout")
                        Spacer()
                        Text("\(Int(settings.holdTimeout))s").foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $settings.holdTimeout, in: 10...115, step: 5)
                    Text("After this long without a click, the request is released and Claude asks in the terminal as usual.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Hooks

@MainActor
private struct HooksTab: View {
    @Bindable var settings: AppSettings
    let hooks: HooksController

    @State private var portText: String = ""
    @State private var portError: String?
    @State private var pathText: String = ""

    private var statusColor: Color {
        switch hooks.status {
        case .installed: return .green
        case .outdated: return .orange
        case .notInstalled: return .secondary
        case .settingsUnreadable: return .red
        case .hooksDisabled: return .orange
        }
    }

    private var primaryTitle: String {
        switch hooks.status {
        case .installed: return "Reinstall"
        case .outdated: return "Update Hooks"
        default: return "Install Hooks"
        }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(hooks.statusLabel).fontWeight(.medium)
                    Spacer()
                    Button("Uninstall") { hooks.uninstall() }
                        .disabled(hooks.status == .notInstalled || hooks.status == .settingsUnreadable)
                    Button(primaryTitle) { hooks.install() }
                        .buttonStyle(.borderedProminent)
                        .disabled(hooks.status == .settingsUnreadable)
                }
                Text(hooks.diffSummary).font(.caption).foregroundStyle(.secondary)
                if let message = hooks.message {
                    Text(message).font(.caption)
                }
                HStack {
                    Text(hooks.settingsPath).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Reveal Backup") { hooks.revealBackup() }
                        .disabled(!hooks.hasBackup)
                }
            }

            Section("Server") {
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onSubmit(applyPort)
                    Button("Apply", action: applyPort)
                        .disabled(UInt16(portText) == settings.port)
                }
                if let portError = portError {
                    Text(portError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Send terminal headers (enables focus on click)", isOn: $settings.includeTerminalHeaders)
                HStack {
                    Text("Auth token")
                    Spacer()
                    Button("Regenerate Token") {
                        settings.regenerateToken()
                    }
                }
                Text("Regenerating rewrites the installed hooks automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("settings.json location") {
                TextField("Default (~/.claude/settings.json)", text: $pathText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { settings.settingsPathOverride = pathText }
                Text("Optional. Set this if you use CLAUDE_CONFIG_DIR; apps launched from Finder don't see your shell environment. Press Return to apply.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            portText = String(settings.port)
            pathText = settings.settingsPathOverride
        }
    }

    private func applyPort() {
        guard let value = UInt16(portText), value >= 1024 else {
            portError = "Enter a port between 1024 and 65535."
            return
        }
        portError = nil
        settings.port = value
    }
}

// MARK: About

@MainActor
private struct AboutTab: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "sparkle")
                .font(.system(size: 36))
                .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
            Text("Claude Notch").font(.title2.weight(.semibold))
            Text(version).font(.caption).foregroundStyle(.secondary)
            Text("Approve permissions and answer questions from your MacBook's notch. Everything stays on this Mac.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
