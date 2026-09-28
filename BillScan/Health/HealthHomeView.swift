import SwiftUI
import SwiftData
import UserNotifications

struct HealthRootView: View {
    @ObservedObject private var route = HealthNotificationRoute.shared
    @Query private var documents: [HealthDocument]
    @State private var openedDocument: HealthDocument?
    @State private var missingDocument = false
    private func routeNotification() {
        guard let id = route.documentID else { return }
        if let document = documents.first(where: { $0.id == id }) { openedDocument = document }
        else { missingDocument = true }
        route.documentID = nil
    }
    var body: some View {
        TabView {
            NavigationStack { HealthHomeView() }
                .tabItem { Label("档案", systemImage: "folder.fill") }
            NavigationStack { HealthSettingsView() }
                .tabItem { Label("我的", systemImage: "person") }
        }
        .tint(HealthStyle.sage)
        .preferredColorScheme(.light)
        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        .onChange(of: route.documentID) { _, _ in routeNotification() }
        .task { routeNotification() }
        .sheet(item: $openedDocument) { document in
            NavigationStack {
                HealthDocumentDetailView(document: document)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { openedDocument = nil } } }
            }
        }
        .alert("资料已移除", isPresented: $missingDocument) { Button("好", role: .cancel) {} } message: { Text("这条提醒关联的药方已经被删除。") }
    }
}

struct HealthHomeView: View {
    @Namespace private var cards
    @Environment(\.scenePhase) private var scenePhase
    @State private var nextReminderDate: Date?
    @State private var nextReminderDocument: HealthDocument?
    @Environment(\.modelContext) private var context
    @Query(sort: \HealthEpisode.updatedAt, order: .reverse) private var episodes: [HealthEpisode]
    @State private var search = ""
    @State private var showSearch = false
    @State private var add = false
    @State private var create = false
    @State private var name = ""
    @State private var error: String?
    var filtered: [HealthEpisode] {
        episodes.filter { episode in
            search.isEmpty || episode.name.localizedCaseInsensitiveContains(search) ||
            episode.documents.contains { $0.title.localizedCaseInsensitiveContains(search) || $0.extractedText.localizedCaseInsensitiveContains(search) || $0.medications.contains { $0.name.localizedCaseInsensitiveContains(search) } }
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("我的健康资料").font(.subheadline).foregroundStyle(HealthStyle.muted)
                        Text("病症档案").font(.system(size: 32, weight: .bold))
                        Text("把每次就诊，整理在一起").font(.subheadline).foregroundStyle(HealthStyle.muted)
                    }
                    Spacer()
                    Button { withAnimation(.snappy) { showSearch.toggle() }; if !showSearch { search = "" } } label: {
                        Image(systemName: "magnifyingglass").font(.title3).padding(12).background(.white, in: Circle())
                    }.accessibilityLabel("搜索档案")
                }.padding(.bottom, 6)
                if showSearch {
                    TextField("搜索病症、药名或资料内容", text: $search).padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
                if episodes.isEmpty {
                    ContentUnavailableView {
                        Label("收好第一份健康资料", systemImage: "folder.badge.plus")
                    } description: {
                        Text("按病症建立档案，拍照保存病历与药方。\n资料和识别内容保存在本机。")
                    } actions: { Button("新建病症档案") { create = true }.buttonStyle(.bordered) }
                    .padding(.vertical, 35)
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
                ForEach(filtered) { episode in
                    NavigationLink { EpisodeDetailView(episode: episode).modifier(HealthNavigationDestination(id: episode.id, namespace: cards)) } label: { episodeCard(episode).modifier(HealthNavigationSource(id: episode.id, namespace: cards)) }
                        .buttonStyle(HealthPressStyle())
                }
                if let date = nextReminderDate, let document = nextReminderDocument {
                    NavigationLink { HealthDocumentDetailView(document: document) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bell")
                            Text(HealthDate.time(date) + " 用药提醒").font(.subheadline)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(HealthStyle.muted)
                        }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 19))
                    }.buttonStyle(HealthPressStyle())
                }
                if !episodes.isEmpty {
                    Button { create = true } label: { Label("新建病症档案", systemImage: "folder.badge.plus").frame(maxWidth: .infinity).padding(14) }
                }
            }.padding(22)
        }
        .background(HealthStyle.background).foregroundStyle(HealthStyle.ink)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            HealthAction(title: "添加病历 / 药方") { add = true }.padding(.horizontal, 22).padding(.vertical, 12).background(HealthStyle.background.opacity(0.96))
        }
        .sheet(isPresented: $add) { DocumentEditorView() }
        .alert("新建病症档案", isPresented: $create) {
            TextField("例如：这次感冒", text: $name)
            Button("取消", role: .cancel) { name = "" }
            Button("创建") { createEpisode() }
        } message: { Text("使用方便自己查找的名字，不必填写正式诊断。") }
        .healthError($error)
        .task { await refreshNextReminder() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refreshNextReminder() } } }
    }
    private func refreshNextReminder() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let documents = episodes.flatMap(\.documents)
        let upcoming = requests.compactMap { request -> (Date, HealthDocument)? in
            guard let id = request.content.userInfo["documentID"] as? String,
                  let document = documents.first(where: { $0.id.uuidString == id && !$0.historical }),
                  let date = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() else { return nil }
            return (date, document)
        }.sorted { $0.0 < $1.0 }.first
        nextReminderDate = upcoming?.0
        nextReminderDocument = upcoming?.1
    }
    private func episodeCard(_ episode: HealthEpisode) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: "folder").font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(HealthStyle.sage).padding(.top, 4)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(episode.name).font(.system(size: 21, weight: .semibold)).lineLimit(2)
                    Spacer(minLength: 0)
                    if !episode.archived { HealthBadge(text: "进行中") }
                }
                Text("\(HealthDate.short(episode.updatedAt))更新").font(.caption).foregroundStyle(HealthStyle.muted)
                HStack(spacing: 10) {
                    if let document = episode.documents.first { DocumentThumbnail(document: document, width: 27) }
                    Text("\(episode.documents.filter { $0.kind == .record }.count) 份病历 · \(episode.documents.filter { $0.kind == .prescription }.count) 张药方")
                        .font(.caption).foregroundStyle(HealthStyle.muted)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(HealthStyle.muted)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).healthCard()
    }
    private func createEpisode() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        context.insert(HealthEpisode(name: trimmed))
        do { try context.save(); name = "" } catch { context.rollback(); self.error = error.localizedDescription }
    }
}

