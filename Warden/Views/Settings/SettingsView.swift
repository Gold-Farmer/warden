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

            Section("Proxy") {
                proxySection
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
            Picker("Auth Mode", selection: form.awsAuthMode) {
                ForEach(SettingsViewModel.AWSAuthMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if form.awsAuthMode.wrappedValue == .accessKey {
                SecureField("Access Key ID", text: form.awsAccessKeyId)
                SecureField("Secret Access Key", text: form.awsSecretAccessKey)
                TextField("Region", text: form.awsRegion)
                SecureField("Session Token (optional)", text: form.awsSessionToken)
            } else {
                awsProfileFields(form: form)
            }

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

    // MARK: - Proxy Section

    @ViewBuilder
    private var proxySection: some View {
        let proxy = Binding(
            get: { viewModel.proxyStore.configuration },
            set: {
                viewModel.proxyStore.configuration = $0
                // Clear previous test state when config changes
                viewModel.proxyStore.testState = .idle
                viewModel.proxyStore.validationError = nil
            }
        )

        Toggle("Enable Proxy", isOn: proxy.enabled)

        if proxy.enabled.wrappedValue {
            Picker("Protocol", selection: proxy.protocol) {
                ForEach(ProxyProtocol.allCases) { proto in
                    Text(proto.rawValue).tag(proto)
                }
            }
            .pickerStyle(.segmented)

            // Host + Port with inline validation
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Host", text: proxy.host)
                        .textFieldStyle(.roundedBorder)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    viewModel.proxyStore.validationError?.field == "host" ? .red : .clear,
                                    lineWidth: 1.5
                                )
                        )
                }
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Port", value: proxy.port, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    viewModel.proxyStore.validationError?.field == "port" ? .red : .clear,
                                    lineWidth: 1.5
                                )
                        )
                }
            }

            if proxy.protocol.wrappedValue.supportsAuth {
                TextField("Username (optional)", text: proxy.username)
                SecureField("Password (optional)", text: proxy.password)
            }

            TextField("Bypass (comma-separated)", text: Binding(
                get: { proxy.bypassList.wrappedValue.joined(separator: ", ") },
                set: { proxy.bypassList.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            ))
            .font(.system(.body, design: .monospaced))
            .help("Domains that bypass the proxy, e.g. localhost, 127.0.0.1, *.internal")

            // Quick URL import
            HStack {
                TextField("Or paste proxy URL", text: $viewModel.proxyStore.proxyURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .help("e.g. socks5://user:pass@host:1080")
                Button("Apply") {
                    viewModel.proxyStore.applyURL()
                }
                .disabled(viewModel.proxyStore.proxyURL.isEmpty)
            }

            Divider()

            // Save & Test button + status
            proxyTestSection
        }
    }

    @ViewBuilder
    private var proxyTestSection: some View {
        let state = viewModel.proxyStore.testState

        HStack(spacing: 12) {
            Button {
                Task { await viewModel.proxyStore.validateAndTest() }
            } label: {
                HStack(spacing: 6) {
                    if state == .validating || state == .testing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(proxyButtonLabel(for: state))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(state == .validating || state == .testing)

            Spacer()

            // Status display
            switch state {
            case .idle:
                EmptyView()

            case .validating:
                Label("Checking...", systemImage: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)

            case .testing:
                Label("Connecting through proxy...", systemImage: "network")
                    .foregroundStyle(.secondary)
                    .font(.caption)

            case .success:
                ProxySuccessBadge()

            case .failure:
                EmptyView() // Error shown below
            }
        }

        // Error banner
        if case .failure(let message) = state {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Proxy not working")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }

    private func proxyButtonLabel(for state: ProxyStore.ProxyTestState) -> String {
        switch state {
        case .idle: "Save & Test"
        case .validating: "Validating..."
        case .testing: "Testing..."
        case .success: "Save & Test"
        case .failure: "Retry"
        }
    }

    // MARK: - AWS Profile Fields

    @ViewBuilder
    private func awsProfileFields(form: Binding<SettingsViewModel.CredentialForm>) -> some View {
        let profiles = AWSProfileResolver.availableProfiles()

        if profiles.isEmpty {
            Text("No profiles found in ~/.aws/credentials")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("Profile Name", text: form.awsProfileName)
        } else {
            Picker("Profile", selection: form.awsProfileName) {
                ForEach(profiles, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
        }

        TextField("Region Override (optional)", text: form.awsProfileRegionOverride)
            .help("Leave empty to use region from ~/.aws/config")
    }
}
