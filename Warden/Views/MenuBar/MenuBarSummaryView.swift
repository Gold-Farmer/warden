import SwiftUI

struct MenuBarSummaryView: View {
    let viewModel: DashboardViewModel
    let settingsViewModel: SettingsViewModel
    let onOpenDashboard: () -> Void

    @State private var addFlowState: AddFlowState = .idle

    private enum AddFlowState: Equatable {
        case idle
        case pickingProvider
        case enteringCredentials(Provider)
    }

    private var insights: [Insight] {
        InsightEngine.evaluate(
            statuses: viewModel.accountStatuses,
            errors: viewModel.errors,
            accounts: viewModel.accountStore.accounts,
            totalCost: viewModel.totalMonthlyCost
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Warden")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.grafanaTextPrimary)
                Spacer()
                StatusBadge(health: viewModel.overallHealth, showLabel: true)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()
                .background(Color.grafanaPanelBorder)

            // Main content
            switch addFlowState {
            case .idle:
                if viewModel.isLoading && viewModel.accountStatuses.isEmpty {
                    loadingView
                } else {
                    insightList
                }
            case .pickingProvider:
                providerGrid
            case .enteringCredentials(let provider):
                credentialForm(for: provider)
            }

            Divider()
                .background(Color.grafanaPanelBorder)

            // Footer
            HStack {
                // Add button
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if addFlowState == .idle {
                            addFlowState = .pickingProvider
                        } else {
                            addFlowState = .idle
                        }
                    }
                } label: {
                    Image(systemName: addFlowState == .idle ? "plus" : "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(addFlowState == .idle ? .grafanaBlue : .grafanaTextSecondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if addFlowState == .idle {
                    if let lastRefresh = viewModel.lastRefresh {
                        Text("Updated \(Formatters.relativeDate.localizedString(for: lastRefresh, relativeTo: Date()))")
                            .font(.system(size: 10))
                            .foregroundStyle(.grafanaTextDisabled)
                    }
                }

                Spacer()

                if addFlowState == .idle {
                    Button("Open Dashboard") {
                        onOpenDashboard()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.grafanaBlue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
                .background(Color.grafanaPanelBorder)

            // Quit
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit Warden")
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.grafanaTextSecondary)
            .padding(.bottom, 4)
        }
        .frame(width: 300)
        .background(Color.grafanaPanelBg)
        .preferredColorScheme(.dark)
        .task {
            if viewModel.accountStore.accounts.isEmpty || viewModel.accountStatuses.isEmpty {
                if !viewModel.isLoading {
                    await viewModel.loadCredentialsAndConfigure()
                    await viewModel.refreshAll()
                    viewModel.scheduler.start()
                }
            }
        }
    }

    // MARK: - Insight List

    private var insightList: some View {
        VStack(spacing: 0) {
            if let top = insights.first {
                topInsightCard(top)
            }

            let rest = Array(insights.dropFirst().prefix(4))
            if !rest.isEmpty {
                Divider()
                    .background(Color.grafanaPanelBorder)
                    .padding(.horizontal, 12)

                ForEach(rest) { insight in
                    insightRow(insight)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func topInsightCard(_ insight: Insight) -> some View {
        HStack(spacing: 10) {
            Image(systemName: insight.icon)
                .font(.system(size: 20))
                .foregroundStyle(insight.iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.grafanaTextPrimary)
                    .lineLimit(2)

                if let detail = insight.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.grafanaTextSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func insightRow(_ insight: Insight) -> some View {
        HStack(spacing: 8) {
            Image(systemName: insight.icon)
                .font(.system(size: 10))
                .foregroundStyle(insight.iconColor)
                .frame(width: 16)

            Text(insight.title)
                .font(.system(size: 11))
                .foregroundStyle(.grafanaTextPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let detail = insight.detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.grafanaTextDisabled)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    // MARK: - Provider Grid

    private var providerGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Account")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.grafanaTextSecondary)
                .padding(.horizontal, 12)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Provider.allCases) { provider in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            addFlowState = .enteringCredentials(provider)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: provider.iconName)
                                .font(.system(size: 18))
                                .foregroundStyle(provider.grafanaColor)
                                .frame(height: 24)
                            Text(provider.shortName)
                                .font(.system(size: 9))
                                .foregroundStyle(.grafanaTextSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.grafanaHoverBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Credential Form

    private enum OpenAIAuthMethod: String, CaseIterable {
        case apiKey = "API Key"
        case chatgpt = "Login with ChatGPT"
        case env = "Environment Variable"
    }

    @State private var openaiAuthMethod: OpenAIAuthMethod = .apiKey
    @State private var formApiKey = ""
    @State private var formOrganizationId = ""
    @State private var formLabel = ""
    @State private var formAwsAccessKeyId = ""
    @State private var formAwsSecretAccessKey = ""
    @State private var formAwsRegion = "us-east-1"
    @State private var formAzureTenantId = ""
    @State private var formAzureClientId = ""
    @State private var formAzureClientSecret = ""
    @State private var formAzureSubscriptionId = ""
    @State private var formCloudflareApiToken = ""
    @State private var formCloudflareAccountId = ""
    @State private var formGcpJSON = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @StateObject private var oauthClient = OpenAIOAuthClient()

    private func credentialForm(for provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Provider header
            HStack(spacing: 8) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(provider.grafanaColor)
                Text(provider.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.grafanaTextPrimary)
            }
            .padding(.horizontal, 12)

            // Fields
            VStack(spacing: 6) {
                TextField("Label (optional)", text: $formLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))

                if provider == .openai {
                    openaiAuthMethodPicker
                    openaiAuthFields
                } else {
                    credentialFields(for: provider)
                    standardActionButtons(for: provider)
                }

                if let error = saveError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.grafanaRed)
                }

                if let error = oauthClient.error {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.grafanaRed)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 10)
    }

    // MARK: - OpenAI Auth Method Picker

    private var openaiAuthMethodPicker: some View {
        HStack(spacing: 0) {
            ForEach(OpenAIAuthMethod.allCases, id: \.self) { method in
                Button {
                    openaiAuthMethod = method
                } label: {
                    Text(method.rawValue)
                        .font(.system(size: 10, weight: openaiAuthMethod == method ? .semibold : .regular))
                        .foregroundStyle(openaiAuthMethod == method ? .grafanaTextPrimary : .grafanaTextDisabled)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(openaiAuthMethod == method ? Color.grafanaHoverBg : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.grafanaPanelBg)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.grafanaPanelBorder)
        )
    }

    // MARK: - OpenAI Auth Fields

    @ViewBuilder
    private var openaiAuthFields: some View {
        switch openaiAuthMethod {
        case .apiKey:
            SecureField("API Key", text: $formApiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            TextField("Organization ID (optional)", text: $formOrganizationId)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            standardActionButtons(for: .openai)

        case .chatgpt:
            if oauthClient.isAuthenticating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for browser login…")
                        .font(.system(size: 11))
                        .foregroundStyle(.grafanaTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                HStack {
                    backButton
                    Spacer()
                    Button("Cancel") {
                        oauthClient.cancel()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.grafanaRed)
                }
            } else {
                Text("Opens your browser to sign in with your ChatGPT account.")
                    .font(.system(size: 10))
                    .foregroundStyle(.grafanaTextSecondary)

                HStack {
                    backButton
                    Spacer()
                    Button {
                        Task { await loginWithChatGPT() }
                    } label: {
                        Label("Login", systemImage: "arrow.up.forward")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

        case .env:
            let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
            if let key = envKey, !key.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.grafanaGreen)
                        .font(.system(size: 12))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("OPENAI_API_KEY detected")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.grafanaTextPrimary)
                        Text("sk-…\(String(key.suffix(4)))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.grafanaTextSecondary)
                    }
                }
                .padding(.vertical, 4)

                HStack {
                    backButton
                    Spacer()
                    Button {
                        Task { await saveWithEnvKey(key) }
                    } label: {
                        Text("Use This Key")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isSaving)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.grafanaRed)
                        .font(.system(size: 12))
                    Text("OPENAI_API_KEY not found in environment")
                        .font(.system(size: 11))
                        .foregroundStyle(.grafanaTextSecondary)
                }
                .padding(.vertical, 4)

                HStack {
                    backButton
                    Spacer()
                }
            }
        }
    }

    // MARK: - Shared Buttons

    private var backButton: some View {
        Button("Back") {
            withAnimation(.easeInOut(duration: 0.15)) {
                addFlowState = .pickingProvider
                resetForm()
            }
        }
        .font(.system(size: 11))
        .buttonStyle(.plain)
        .foregroundStyle(.grafanaTextSecondary)
    }

    private func standardActionButtons(for provider: Provider) -> some View {
        HStack {
            backButton
            Spacer()
            Button {
                Task { await saveNewAccount(provider: provider) }
            } label: {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Add")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isSaving)
        }
    }

    @ViewBuilder
    private func credentialFields(for provider: Provider) -> some View {
        switch provider {
        case .openai:
            EmptyView() // Handled by openaiAuthFields

        case .anthropic, .gemini, .grok:
            SecureField("API Key", text: $formApiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))

        case .aws:
            SecureField("Access Key ID", text: $formAwsAccessKeyId)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            SecureField("Secret Access Key", text: $formAwsSecretAccessKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            TextField("Region", text: $formAwsRegion)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))

        case .azure:
            SecureField("Tenant ID", text: $formAzureTenantId)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            SecureField("Client ID", text: $formAzureClientId)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            SecureField("Client Secret", text: $formAzureClientSecret)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            TextField("Subscription ID", text: $formAzureSubscriptionId)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))

        case .cloudflare:
            SecureField("API Token", text: $formCloudflareApiToken)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            TextField("Account ID", text: $formCloudflareAccountId)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))

        case .gcp:
            TextEditor(text: $formGcpJSON)
                .font(.system(size: 10, design: .monospaced))
                .frame(height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.grafanaPanelBorder)
                )
        }
    }

    private func buildCredentials(for provider: Provider) -> Credentials? {
        switch provider {
        case .openai:
            .openai(apiKey: formApiKey, organizationId: formOrganizationId.isEmpty ? nil : formOrganizationId)
        case .anthropic:
            .anthropic(apiKey: formApiKey)
        case .gemini:
            .gemini(apiKey: formApiKey)
        case .grok:
            .grok(apiKey: formApiKey)
        case .aws:
            .aws(accessKeyId: formAwsAccessKeyId, secretAccessKey: formAwsSecretAccessKey, region: formAwsRegion)
        case .azure:
            .azure(tenantId: formAzureTenantId, clientId: formAzureClientId, clientSecret: formAzureClientSecret, subscriptionId: formAzureSubscriptionId)
        case .cloudflare:
            .cloudflare(apiToken: formCloudflareApiToken, accountId: formCloudflareAccountId)
        case .gcp:
            .gcp(serviceAccountJSON: Data(formGcpJSON.utf8))
        }
    }

    // MARK: - Save Actions

    private func saveNewAccount(provider: Provider) async {
        guard let credentials = buildCredentials(for: provider), credentials.isValid else {
            saveError = "Please fill in required fields"
            return
        }
        await createAndConfigureAccount(provider: provider, credentials: credentials)
    }

    private func loginWithChatGPT() async {
        guard let credentials = await oauthClient.login() else { return }
        await createAndConfigureAccount(provider: .openai, credentials: credentials)
    }

    private func saveWithEnvKey(_ key: String) async {
        let credentials = Credentials.openai(apiKey: key)
        await createAndConfigureAccount(provider: .openai, credentials: credentials)
    }

    private func createAndConfigureAccount(provider: Provider, credentials: Credentials) async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let label = formLabel.isEmpty ? provider.displayName : formLabel
        settingsViewModel.newAccountProvider = provider
        settingsViewModel.newAccountLabel = label
        settingsViewModel.addAccount()

        guard let account = viewModel.accountStore.accounts.last(where: { $0.label == label && $0.providerType == provider }) else {
            saveError = "Failed to create account"
            return
        }

        do {
            try KeychainManager.shared.save(credentials, for: account.id)
        } catch {
            saveError = "Keychain error: \(error.localizedDescription)"
            return
        }

        await viewModel.loadCredentialsAndConfigure()
        await viewModel.refreshAll()

        resetForm()
        withAnimation(.easeInOut(duration: 0.15)) {
            addFlowState = .idle
        }
    }

    private func resetForm() {
        formApiKey = ""
        formOrganizationId = ""
        formLabel = ""
        formAwsAccessKeyId = ""
        formAwsSecretAccessKey = ""
        formAwsRegion = "us-east-1"
        formAzureTenantId = ""
        formAzureClientId = ""
        formAzureClientSecret = ""
        formAzureSubscriptionId = ""
        formCloudflareApiToken = ""
        formCloudflareAccountId = ""
        formGcpJSON = ""
        saveError = nil
        openaiAuthMethod = .apiKey
    }

    // MARK: - Loading

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Fetching status…")
                .font(.system(size: 11))
                .foregroundStyle(.grafanaTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}
