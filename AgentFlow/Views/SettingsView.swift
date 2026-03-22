import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultProvider") private var defaultProvider = "claude"
    @AppStorage("gridVisible") private var gridVisible = true
    @AppStorage("openaiAPIKey") private var openaiAPIKey = ""

    @State private var connectionStatus: ConnectionStatus = .untested
    @State private var isTesting = false

    private enum ConnectionStatus {
        case untested
        case success
        case failed(String)
    }

    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                Form {
                    Section("AI Provider") {
                        Picker("Default Provider", selection: $defaultProvider) {
                            Text("Claude (via Claude Code)").tag("claude")
                            Text("OpenAI").tag("openai")
                        }
                    }

                    Section("Canvas") {
                        Toggle("Show Grid", isOn: $gridVisible)
                    }
                }
                .formStyle(.grouped)
            }

            Tab("API Keys", systemImage: "key") {
                Form {
                    Section("OpenAI") {
                        SecureField("API Key", text: $openaiAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: openaiAPIKey) {
                                connectionStatus = .untested
                            }

                        HStack {
                            Button {
                                testOpenAIConnection()
                            } label: {
                                if isTesting {
                                    ProgressView()
                                        .controlSize(.small)
                                        .padding(.trailing, 4)
                                }
                                Text("Test Connection")
                            }
                            .disabled(openaiAPIKey.isEmpty || isTesting)

                            Spacer()

                            connectionStatusView
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .scenePadding()
        .frame(width: 450, height: 300)
    }

    // MARK: - Connection Status View

    @ViewBuilder
    private var connectionStatusView: some View {
        switch connectionStatus {
        case .untested:
            Text("Not tested")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(1)
        }
    }

    // MARK: - Test Connection

    private func testOpenAIConnection() {
        isTesting = true
        connectionStatus = .untested

        Task {
            do {
                let url = URL(string: "https://api.openai.com/v1/models")!
                var request = URLRequest(url: url)
                request.setValue("Bearer \(openaiAPIKey)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 10

                let (_, response) = try await URLSession.shared.data(for: request)

                await MainActor.run {
                    if let httpResponse = response as? HTTPURLResponse {
                        if httpResponse.statusCode == 200 {
                            connectionStatus = .success
                        } else if httpResponse.statusCode == 401 {
                            connectionStatus = .failed("Invalid API key")
                        } else {
                            connectionStatus = .failed("HTTP \(httpResponse.statusCode)")
                        }
                    } else {
                        connectionStatus = .failed("Invalid response")
                    }
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .failed("Connection error")
                    isTesting = false
                }
            }
        }
    }
}
