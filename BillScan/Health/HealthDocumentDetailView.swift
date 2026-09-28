import SwiftUI
import SwiftData

struct HealthDocumentDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var document: HealthDocument
    @State private var editing = false
    @State private var original = false
    @State private var reminders = false
    @State private var deleting = false
    @State private var tab = "识别内容"
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(document.title).font(.system(size: 31, weight: .bold))
                    Text("\(HealthDate.short(document.date)) · \(document.episode?.name ?? "未归档")")
                        .font(.subheadline).foregroundStyle(HealthStyle.muted)
                }
                if let data = document.images.first, let image = UIImage(data: data) {
                    Button { original = true } label: {
                        Image(uiImage: image).resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: 215, alignment: .top).clipped()
                            .background(Color(hex: "ECEDEE"))
                            .overlay(alignment: .bottomTrailing) {
                                Label("查看原图 · \(document.images.count)页", systemImage: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption).padding(9).background(.black.opacity(0.45), in: Capsule()).foregroundStyle(.white).padding(10)
                            }.clipShape(RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(HealthPressStyle())
                }
                Picker("查看方式", selection: $tab) { Text("识别内容").tag("识别内容"); Text("原文").tag("原文") }.pickerStyle(.segmented)
                if tab == "原文" {
                    Text(document.extractedText.isEmpty ? "暂无识别文字，可在编辑中手动填写。" : document.extractedText)
                        .font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).healthCard()
                } else if document.kind == .prescription {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack { Text("药品与用法").font(.headline); Spacer(); Button("修改", systemImage: "pencil") { editing = true }.font(.caption) }
                        if document.medications.isEmpty { Text("尚未添加药品，请核对原图后填写。").font(.subheadline).foregroundStyle(HealthStyle.muted) }
                        ForEach(document.medications) { medicine in
                            Divider()
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(medicine.name.isEmpty ? "未命名药品" : medicine.name).font(.headline)
                                    Spacer()
                                    if !medicine.isComplete { HealthBadge(text: "用法待确认", warning: true) }
                                }
                                Text(medicine.summary.isEmpty ? "请补充用法" : medicine.summary).font(.subheadline).foregroundStyle(HealthStyle.muted)
                                if medicine.days > 0 { Text("\(HealthDate.short(medicine.startDate))起 · \(medicine.days) 天").font(.caption).foregroundStyle(HealthStyle.muted) }
                                if !medicine.instructions.isEmpty { Text(medicine.instructions).font(.caption).foregroundStyle(HealthStyle.muted) }
                            }
                        }
                    }.healthCard()
                    if !document.historical {
                        Button { reminders = true } label: {
                            HStack(spacing: 15) {
                                Image(systemName: "bell").font(.title2)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("用药提醒").font(.headline)
                                    Text(document.medications.contains(where: \.reminderEnabled) ? "已设置 · 点击调整时间" : "核对药方后，按需开启").font(.caption).foregroundStyle(HealthStyle.muted)
                                    if let through = document.medications.filter(\.reminderEnabled).map({ $0.reminderThrough ?? $0.courseEnd }).min() {
                                        Text("本次安排至 " + HealthDate.short(through)).font(.caption2).foregroundStyle(HealthStyle.muted)
                                    }
                                }
                                Spacer()
                                Image(systemName: document.medications.contains(where: \.reminderEnabled) ? "checkmark.circle.fill" : "chevron.right").foregroundStyle(HealthStyle.sage)
                            }.healthCard()
                        }.buttonStyle(HealthPressStyle())
                    } else { HealthBadge(text: "历史药方 · 提醒已关闭") }
                    HStack {
                        Button("修改识别内容") { editing = true }.frame(maxWidth: .infinity)
                        Button(document.historical ? "恢复为当前药方" : "归入历史药方") { Task { await archive() } }.frame(maxWidth: .infinity)
                    }.font(.subheadline).padding(18).background(Color(hex: "ECEEF0"), in: RoundedRectangle(cornerRadius: 20))
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("就诊记录").font(.headline)
                        if !document.institution.isEmpty { Label(document.institution, systemImage: "building.2").font(.subheadline) }
                        Text(document.extractedText.isEmpty ? "暂无文字记录" : document.extractedText).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading).healthCard()
                }
                if !document.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) { Text("备注").font(.headline); Text(document.notes).textSelection(.enabled) }
                        .frame(maxWidth: .infinity, alignment: .leading).healthCard()
                }
            }.padding(22)
        }.background(HealthStyle.background).foregroundStyle(HealthStyle.ink).navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            Button("编辑") { editing = true }
            Menu { Button("删除资料", systemImage: "trash", role: .destructive) { deleting = true } } label: { Image(systemName: "ellipsis") }.accessibilityLabel("资料操作")
        }
        .sheet(isPresented: $editing) { DocumentEditorView(document: document) }
        .sheet(isPresented: $reminders) { ReminderSettingsView(document: document) }
        .fullScreenCover(isPresented: $original) { DocumentOriginalView(images: document.images) }
        .confirmationDialog("永久删除这份资料和原图？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除资料", role: .destructive) {
                let id = document.id
                document.episode?.updatedAt = Date()
                context.delete(document)
                do { try context.save(); Task { await HealthReminders.cancel(documentID: id) }; dismiss() }
                catch { context.rollback(); self.error = error.localizedDescription }
            }
        }.healthError($error)
    }
    private func archive() async {
        document.historical.toggle()
        var medications = document.medications
        for i in medications.indices { medications[i].reminderEnabled = false }
        document.medications = medications
        do { try context.save(); await HealthReminders.cancel(documentID: document.id) }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}

