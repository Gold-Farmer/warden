import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var expandedProvider: Provider?

    var body: some View {
        Form {
            Section("Refresh") {
                Picker("Auto-refresh interval", selection: $viewModel.refreshInterval) {
                    Text("1 minute").tag(TimeInterval(60))
                    Text("5 minutes").tag(TimeInterval(300))
                    Text("15 minutes").tag(TimeInterval(900))
                    Text("30 minutes").tag(TimeInterval(1800))
                    Text("Manual only").tag(TimeInterval(0))
                }
            }

            Section("Cloud Providers") {
                ForEach(Provider.allCases.filter(\.isCloudProvider)) { provider in
                    credentialSection(for: provider)
                }
            }

            Section("AI Services") {
                ForEach(Provider.allCases.filter(\.isAIProvider)) { provider in
                    credentialSection(for: provider)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    @ViewBuilder
    private func credentialSection(for provider: Provider) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedProvider == provider },
                set: { expandedProvider = $0 ? provider : nil }
            )
        ) {
            credentialFields(for: provider)

            HStack {
                Button("Save") {
                    viewModel.save(provider: provider)
                }
                .buttonStyle(.borderedProminent)

                Button("Test Connection") {
                    Task { await viewModel.testConnection(provider: provider) }
                }
                .disabled(viewModel.isTesting[provider] == true)

                if viewModel.isTesting[provider] == true {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                if let result = viewModel.testResults[provider] {
                    switch result {
                    case .success:
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let msg):
                        Label(msg, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }

                Button("Delete", role: .destructive) {
                    viewModel.deleteCredentials(provider: provider)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Image(systemName: provider.iconName)
                    .foregroundStyle(provider.brandColor)
                    .frame(width: 24)
                Text(provider.displayName)
                Spacer()
                if KeychainManager.shared.hasCredentials(for: provider) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func credentialFields(for provider: Provider) -> some View {
        let form = Binding(
            get: { viewModel.credentialForms[provider] ?? SettingsViewModel.CredentialForm() },
            set: { viewModel.credentialForms[provider] = $0 }
        )

        switch provider {
        case .aws:
            SecureField("Access Key ID", text: form.awsAccessKeyId)
            SecureField("Secret Access Key", text: form.awsSecretAccessKey)
            TextField("Region", text: form.awsRegion)
            SecureField("Session Token (optional)", text: form.awsSessionToken)

        case .gcp:
            TextEditor(text: form.gcpServiceAccountJSON)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.quaternary)
                )

        case .azure:
            SecureField("Tenant ID", text: form.azureTenantId)
            SecureField("Client ID", text: form.azureClientId)
            SecureField("Client Secret", text: form.azureClientSecret)
            TextField("Subscription ID", text: form.azureSubscriptionId)

        case .cloudflare:
            SecureField("API Token", text: form.cloudflareApiToken)
            TextField("Account ID", text: form.cloudflareAccountId)

        case .openai:
            SecureField("API Key", text: form.apiKey)
            TextField("Organization ID (optional)", text: form.organizationId)

        case .anthropic, .gemini, .grok:
            SecureField("API Key", text: form.apiKey)
        }
    }
}
