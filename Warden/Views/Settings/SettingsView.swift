import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var expandedAccountId: UUID?

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

            Section {
                ForEach(viewModel.accountStore.accounts) { account in
                    accountSection(for: account)
                }

                Button {
                    viewModel.showingAddAccount = true
                } label: {
                    Label("Add Account", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Accounts")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .sheet(isPresented: $viewModel.showingAddAccount) {
            addAccountSheet
        }
    }

    // MARK: - Add Account Sheet

    private var addAccountSheet: some View {
        VStack(spacing: 16) {
            Text("Add Account")
                .font(.headline)

            Picker("Provider", selection: $viewModel.newAccountProvider) {
                ForEach(Provider.allCases) { provider in
                    Label(provider.displayName, systemImage: provider.iconName)
                        .tag(provider)
                }
            }
            .pickerStyle(.menu)

            TextField("Label (optional)", text: $viewModel.newAccountLabel)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    viewModel.showingAddAccount = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    viewModel.addAccount()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 320)
    }

    // MARK: - Per-Account Section

    @ViewBuilder
    private func accountSection(for account: Account) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedAccountId == account.id },
                set: { expandedAccountId = $0 ? account.id : nil }
            )
        ) {
            credentialFields(for: account)

            HStack {
                Button("Save") {
                    viewModel.save(account: account)
                }
                .buttonStyle(.borderedProminent)

                Button("Test Connection") {
                    Task { await viewModel.testConnection(account: account) }
                }
                .disabled(viewModel.isTesting[account.id] == true)

                if viewModel.isTesting[account.id] == true {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                if let result = viewModel.testResults[account.id] {
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
                    viewModel.deleteCredentials(account: account)
                }

                Button("Remove Account", role: .destructive) {
                    viewModel.removeAccount(account)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Image(systemName: account.providerType.iconName)
                    .foregroundStyle(account.providerType.brandColor)
                    .frame(width: 24)
                Text(account.label)
                Text("(\(account.providerType.displayName))")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Spacer()
                if KeychainManager.shared.hasCredentials(for: account.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Credential Fields

    @ViewBuilder
    private func credentialFields(for account: Account) -> some View {
        let form = Binding(
            get: { viewModel.credentialForms[account.id] ?? SettingsViewModel.CredentialForm() },
            set: { viewModel.credentialForms[account.id] = $0 }
        )

        switch account.providerType {
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
