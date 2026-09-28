import SwiftUI
import SwiftData

@main
struct BillScanApp: App {
    @UIApplicationDelegateAdaptor(HealthNotificationDelegate.self) private var notificationDelegate
    @State private var storage: Result<ModelContainer, Error> = Self.openStorage()

    init() { InjectionIIISetup.loadBundle() }

    private static func openStorage() -> Result<ModelContainer, Error> {
        let schema = Schema([Receipt.self, Category.self, HealthEpisode.self, HealthDocument.self])
        #if DEBUG
        let isPreview = ProcessInfo.processInfo.arguments.contains("--health-demo")
        #else
        let isPreview = false
        #endif
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isPreview)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            #if DEBUG
            if isPreview { try HealthPreviewData.populate(container.mainContext) }
            #endif
            return .success(container)
        } catch { return .failure(error) }
    }

    var body: some Scene {
        WindowGroup {
            switch storage {
            case .success(let container):
                HealthRootView().modelContainer(container)
            case .failure(let error):
                ContentUnavailableView {
                    Label("资料库暂时无法打开", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("原有资料不会被清空。请检查设备剩余空间后重试。\n\(error.localizedDescription)")
                } actions: {
                    Button("重试") { storage = Self.openStorage() }.buttonStyle(.borderedProminent)
                }.tint(HealthStyle.sage).preferredColorScheme(.light)
            }
        }
    }
}
