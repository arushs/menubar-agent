import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("refreshInterval") private var refreshInterval = 5.0
    @AppStorage("hasSeenFirstLaunch") private var hasSeenFirstLaunch = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)

            GroupBox("General") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            setLaunchAtLogin(enabled: newValue)
                        }

                    HStack {
                        Text("Refresh interval:")
                        Picker("", selection: $refreshInterval) {
                            Text("1 second").tag(1.0)
                            Text("5 seconds").tag(5.0)
                            Text("10 seconds").tag(10.0)
                            Text("30 seconds").tag(30.0)
                        }
                        .frame(width: 120)
                    }
                }
                .padding(8)
            }

            GroupBox("Monitored Agents") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(AgentType.allCases) { agentType in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(agentType.displayName)
                                Spacer()
                                Text(agentType.pattern.patterns.first ?? "")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 150)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 320)
    }

    private func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
        }
    }
}

struct FirstLaunchView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("hasSeenFirstLaunch") private var hasSeenFirstLaunch = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Welcome to Agent Tracker")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Monitor your CLI coding agents from the menu bar")
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                Text("Would you like Agent Tracker to start automatically when you log in?")
                    .multilineTextAlignment(.center)

                HStack(spacing: 16) {
                    Button("Not Now") {
                        launchAtLogin = false
                        hasSeenFirstLaunch = true
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("Enable") {
                        launchAtLogin = true
                        setLaunchAtLogin(enabled: true)
                        hasSeenFirstLaunch = true
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(32)
        .frame(width: 400, height: 280)
    }

    private func setLaunchAtLogin(enabled: Bool) {
        do {
            try SMAppService.mainApp.register()
        } catch {
            print("Failed to enable launch at login: \(error)")
        }
    }
}
