import CCEmailCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section("Workspace") {
                LabeledContent("cc-email folder") {
                    HStack {
                        Text(app.check.repoURL?.path ?? (settings.repoPath.isEmpty ? "Not found" : "\(settings.repoPath) (not a cc-email folder)"))
                            .foregroundStyle(app.check.repoURL == nil ? .orange : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { app.chooseWorkspace() }
                    }
                }
            }
            Section("Claude Code") {
                TextField("claude path", text: $settings.claudePath, prompt: Text(app.check.claudePath ?? "Find automatically"))
                LabeledContent("Version", value: app.check.claudeVersion ?? "—")
                LabeledContent("Login") {
                    if let auth = app.check.auth {
                        if auth.usesClaudeCodeLogin {
                            Label("Claude Code login\(auth.subscriptionType.map { " (\($0))" } ?? "")", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("\(auth.authMethod): the app won't run on this", systemImage: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                        }
                    } else {
                        Text("—")
                    }
                }
                Text("CC Email only runs Claude Code on your Claude Code login. It removes ANTHROPIC_API_KEY and other provider settings from claude's environment, checks `claude auth status` before every session, and stops any session that reports other credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Model") { ModelPicker() }
                Toggle("Show replies as they're written", isOn: $settings.streamReplies)
            }
            HStack {
                Spacer()
                if app.check.checking { ProgressView().controlSize(.small) }
                Button("Check Again") { Task { await app.runCheck() } }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .padding(.vertical, 8)
    }
}
