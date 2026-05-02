import Foundation
import Combine

enum CloudAPIProtocol: String, CaseIterable, Codable, Identifiable {
    case openAICompatible = "OpenAI 兼容"
    case anthropicCompatible = "Anthropic 兼容"

    var id: String { rawValue }
}

struct CloudModelProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var apiProtocol: CloudAPIProtocol
    var baseURL: String
    var apiKey: String
    var modelID: String

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedModelID: String {
        modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isComplete: Bool {
        !trimmedBaseURL.isEmpty && !trimmedAPIKey.isEmpty && !trimmedModelID.isEmpty
    }

    var maskedAPIKey: String {
        guard trimmedAPIKey.count > 8 else { return trimmedAPIKey.isEmpty ? "未填写" : "已填写" }
        return "\(trimmedAPIKey.prefix(4))••••\(trimmedAPIKey.suffix(4))"
    }
}

final class ModelManager: ObservableObject {
    static let shared = ModelManager()

    enum ModelType: String, CaseIterable {
        case system = "系统原生引擎"
        case customCloud = "自定义云模型"
    }

    @Published var currentModelName: String {
        didSet { UserDefaults.standard.set(currentModelName, forKey: selectedModelKey) }
    }
    @Published private(set) var cloudProfiles: [CloudModelProfile] {
        didSet { persistProfiles() }
    }
    @Published var activeCloudProfileID: UUID? {
        didSet { UserDefaults.standard.set(activeCloudProfileID?.uuidString, forKey: activeCloudProfileKey) }
    }

    private let selectedModelKey = "SelectedModelName"
    private let cloudProfilesKey = "CloudModelProfiles"
    private let activeCloudProfileKey = "ActiveCloudProfileID"

    private init() {
        let defaults = UserDefaults.standard
        let savedModel = defaults.string(forKey: selectedModelKey)
        currentModelName = ModelType(rawValue: savedModel ?? "")?.rawValue ?? ModelType.system.rawValue

        if let data = defaults.data(forKey: cloudProfilesKey),
           let decoded = try? JSONDecoder().decode([CloudModelProfile].self, from: data) {
            cloudProfiles = decoded
        } else {
            cloudProfiles = []
        }

        if let rawID = defaults.string(forKey: activeCloudProfileKey),
           let uuid = UUID(uuidString: rawID),
           cloudProfiles.contains(where: { $0.id == uuid }) {
            activeCloudProfileID = uuid
        } else {
            activeCloudProfileID = cloudProfiles.first?.id
        }
    }

    var currentModelType: ModelType {
        ModelType(rawValue: currentModelName) ?? .system
    }

    var activeCloudProfile: CloudModelProfile? {
        guard let activeCloudProfileID else { return nil }
        return cloudProfiles.first(where: { $0.id == activeCloudProfileID })
    }

    var parsingModeIsAI: Bool {
        currentModelType == .customCloud && hasValidCloudConfiguration
    }

    var hasValidCloudConfiguration: Bool {
        activeCloudProfile?.isComplete == true
    }

    var cloudProtocol: CloudAPIProtocol {
        activeCloudProfile?.apiProtocol ?? .openAICompatible
    }

    var normalizedCloudBaseURL: String {
        activeCloudProfile?.trimmedBaseURL ?? ""
    }

    var cloudAPIKey: String {
        activeCloudProfile?.trimmedAPIKey ?? ""
    }

    var cloudModelID: String {
        activeCloudProfile?.trimmedModelID ?? ""
    }

    var maskedAPIKey: String {
        activeCloudProfile?.maskedAPIKey ?? "未填写"
    }

    var cloudSummary: String {
        guard let profile = activeCloudProfile else { return "未配置" }
        return profile.trimmedName.isEmpty ? profile.trimmedModelID : profile.trimmedName
    }

    var parsingModeLabel: String {
        switch currentModelType {
        case .system:
            return "Vision OCR + 规则整理"
        case .customCloud:
            return hasValidCloudConfiguration ? "OCR + 云模型整理" : "云模型未配置，当前仍可用系统整理"
        }
    }

    func selectModel(for type: ModelType) {
        currentModelName = type.rawValue
    }

    func setActiveCloudProfile(_ id: UUID) {
        activeCloudProfileID = id
    }

    func saveCloudProfile(
        editingID: UUID?,
        name: String,
        apiProtocol: CloudAPIProtocol,
        baseURL: String,
        apiKey: String,
        modelID: String
    ) -> CloudModelProfile {
        let profile = CloudModelProfile(
            id: editingID ?? UUID(),
            name: {
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedName.isEmpty ? (trimmedModelID.isEmpty ? "未命名模型" : trimmedModelID) : trimmedName
            }(),
            apiProtocol: apiProtocol,
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            modelID: modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if let index = cloudProfiles.firstIndex(where: { $0.id == profile.id }) {
            cloudProfiles[index] = profile
        } else {
            cloudProfiles.insert(profile, at: 0)
        }

        activeCloudProfileID = profile.id
        return profile
    }

    func deleteCloudProfile(_ id: UUID) {
        cloudProfiles.removeAll { $0.id == id }
        if activeCloudProfileID == id {
            activeCloudProfileID = cloudProfiles.first?.id
        }
        if cloudProfiles.isEmpty {
            selectModel(for: .system)
        }
    }

    private func persistProfiles() {
        let data = try? JSONEncoder().encode(cloudProfiles)
        UserDefaults.standard.set(data, forKey: cloudProfilesKey)
    }
}
