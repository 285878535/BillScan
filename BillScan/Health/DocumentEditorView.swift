import SwiftUI
import SwiftData
import PhotosUI
import VisionKit

struct DocumentEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HealthEpisode.updatedAt, order: .reverse) private var episodes: [HealthEpisode]
    var episode: HealthEpisode?
    var document: HealthDocument?
    @State private var selectedEpisode: UUID?
    @State private var newEpisodeName = ""
    @State private var title = "门诊病历"
    @State private var kind = HealthDocumentKind.record
    @State private var date = Date()
    @State private var institution = ""
    @State private var notes = ""
    @State private var text = ""
    @State private var images: [Data] = []
    @State private var medicines: [MedicationEntry] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var scan = false
    @State private var busy = false
    @State private var saving = false
    @State private var loaded = false
    @State private var error: String?
    @State private var discard = false
    @State private var recognitionMessage = ""
    private var valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (selectedEpisode != nil || !newEpisodeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        (!images.isEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (kind == .prescription && medicines.contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !images.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                                    if let image = UIImage(data: data) {
                                        VStack {
                                            Image(uiImage: image).resizable().scaledToFit().frame(width: 110, height: 140).clipShape(RoundedRectangle(cornerRadius: 12))
                                            Button("移除第 \(index + 1) 页", role: .destructive) { images.remove(at: index) }.font(.caption)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    HStack {
                        Button { scan = true } label: { Label("拍照扫描", systemImage: "camera") }
                            .disabled(!VNDocumentCameraViewController.isSupported || busy)
                        Spacer()
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 12, matching: .images) { Label("相册上传", systemImage: "photo") }.disabled(busy)
                    }.buttonStyle(.borderless)
                    if busy { HStack { ProgressView(); Text("正在本机识别…") } }
                    if !recognitionMessage.isEmpty { Text(recognitionMessage).font(.caption).foregroundStyle(.secondary) }
                } header: { Text("原始资料") } footer: { Text("支持多页图片；识别只在本机完成。也可以直接手动填写。") }
                Section("归入病症") {
                    Picker("病症档案", selection: $selectedEpisode) {
                        Text("新建档案").tag(Optional<UUID>.none)
                        ForEach(episodes) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if selectedEpisode == nil { TextField("病症名称，例如：这次感冒", text: $newEpisodeName).accessibilityIdentifier("episodeName") }
                }
                Section("资料信息") {
                    Picker("类型", selection: $kind) { ForEach(HealthDocumentKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    TextField("资料标题", text: $title).accessibilityIdentifier("documentTitle")
                    DatePicker("就诊日期", selection: $date, displayedComponents: .date)
                    TextField("医院 / 就诊机构（选填）", text: $institution)
                }
                if kind == .prescription {
                    Section {
                        ForEach($medicines) { $medicine in
                            NavigationLink { MedicationEditorView(medicine: $medicine) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(medicine.name.isEmpty ? "填写药品名称" : medicine.name)
                                    Text(medicine.summary.isEmpty ? "补充用量和频次" : medicine.summary).font(.caption).foregroundStyle(.secondary)
                                    if !medicine.confirmed { HealthBadge(text: "待核对", warning: true) }
                                }
                            }
                        }.onDelete { medicines.remove(atOffsets: $0) }
                        Button { medicines.append(MedicationEntry()) } label: { Label("添加药品", systemImage: "plus") }
                    } header: { Text("药品与用法") } footer: { Text("识别可能遗漏或出错。用量、频次和疗程请逐项核对原药方，缺失信息不会根据药名推断。") }
                }
                Section("识别原文 · 可修改") {
                    TextEditor(text: $text).frame(minHeight: 160).accessibilityLabel("识别原文").accessibilityIdentifier("documentText")
                }
                Section("备注") { TextField("记录症状、复诊安排等", text: $notes, axis: .vertical).lineLimit(3...6) }
            }
            .navigationTitle(document == nil ? "添加资料" : "编辑资料").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { discard = true }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button { Task { await save() } } label: { if saving { ProgressView() } else { Text("保存") } }.disabled(!valid || busy || saving) }
            }
            .interactiveDismissDisabled()
            .confirmationDialog("放弃本次未保存的修改？", isPresented: $discard, titleVisibility: .visible) { Button("放弃修改", role: .destructive) { dismiss() } }
            .sheet(isPresented: $scan) {
                HealthScanner { result in
                    scan = false
                    switch result {
                    case .success(let pages): Task { await importPages(pages) }
                    case .failure(let failure): error = failure.localizedDescription
                    }
                }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    busy = true
                    var data: [Data] = []
                    do {
                        for item in items { if let value = try await item.loadTransferable(type: Data.self) { data.append(value) } }
                        busy = false
                        await importPages(data)
                        photoItems = []
                    } catch { busy = false; self.error = error.localizedDescription }
                }
            }
            .onChange(of: kind) { _, newKind in
                if title == "门诊病历" || title == "门诊药方" { title = newKind == .record ? "门诊病历" : "门诊药方" }
            }
            .task { load() }
            .healthError($error)
        }.tint(HealthStyle.sage)
    }
    private func load() {
        guard !loaded else { return }; loaded = true
        selectedEpisode = episode?.id ?? document?.episode?.id
        guard let document else { return }
        title = document.title; kind = document.kind; date = document.date
        institution = document.institution; notes = document.notes; text = document.extractedText
        images = document.images; medicines = document.medications
    }
    private func importPages(_ pages: [Data]) async {
        busy = true
        defer { busy = false }
        var failures = 0
        for data in pages {
            guard UIImage(data: data) != nil else { failures += 1; continue }
            images.append(data)
            do {
                let result = try await HealthOCR.recognize(data)
                if text.isEmpty { kind = result.kind }
                text += (text.isEmpty ? "" : "\n\n—— 第 \(images.count) 页 ——\n") + result.text
                medicines.append(contentsOf: result.medications)
            } catch { failures += 1 }
        }
        recognitionMessage = failures == 0 ? "已保留原图。请核对识别文字与药品信息后保存。" : "\(failures) 页未能完成识别；可读原图已保留，请手动补充。"
    }
    private func save() async {
        saving = true
        defer { saving = false }
        let target = document ?? HealthDocument(title: title, kind: kind)
        let targetID = target.id
        let previousMedicines = target.medications
        let previousHistorical = target.historical
        // Editing prescription details invalidates existing notification schedules until saved consistently.
        if kind != .prescription { medicines = [] }
        do {
            try await HealthReminders.schedule(documentID: targetID, medications: medicines, historical: target.historical)
            let targetEpisode: HealthEpisode
            if let selectedEpisode, let existing = episodes.first(where: { $0.id == selectedEpisode }) { targetEpisode = existing }
            else {
                targetEpisode = HealthEpisode(name: newEpisodeName.trimmingCharacters(in: .whitespacesAndNewlines))
                context.insert(targetEpisode)
            }
            if document == nil { context.insert(target) }
            target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            target.kind = kind; target.date = date; target.institution = institution; target.notes = notes
            target.extractedText = text; target.images = images; target.medications = medicines
            target.episode = targetEpisode; targetEpisode.updatedAt = Date()
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            if document != nil { try? await HealthReminders.schedule(documentID: targetID, medications: previousMedicines, historical: previousHistorical) }
            else { await HealthReminders.cancel(documentID: targetID) }
            self.error = error.localizedDescription
        }
    }
}

