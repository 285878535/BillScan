import Foundation
// 与 SwiftUI 注入配合：见 https://github.com/johnno1962/InjectionIII/blob/main/README_Chinese.md 「Injection 在 SwiftUI 中的使用」
@_exported import HotSwiftUI

/// InjectionIII 客户端初始化。
/// - 模拟器：与官方文档一致，从 Mac 端 App 内加载 bundle。
/// - 真机：需按官方文档配置 `copy_bundle.sh` Build Phase、关闭 User Script Sandboxing、`defaults write com.johnholdsworth.InjectionIII deviceUnlock any`，并从 `Bundle.main` 加载嵌入的 `iOSInjection.bundle`。
/// - Xcode 16.3+：工程 Debug 需 `EMIT_FRONTEND_COMMAND_LINES = YES`（已在 project 的 Debug 配置中）。
/// - Debug 链接需 `-Xlinker -interposable`（已在 target Debug 的 Other Linker Flags 中）。
enum InjectionIIISetup {
    static func loadBundle() {
        #if DEBUG
        // 官方示例（模拟器 + Mac 已安装 InjectionIII）：README_Chinese.md「如何使用」
        if let mac = Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/iOSInjection.bundle") {
            mac.load()
        } else if let path = Bundle.main.path(forResource: "iOSInjection", ofType: "bundle"),
                  let embedded = Bundle(path: path) {
            // 真机 + copy_bundle：README_Chinese.md「关于 Injection 在 iOS, tvOS or visionOS 设备上的运行」
            embedded.load()
        }
        #endif
    }
}
