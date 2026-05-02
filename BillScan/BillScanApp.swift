import SwiftUI
import SwiftData

@main
struct BillScanApp: App {
    @State private var showTabBar = true

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Receipt.self,
            Category.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            TabView {
                ReceiptFolderView(showTabBar: $showTabBar)
                    .tabItem {
                        Image(systemName: "folder.fill")
                        Text("票夹")
                    }

                SettingsView(showTabBar: $showTabBar)
                    .tabItem {
                        Image(systemName: "person.fill")
                        Text("我的")
                    }
            }
            .background(AppTheme.bgPrimary.ignoresSafeArea())
            .opacity(showTabBar ? 1 : 1)
        }
        .modelContainer(sharedModelContainer)
    }
}
