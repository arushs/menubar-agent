import SwiftUI

struct MenuContentView: View {
    @ObservedObject var agentManager: AgentManager
    @Binding var showSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if agentManager.agents.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)

                    Text("No agents running")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    Text("Start Claude Code, Codex, Aider,\nor Cursor Agent to see them here")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                // Agent list
                VStack(spacing: 0) {
                    ForEach(agentManager.agents) { agent in
                        AgentRowView(
                            agent: agent,
                            onOpenTerminal: { agentManager.openInTerminal(agent) },
                            onCopyPath: { agentManager.copyPath(agent) },
                            onKill: { agentManager.killAgent(agent) }
                        )

                        if agent.id != agentManager.agents.last?.id {
                            Divider()
                                .padding(.horizontal, 12)
                        }
                    }
                }
            }

            Divider()
                .padding(.vertical, 8)

            // Footer buttons
            VStack(spacing: 4) {
                Button(action: {
                    Task {
                        await agentManager.refreshAgents()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                Button(action: { showSettings = true }) {
                    HStack {
                        Image(systemName: "gear")
                        Text("Settings...")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.horizontal, 12)

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack {
                        Text("Quit Agent Tracker")
                        Spacer()
                        Text("⌘Q")
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .frame(width: 280)
        .padding(.vertical, 8)
    }
}
