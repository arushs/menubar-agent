import SwiftUI

struct AgentRowView: View {
    let agent: Agent
    let onOpenTerminal: () -> Void
    let onCopyPath: () -> Void
    let onKill: () -> Void

    @State private var showKillConfirmation = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Agent name and status
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Text(agent.type.displayName)
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                Text(agent.runningTime)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Project path
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text(agent.projectName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }
            .padding(.leading, 18)
            
            // Session stats (if available)
            if let stats = agent.sessionStats, stats.totalTokens > 0 {
                HStack(spacing: 8) {
                    if !stats.formattedTokens.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "text.word.spacing")
                                .font(.system(size: 9))
                            Text(stats.formattedTokens)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    if !stats.formattedCost.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "dollarsign.circle")
                                .font(.system(size: 9))
                            Text(stats.formattedCost)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.leading, 18)
            }

            // Action buttons
            HStack(spacing: 8) {
                Button(action: onOpenTerminal) {
                    HStack(spacing: 4) {
                        Image(systemName: "terminal")
                            .font(.system(size: 10))
                        Text("Terminal")
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button(action: onCopyPath) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                        Text("Copy Path")
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button(action: { showKillConfirmation = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                        Text("Kill")
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.leading, 16)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isHovering ? Color.gray.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            isHovering = hovering
        }
        .alert("Kill Agent?", isPresented: $showKillConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Kill", role: .destructive, action: onKill)
        } message: {
            Text("Are you sure you want to terminate \(agent.type.displayName)?")
        }
    }


}
