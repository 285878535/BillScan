import SwiftUI

struct OfflineModelView: View {
    @StateObject private var modelMgr = ModelManager.shared
    @State private var editingProfileID: UUID?
    @State private var draftName = ""
    @State private var draftProtocol: CloudAPIProtocol = .openAICompatible
    @State private var draftBaseURL = ""
    @State private var draftAPIKey = ""
    @State private var draftModelID = ""
    @State private var toastMessage = ""
    @State private var showToast = false
    @State private var isTesting = false
    @State private var testingMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard
                engineSection
                savedProfilesSection
                cloudConfigSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(AppTheme.bgSecondary)
        .navigationTitle("云模型")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadActiveProfile)
        .overlay(alignment: .bottom) {
            if showToast {
                Text(toastMessage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(AppTheme.brandPrimary)
                Text("当前模式")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Text(modelMgr.currentModelName)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)

            Text(modelMgr.parsingModeLabel)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary)

            if let profile = modelMgr.activeCloudProfile {
                HStack(spacing: 8) {
                    Text(profile.trimmedName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(profile.apiProtocol.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.brandPrimary)
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [AppTheme.bgPrimary, AppTheme.brandPrimary.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("识别引擎")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)

            engineOption(
                title: "系统原生引擎",
                subtitle: "使用 Vision OCR，再走内置规则整理。",
                trailing: "内置",
                selected: modelMgr.currentModelType == .system,
                action: { modelMgr.selectModel(for: .system) }
            )

            engineOption(
                title: "自定义云模型",
                subtitle: "支持 OpenAI 兼容和 Anthropic 兼容协议，可保存多个模型配置。",
                trailing: modelMgr.hasValidCloudConfiguration ? "已配置" : "未配置",
                selected: modelMgr.currentModelType == .customCloud,
                action: { modelMgr.selectModel(for: .customCloud) }
            )
        }
    }

    private var savedProfilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("已保存模型")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)

            if modelMgr.cloudProfiles.isEmpty {
                Text("还没有保存的云模型配置。")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(18)
                    .modernCardStyle()
            } else {
                VStack(spacing: 10) {
                    ForEach(modelMgr.cloudProfiles) { profile in
                        savedProfileRow(profile)
                    }
                }
            }
        }
    }

    private var cloudConfigSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑配置")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)

            VStack(alignment: .leading, spacing: 16) {
                inputField(title: "配置名称", text: $draftName, placeholder: "可选，比如：OpenAI 主账号")

                VStack(alignment: .leading, spacing: 8) {
                    Text("协议")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)

                    Picker("协议", selection: $draftProtocol) {
                        ForEach(CloudAPIProtocol.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                inputField(
                    title: "API 地址",
                    text: $draftBaseURL,
                    placeholder: draftProtocol == .openAICompatible ? "https://api.openai.com/v1" : "https://api.anthropic.com/v1"
                )
                secureInputField(title: "API Key", text: $draftAPIKey, placeholder: draftProtocol == .openAICompatible ? "sk-..." : "sk-ant-...")
                inputField(title: "模型名", text: $draftModelID, placeholder: draftProtocol == .openAICompatible ? "gpt-4.1-mini" : "claude-3-5-sonnet-latest")

                VStack(alignment: .leading, spacing: 10) {
                    infoRow(title: "当前生效", value: effectiveProfileLabel)
                    infoRow(title: "Key 状态", value: draftKeyStatus)
                }

                if !testingMessage.isEmpty {
                    Text(testingMessage)
                        .font(.system(size: 13, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(testingMessage == "连接成功" ? .green : .red)
                }

                HStack(spacing: 12) {
                    Button(action: testConnection) {
                        HStack(spacing: 6) {
                            if isTesting {
                                ProgressView()
                                    .tint(AppTheme.brandPrimary)
                            }
                            Text(isTesting ? "测试中" : "测试连通性")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.brandPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.brandPrimary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(isTesting)

                    Button(action: saveConfiguration) {
                        Text(editingProfileID == nil ? "保存模型" : "更新模型")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppTheme.brandPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                HStack(spacing: 12) {
                    Button(action: resetDraft) {
                        Text("新建配置")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppTheme.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Button(role: .destructive, action: deleteCurrentProfile) {
                        Text("删除当前")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(editingProfileID == nil)
                }

                Text(draftProtocol == .openAICompatible ? "OpenAI 兼容协议支持填 `/v1` 或完整 `/chat/completions`。" : "Anthropic 兼容协议支持填 `/v1` 或完整 `/messages`。")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textDisabled)
            }
            .padding(18)
            .modernCardStyle()
        }
    }

    private func savedProfileRow(_ profile: CloudModelProfile) -> some View {
        Button {
            loadProfile(profile)
            modelMgr.setActiveCloudProfile(profile.id)
            modelMgr.selectModel(for: .customCloud)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(profile.trimmedName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)

                        if modelMgr.activeCloudProfileID == profile.id {
                            Text("当前使用")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.brandPrimary)
                                .clipShape(Capsule())
                        }
                    }

                    Text(profile.apiProtocol.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.brandPrimary)

                    Text(profile.trimmedModelID)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(profile.maskedAPIKey)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textDisabled)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textDisabled)
                }
            }
            .padding(16)
            .background(AppTheme.bgPrimary)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(modelMgr.activeCloudProfileID == profile.id ? AppTheme.brandPrimary.opacity(0.45) : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private func engineOption(title: String, subtitle: String, trailing: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)

                        if selected {
                            Text("当前使用")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.brandPrimary)
                                .clipShape(Capsule())
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Text(trailing)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textDisabled)
            }
            .padding(18)
            .background(AppTheme.bgPrimary)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? AppTheme.brandPrimary.opacity(0.45) : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private func inputField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)

            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppTheme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func secureInputField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)

            SecureField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppTheme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var effectiveProfileLabel: String {
        if let editingProfileID, modelMgr.activeCloudProfileID == editingProfileID {
            return "当前配置"
        }
        if !draftModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "待保存"
        }
        return modelMgr.cloudSummary
    }

    private var draftKeyStatus: String {
        let trimmed = draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "未填写"
        }
        if let editingProfileID, modelMgr.activeCloudProfileID == editingProfileID {
            return "已保存"
        }
        return "已填写"
    }

    private func loadActiveProfile() {
        guard let profile = modelMgr.activeCloudProfile else {
            resetDraft()
            return
        }
        loadProfile(profile)
    }

    private func loadProfile(_ profile: CloudModelProfile) {
        editingProfileID = profile.id
        draftName = profile.trimmedName
        draftProtocol = profile.apiProtocol
        draftBaseURL = profile.trimmedBaseURL
        draftAPIKey = profile.trimmedAPIKey
        draftModelID = profile.trimmedModelID
        testingMessage = ""
    }

    private func saveConfiguration() {
        let profile = modelMgr.saveCloudProfile(
            editingID: editingProfileID,
            name: draftName,
            apiProtocol: draftProtocol,
            baseURL: draftBaseURL,
            apiKey: draftAPIKey,
            modelID: draftModelID
        )
        loadProfile(profile)
        modelMgr.selectModel(for: .customCloud)
        presentToast("已保存")
    }

    private func deleteCurrentProfile() {
        guard let editingProfileID else { return }
        modelMgr.deleteCloudProfile(editingProfileID)
        resetDraft()
        presentToast("已删除")
    }

    private func resetDraft() {
        editingProfileID = nil
        draftName = ""
        draftProtocol = .openAICompatible
        draftBaseURL = ""
        draftAPIKey = ""
        draftModelID = ""
        testingMessage = ""
    }

    private func testConnection() {
        let profile = CloudModelProfile(
            id: editingProfileID ?? UUID(),
            name: draftName,
            apiProtocol: draftProtocol,
            baseURL: draftBaseURL,
            apiKey: draftAPIKey,
            modelID: draftModelID
        )

        isTesting = true
        testingMessage = ""
        LocalLLMService.shared.testConnection(profile: profile) { success, message in
            isTesting = false
            testingMessage = message
            presentToast(success ? "连接成功" : "连接失败")
        }
    }

    private func presentToast(_ text: String) {
        toastMessage = text
        withAnimation(.easeInOut(duration: 0.2)) {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showToast = false
            }
        }
    }
}