struct DocumentOriginalView: View {
    @Environment(\.dismiss) private var dismiss
    var images: [Data]
    var body: some View {
        NavigationStack {
            TabView {
                ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                    if let image = UIImage(data: data) { ZoomableDocumentImage(image: image) }
                }
            }.tabViewStyle(.page).background(.black)
                .navigationTitle("原始资料 · \(images.count)页").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct ZoomableDocumentImage: UIViewRepresentable {
    var image: UIImage
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView(); scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 5; scroll.delegate = context.coordinator
        let view = UIImageView(image: image); view.contentMode = .scaleAspectFit; view.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(view); context.coordinator.image = view
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor), view.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
        return scroll
    }
    func updateUIView(_ uiView: UIScrollView, context: Context) { context.coordinator.image?.image = image }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var image: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { image }
    }
}

struct ReminderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var document: HealthDocument
    @State private var medicines: [MedicationEntry] = []
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("提醒时间由你确认，不代表药品推荐服用时间。疗程结束后自动停止。") .font(.subheadline).foregroundStyle(.secondary) }
                if medicines.isEmpty { Section { Text("请先在药方中添加药品并核对用法。") } }
                ForEach($medicines) { $medicine in
                    Section {
                        Toggle(medicine.name.isEmpty ? "未命名药品" : medicine.name, isOn: $medicine.reminderEnabled).disabled(!medicine.isComplete)
                        if !medicine.isComplete { Text("请先编辑药品，补齐用量、次数、天数并确认医嘱。").font(.caption).foregroundStyle(.orange) }
                        if medicine.reminderEnabled {
                            Text("\(medicine.summary) · 原药方疗程 \(medicine.days) 天").font(.caption)
                            if medicine.courseEnd >= Calendar.current.startOfDay(for: Date()) {
                                DatePicker("本次提醒至", selection: Binding(get: { medicine.reminderThrough ?? medicine.courseEnd }, set: { medicine.reminderThrough = $0 }), in: max(Calendar.current.startOfDay(for: Date()), Calendar.current.startOfDay(for: medicine.startDate))...medicine.courseEnd, displayedComponents: .date)
                                Text("仅安排至所选日期。长疗程可分段设置，之后需重新打开药方继续安排；不会修改原药方的疗程。").font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(medicine.times.indices, id: \.self) { i in
                                DatePicker("第 \(i + 1) 次", selection: Binding(get: {
                                    Calendar.current.date(bySettingHour: medicine.times[i] / 60, minute: medicine.times[i] % 60, second: 0, of: Date()) ?? Date()
                                }, set: { value in let c = Calendar.current.dateComponents([.hour, .minute], from: value); medicine.times[i] = (c.hour ?? 0) * 60 + (c.minute ?? 0) }), displayedComponents: .hourAndMinute)
                            }
                        }
                    }.onChange(of: medicine.reminderEnabled) { _, enabled in
                        if enabled && medicine.times.count != medicine.frequency {
                            // Editable suggested times are visible before explicit Save; not inferred clinical instructions.
                            medicine.times = (0..<medicine.frequency).map { 8 * 60 + $0 * (12 * 60 / max(1, medicine.frequency - 1)) }
                        }
                    }
                }
                Section { Link("打开系统通知设置", destination: URL(string: UIApplication.openSettingsURLString)!) }
            }.navigationTitle("用药提醒").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(saving) }
                }
                .interactiveDismissDisabled(saving)
                .task { medicines = document.medications }
                .healthError($error)
        }.tint(HealthStyle.sage)
    }
    private func save() async {
        saving = true; defer { saving = false }
        let previous = document.medications
        do {
            try await HealthReminders.schedule(documentID: document.id, medications: medicines, historical: document.historical)
            document.medications = medicines
            try context.save(); dismiss()
        } catch {
            context.rollback()
            try? await HealthReminders.schedule(documentID: document.id, medications: previous, historical: document.historical)
            self.error = error.localizedDescription
        }
    }
}
