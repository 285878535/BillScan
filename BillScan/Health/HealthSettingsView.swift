import SwiftUI
import SwiftData

struct HealthSettingsView: View {
    @Query private var episodes: [HealthEpisode]
    @Query private var documents: [HealthDocument]
    @State private var showLegacy = true
    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "folder.badge.person.crop").font(.largeTitle).foregroundStyle(HealthStyle.sage)
                    VStack(alignment: .leading, spacing: 6) { Text("我的健康资料").font(.title3.bold()); Text("\(episodes.count) 个档案 · \(documents.count) 份资料").font(.subheadline).foregroundStyle(.secondary) }
                }.padding(.vertical, 12)
            }
            Section("数据与隐私") {
                NavigationLink("资料保存说明") {
                    List {
                        Section("保存在这台设备") { Text("病症档案、原始图片、识别文字和药品信息保存在应用的本地数据库中。新健康档案使用系统 Vision 在设备上识别，不上传至云端模型。") }
                        Section("删除与备份") { Text("删除资料或档案时，关联的原图会一起删除，关联用药提醒也会停止。卸载应用可能移除全部本地资料，请保留重要原件或使用设备备份。") }
                        Section("识别与提醒") { Text("识别内容需要逐项核对。提醒按你保存的计划执行，不能替代原医嘱；通知显示受系统权限、专注模式及设备设置影响。") }
                    }.navigationTitle("资料保存说明")
                }
                Link("通知设置", destination: URL(string: UIApplication.openSettingsURLString)!)
            }
            Section("原有资料") {
                NavigationLink("查看旧版票据") { ReceiptFolderView(showTabBar: $showLegacy) }
            }
            Section { HStack { Text("版本"); Spacer(); Text("1.0").foregroundStyle(.secondary) } }
        }.navigationTitle("我的").tint(HealthStyle.sage)
    }
}