struct MedicationEditorView: View {
    @Binding var medicine: MedicationEntry
    var body: some View {
        Form {
            Section("药品信息") {
                TextField("药品名称", text: $medicine.name)
                TextField("每次用量，例如：1片", text: $medicine.dose)
                Picker("每日次数", selection: $medicine.frequency) {
                    Text("待确认 / 非固定频次").tag(0)
                    ForEach(1...6, id: \.self) { Text("每日 \($0) 次").tag($0) }
                }
                TextField("原药方服用要求，例如：饭后", text: $medicine.instructions, axis: .vertical)
            }
            Section("疗程") {
                DatePicker("开始用药", selection: $medicine.startDate, displayedComponents: .date)
                HStack { Text("用药天数"); Spacer(); TextField("待补充", value: $medicine.days, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
            }
            Section {
                Toggle("我已按原药方核对以上信息", isOn: $medicine.confirmed)
            } footer: { Text("按需服用、每隔若干小时等特殊用法，请保留原始医嘱。固定时刻提醒仅支持确认后的每日用药计划。") }
        }.navigationTitle("药品用法").navigationBarTitleDisplayMode(.inline)
            .onChange(of: medicine.name) { _, _ in invalidate() }
            .onChange(of: medicine.dose) { _, _ in invalidate() }
            .onChange(of: medicine.frequency) { _, _ in invalidate(); medicine.times = [] }
            .onChange(of: medicine.days) { _, _ in invalidate() }
            .onChange(of: medicine.instructions) { _, _ in invalidate() }
            .onChange(of: medicine.startDate) { _, _ in invalidate() }
    }
    private func invalidate() { medicine.confirmed = false; medicine.reminderEnabled = false; medicine.reminderThrough = nil }
}

struct HealthScanner: UIViewControllerRepresentable {
    var completion: (Result<[Data], Error>) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController(); controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) { }
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: HealthScanner
        init(_ parent: HealthScanner) { self.parent = parent }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let data = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).jpegData(compressionQuality: 0.92) }
            parent.completion(.success(data))
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.dismiss() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.completion(.failure(error)) }
    }
}