struct EpisodeDetailView: View {
    @Namespace private var cards
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var episode: HealthEpisode
    @State private var filter = "全部"
    @State private var prescriptionFilter = "当前药方"
    @State private var add = false
    @State private var rename = false
    @State private var name = ""
    @State private var deleting = false
    @State private var error: String?
    private var documents: [HealthDocument] {
        episode.documents.filter { document in
            guard filter == "全部" || document.kind.rawValue == filter else { return false }
            return filter != "药方" || document.historical == (prescriptionFilter == "历史药方")
        }.sorted { $0.date > $1.date }
    }
    private var dates: [Date] { Array(Set(documents.map { Calendar.current.startOfDay(for: $0.date) })).sorted(by: >) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(episode.name).font(.system(size: 31, weight: .bold))
                    Text("\(HealthDate.short(episode.createdAt))建立 · \(episode.documents.count) 份资料")
                        .font(.subheadline).foregroundStyle(HealthStyle.muted)
                }
                Picker("资料类型", selection: $filter) { ForEach(["全部", "病历", "药方"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                if filter == "药方" {
                    Picker("药方状态", selection: $prescriptionFilter) {
                        Text("当前药方").tag("当前药方")
                        Text("历史药方").tag("历史药方")
                    }.pickerStyle(.segmented)
                }
                if documents.isEmpty { ContentUnavailableView("还没有\(filter == "全部" ? "资料" : filter)", systemImage: "doc.badge.plus", description: Text("添加照片或手动填写，建立完整就诊记录。")) }
                ForEach(dates, id: \.self) { date in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(HealthDate.section(date)).font(.subheadline).foregroundStyle(HealthStyle.muted)
                        ForEach(documents.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }) { document in
                            NavigationLink { HealthDocumentDetailView(document: document).modifier(HealthNavigationDestination(id: document.id, namespace: cards)) } label: {
                                HStack(spacing: 18) {
                                    DocumentThumbnail(document: document)
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(document.title).font(.system(size: 19, weight: .semibold)).foregroundStyle(HealthStyle.ink)
                                        Text(document.kind == .prescription ? "\(document.medications.count) 种药品" : document.institution.isEmpty ? "就诊记录" : document.institution)
                                            .font(.caption).foregroundStyle(HealthStyle.muted)
                                        HealthBadge(text: document.kind == .prescription ? document.historical ? "历史药方" : "当前药方" : document.extractedText.isEmpty ? "手动记录" : "已识别")
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(HealthStyle.muted)
                                }.healthCard().modifier(HealthNavigationSource(id: document.id, namespace: cards))
                            }.buttonStyle(HealthPressStyle())
                        }
                    }
                }
            }.padding(22)
        }.background(HealthStyle.background).navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            Menu {
                Button("重命名", systemImage: "pencil") { name = episode.name; rename = true }
                Button(episode.archived ? "恢复档案" : "归档病症", systemImage: "archivebox") { episode.archived.toggle(); save() }
                Button("删除档案", systemImage: "trash", role: .destructive) { deleting = true }
            } label: { Image(systemName: "ellipsis").padding(8) }.accessibilityLabel("档案操作")
        }
        .safeAreaInset(edge: .bottom) { HealthAction(title: "添加资料") { add = true }.padding(22).background(HealthStyle.background.opacity(0.96)) }
        .sheet(isPresented: $add) { DocumentEditorView(episode: episode) }
        .alert("重命名档案", isPresented: $rename) {
            TextField("档案名称", text: $name)
            Button("取消", role: .cancel) { }
            Button("保存") { if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { episode.name = name; save() } }
        }
        .confirmationDialog("删除此档案及全部资料？此操作无法撤销。", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除全部资料", role: .destructive) {
                let ids = episode.documents.map(\.id)
                context.delete(episode)
                do { try context.save(); Task { for id in ids { await HealthReminders.cancel(documentID: id) } }; dismiss() }
                catch { context.rollback(); self.error = error.localizedDescription }
            }
        }.healthError($error)
    }
    private func save() { do { try context.save() } catch { context.rollback(); self.error = error.localizedDescription } }
}
