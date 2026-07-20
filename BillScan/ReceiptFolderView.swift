import SwiftUI
import SwiftData
import UIKit
import VisionKit

struct ReceiptFolderView: View {
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    @Query(sort: \Category.createdAt) private var userCategories: [Category]
    @State private var selectedReceipt: Receipt?
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @Binding var showTabBar: Bool

    // 批量选择/删除
    @State private var isSelecting = false
    @State private var selectedIDs = Set<UUID>()
    @State private var showBatchDeleteConfirm = false
    @State private var pendingDeleteReceipt: Receipt?

    // 扫描相关状态
    @State private var showScanningOptions = false
    @State private var showImagePicker = false
    @State private var showDocumentScanner = false
    @State private var pickerSourceType: UIImagePickerController.SourceType = .camera
    @State private var selectedImage: UIImage?
    @State private var shouldAutoCropSelectedPhoto = false
    @State private var navigateToCapture = false

    // 悬浮按钮位置
    @State private var fabPosition: CGPoint = CGPoint(x: UIScreen.main.bounds.width - 50, y: UIScreen.main.bounds.height - 180)
    @GestureState private var dragOffset: CGSize = .zero

    // ── 详情打开动画相关状态 ──
    @State private var showOpenAnimation = false
    @State private var showEnvelope = false
    @State private var envelopeIsOpen = false
    @State private var billInEnvelope = false
    @State private var animationOffset: CGSize = .zero
    @State private var animationScale: CGFloat = 1.0
    @State private var animationOpacity: Double = 0
    @State private var envelopeOffset: CGSize = .zero
    @State private var openingImage: UIImage? = nil

    @Environment(\.modelContext) private var modelContext

    // 所有分类 (包含图标)
    private var allCategoryItems: [CategoryItem] {
        if userCategories.isEmpty {
            return [
                CategoryItem(name: "医疗", iconName: "medical.thermometer"),
                CategoryItem(name: "购物", iconName: "cart"),
                CategoryItem(name: "餐饮", iconName: "fork.knife")
            ]
        }
        return userCategories.map { CategoryItem(name: $0.name, iconName: $0.iconName) }
    }

    // 按分类和搜索分组票据
    private var groupedReceipts: [String: [Receipt]] {
        let filtered = receipts.filter { receipt in
            let matchesCategory = selectedCategory == nil || receipt.category == selectedCategory
            let matchesSearch = searchText.isEmpty ||
                               receipt.type.rawValue.contains(searchText) ||
                               receipt.displayTitle.contains(searchText) ||
                               (receipt.merchantName?.contains(searchText) ?? false)
            return matchesCategory && matchesSearch
        }
        return Dictionary(grouping: filtered) { $0.category }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                AppTheme.bgSecondary.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // ── 顶部标题
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("票夹")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary)

                            if !receipts.isEmpty {
                                Text(overallSummary)
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        }
                        Spacer()

                        if !receipts.isEmpty {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isSelecting.toggle()
                                    selectedIDs.removeAll()
                                }
                            } label: {
                                Text(isSelecting ? "完成" : "选择")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppTheme.brandPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(AppTheme.brandPrimary.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 16)

                    // ── 搜索栏
                    SearchBar(text: $searchText, placeholder: "搜索票据类型或商家...")
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)

                    // ── 分类选择器
                    CategoryPicker(categories: allCategoryItems, selected: $selectedCategory)
                        .padding(.bottom, 20)

                    if receipts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "folder")
                                .font(.system(size: 60, weight: .light))
                                .foregroundColor(AppTheme.textDisabled)
                            Text("暂无票据")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("点击右下角 + 扫描第一张票据")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .frame(maxHeight: .infinity)
                    } else if groupedReceipts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(AppTheme.textDisabled)
                            Text("没有找到匹配的票据")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("换个关键词，或清除分类筛选试试")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: AppTheme.spacingLG) {
                                ForEach(Array(groupedReceipts.keys.sorted()), id: \.self) { category in
                                    VStack(alignment: .leading, spacing: 12) {
                                        SectionHeader(title: category, actionTitle: groupSummary(groupedReceipts[category] ?? []))

                                        VStack(spacing: 12) {
                                            ForEach(groupedReceipts[category] ?? []) { receipt in
                                                ReceiptRowCard(receipt: receipt)
                                                    .overlay(alignment: .topTrailing) {
                                                        if isSelecting {
                                                            Image(systemName: selectedIDs.contains(receipt.id) ? "checkmark.circle.fill" : "circle")
                                                                .font(.system(size: 22))
                                                                .foregroundColor(selectedIDs.contains(receipt.id) ? AppTheme.brandPrimary : AppTheme.textDisabled)
                                                                .padding(10)
                                                                .transition(.scale.combined(with: .opacity))
                                                        }
                                                    }
                                                    .onTapGesture {
                                                        if isSelecting {
                                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                            if selectedIDs.contains(receipt.id) {
                                                                selectedIDs.remove(receipt.id)
                                                            } else {
                                                                selectedIDs.insert(receipt.id)
                                                            }
                                                        } else {
                                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                            startOpeningAnimation(for: receipt)
                                                        }
                                                    }
                                                    .contextMenu {
                                                        if !isSelecting {
                                                            Button(role: .destructive) {
                                                                pendingDeleteReceipt = receipt
                                                            } label: {
                                                                Label("删除", systemImage: "trash")
                                                            }
                                                        }
                                                    }
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                }
                            }
                            .padding(.bottom, isSelecting ? 110 : 32)
                        }
                    }
                }

                // ── 悬浮按钮
                if !isSelecting {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showScanningOptions = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 54, height: 54)
                        .background(
                            Circle()
                                .fill(AppTheme.brandPrimary)
                                .shadow(color: AppTheme.brandPrimary.opacity(0.4), radius: 12, x: 0, y: 6)
                        )
                }
                .position(x: fabPosition.x + dragOffset.width, y: fabPosition.y + dragOffset.height)
                .gesture(
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            let screen = UIScreen.main.bounds
                            let padding: CGFloat = 30
                            var newX = fabPosition.x + value.translation.width
                            var newY = fabPosition.y + value.translation.height
                            newX = min(max(newX, padding), screen.width - padding)
                            newY = min(max(newY, padding), screen.height - padding - 80)
                            fabPosition = CGPoint(x: newX, y: newY)
                        }
                )
                .confirmationDialog("选择图片来源", isPresented: $showScanningOptions, titleVisibility: .visible) {
                    if VNDocumentCameraViewController.isSupported {
                        Button("扫描文稿") { showDocumentScanner = true }
                    }
                    Button("拍照") {
                        shouldAutoCropSelectedPhoto = false
                        pickerSourceType = .camera
                        showImagePicker = true
                    }
                    Button("从相册选择") {
                        shouldAutoCropSelectedPhoto = true
                        pickerSourceType = .photoLibrary
                        showImagePicker = true
                    }
                    Button("取消", role: .cancel) {}
                }
                }
            }
            .overlay(alignment: .bottom) {
                // ── 批量删除操作栏
                if isSelecting {
                    HStack(spacing: 12) {
                        Button {
                            if selectedIDs.count == receipts.count {
                                selectedIDs.removeAll()
                            } else {
                                selectedIDs = Set(receipts.map(\.id))
                            }
                        } label: {
                            Text(selectedIDs.count == receipts.count ? "取消全选" : "全选")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary)
                        }

                        Spacer()

                        Text("已选 \(selectedIDs.count) 张")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)

                        Button {
                            showBatchDeleteConfirm = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("删除")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(selectedIDs.isEmpty ? AppTheme.textDisabled : .white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(selectedIDs.isEmpty ? AppTheme.bgSecondary : Color.red)
                            .clipShape(Capsule())
                        }
                        .disabled(selectedIDs.isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .confirmationDialog(
                "将删除 \(selectedIDs.count) 张票据，删除后不可恢复",
                isPresented: $showBatchDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("删除 \(selectedIDs.count) 张", role: .destructive) {
                    deleteSelectedReceipts()
                }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog(
                "删除这张票据？删除后不可恢复",
                isPresented: Binding(
                    get: { pendingDeleteReceipt != nil },
                    set: { if !$0 { pendingDeleteReceipt = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let receipt = pendingDeleteReceipt {
                        deleteReceipt(receipt)
                    }
                    pendingDeleteReceipt = nil
                }
                Button("取消", role: .cancel) { pendingDeleteReceipt = nil }
            }
            .overlay {
                // 详情页覆盖层：与信封动画同层级，保证过渡连贯
                if let receipt = selectedReceipt {
                    ReceiptDetailView(receipt: receipt, onClose: closeDetail)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                        .zIndex(150)
                }
            }
            .overlay(
                ZStack {
                    if showOpenAnimation {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .onTapGesture {
                                // 防止误触关闭动画中的背景
                            }
                        
                        ZStack {
                            if showEnvelope {
                                EnvelopeView(isOpen: envelopeIsOpen)
                                    .offset(envelopeOffset)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }
                            
                            if let image = openingImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
                                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                                    .offset(animationOffset)
                                    .scaleEffect(animationScale)
                                    .opacity(animationOpacity)
                                    .zIndex(billInEnvelope ? -1 : 1)
                            }
                        }
                    }
                }
                .zIndex(200)
            )
            .toolbar(.hidden)
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $selectedImage, sourceType: pickerSourceType)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showDocumentScanner) {
                DocumentScannerView { images in
                    selectedImage = DocumentScanComposer.compose(images: images)
                }
                .ignoresSafeArea()
            }
            .navigationDestination(isPresented: $navigateToCapture) {
                CaptureReceiptView(showTabBar: $showTabBar, initialImage: selectedImage, isPushed: true)
            }
            .onChange(of: selectedImage) { _, newValue in
                guard let image = newValue else { return }
                if shouldAutoCropSelectedPhoto {
                    shouldAutoCropSelectedPhoto = false
                    DocumentImageProcessor.autoCropIfNeeded(image: image) { processedImage in
                        selectedImage = processedImage
                    }
                    return
                }
                navigateToCapture = true
            }
            .onAppear {
                showTabBar = true
                insertMockDataIfNeeded()
            }
        }
    }

    private func startOpeningAnimation(for receipt: Receipt) {
        openingImage = UIImage(data: receipt.imageData)
        showTabBar = false

        // 1. 信封带着票据升起（初始状态先摆好，再触发过渡）
        envelopeOffset = .zero
        billInEnvelope = true
        animationOffset = CGSize(width: 0, height: 40)
        animationScale = 0.5
        animationOpacity = 0
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            showOpenAnimation = true
            showEnvelope = true
            animationOpacity = 1.0
        }

        // 2. 打开封盖
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                envelopeIsOpen = true
            }
        }

        // 3. 票据钻出
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            billInEnvelope = false
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                animationOffset = CGSize(width: 0, height: -140)
                animationScale = 1.05
            }
        }

        // 4. 票据继续放大“变成”详情页头图，详情页同步淡入、信封淡出——一段动画直达详情
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            let screen = UIScreen.main.bounds
            withAnimation(.easeInOut(duration: 0.35)) {
                selectedReceipt = receipt
                animationOffset = CGSize(width: 0, height: -(screen.height / 2 - 200))
                animationScale = screen.width / 180
                animationOpacity = 0
                showEnvelope = false
            }

            // 5. 清理动画状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showOpenAnimation = false
                envelopeIsOpen = false
                billInEnvelope = false
                openingImage = nil
                animationOffset = .zero
                animationScale = 1.0
                envelopeOffset = .zero
            }
        }
    }

    private func closeDetail() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
            selectedReceipt = nil
        }
        showTabBar = true
    }

    private func deleteReceipt(_ receipt: Receipt) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation {
            modelContext.delete(receipt)
            try? modelContext.save()
        }
    }

    private func deleteSelectedReceipts() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation {
            for receipt in receipts where selectedIDs.contains(receipt.id) {
                modelContext.delete(receipt)
            }
            try? modelContext.save()
            selectedIDs.removeAll()
            isSelecting = false
        }
    }

    private func groupSummary(_ list: [Receipt]) -> String {
        let total = list.compactMap(\.amount).reduce(0, +)
        guard total > 0 else { return "\(list.count)张" }
        return "\(list.count)张 · ¥\(String(format: "%.2f", total))"
    }

    private var overallSummary: String {
        let total = receipts.compactMap(\.amount).reduce(0, +)
        guard total > 0 else { return "共 \(receipts.count) 张票据" }
        return "共 \(receipts.count) 张 · 合计 ¥\(String(format: "%.2f", total))"
    }

    private func insertMockDataIfNeeded() {
        // 初始化默认分类
        if userCategories.isEmpty {
            let defaults = ["医疗", "购物", "餐饮"]
            for name in defaults {
                modelContext.insert(Category(name: name))
            }
            try? modelContext.save()
        }
    }
}

// ── 横向列表卡片
struct ReceiptRowCard: View {
    let receipt: Receipt
    @State private var uiImage: UIImage?
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let image = uiImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(AppTheme.bgSecondary)
                        .overlay(Image(systemName: "doc.text").foregroundColor(AppTheme.textDisabled))
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.divider, lineWidth: 0.5)
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(receipt.displayTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)

                if !receipt.displaySubtitle.isEmpty {
                    Text(receipt.displaySubtitle)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                
                HStack {
                    Text(receipt.date.chineseDateString)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textDisabled)
                    Spacer()
                    if let amount = receipt.amount {
                        Text("¥\(String(format: "%.2f", amount))")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppTheme.brandPrimary)
                    }
                }
            }
            Spacer()
        }
        .padding(12)
        .modernCardStyle()
        .onAppear {
            uiImage = UIImage(data: receipt.imageData)
        }
    }
}

// 票据详情页
struct ReceiptDetailView: View {
    let receipt: Receipt
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.createdAt) private var categories: [Category]
    @State private var uiImage: UIImage?
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showFullScreen = false

    // ── 编辑状态 ──
    @State private var isEditing = false
    @State private var editKeys: [String] = []
    @State private var draftFields: [String: String] = [:]
    @State private var draftAmount = ""
    @State private var draftCategory = ""
    @State private var draftItems = ""
    @State private var customDrafts: [CustomFieldDraft] = []

    struct CustomFieldDraft: Identifiable {
        let id = UUID()
        var key = ""
        var value = ""
    }

    /// 同一信息的别名字段组：编辑其一，同步更新组内其他已存在的键
    private static let aliasGroups: [[String]] = [
        ["商家名称", "医疗机构", "医院", "门店名称", "商户名称"],
        ["病人姓名", "姓名"]
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.bgPrimary.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // ── Hero 图区域
                    ZStack(alignment: .bottomLeading) {
                        if let image = uiImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: UIScreen.main.bounds.width, height: 380)
                                .clipped()
                                .onTapGesture { showFullScreen = true }
                        } else {
                            ZStack {
                                Rectangle().fill(AppTheme.bgSecondary)
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 80))
                                    .foregroundColor(AppTheme.brandPrimary.opacity(0.15))
                            }
                            .frame(width: UIScreen.main.bounds.width, height: 380)
                        }

                        // 底部渐变遮罩
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.4)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .frame(height: 140)
                        .frame(maxWidth: .infinity, alignment: .bottom)

                        // 顶部按钮
                        VStack {
                            HStack {
                                Button {
                                    if let onClose {
                                        onClose()
                                    } else {
                                        dismiss()
                                    }
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .foregroundColor(.white)
                                        .font(.system(size: 16, weight: .semibold))
                                        .frame(width: 36, height: 36)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                }
                                Spacer()
                                if !isEditing {
                                    Button { beginEdit() } label: {
                                        Image(systemName: "pencil")
                                            .foregroundColor(.white)
                                            .font(.system(size: 16, weight: .semibold))
                                            .frame(width: 36, height: 36)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Circle())
                                    }
                                    Button { exportAsImage() } label: {
                                        Image(systemName: "square.and.arrow.up")
                                            .foregroundColor(.white)
                                            .font(.system(size: 16, weight: .semibold))
                                            .frame(width: 36, height: 36)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Circle())
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 52)
                            Spacer()
                        }
                    }
                    
                    // ── 信息卡片
                    VStack(spacing: 20) {
                        // 分类 + 类型 + 日期 + 金额（紧凑单行）
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(isEditing ? draftCategory : receipt.category)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(AppTheme.brandPrimary)
                                        .cornerRadius(6)

                                    Text(receipt.date.chineseDateString)
                                        .font(.system(size: 13))
                                        .foregroundColor(AppTheme.textDisabled)
                                }

                                Text(receipt.displayTitle)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(AppTheme.textPrimary)
                                    .lineLimit(2)

                                if !receipt.displaySubtitle.isEmpty {
                                    Text(receipt.displaySubtitle)
                                        .font(.system(size: 13))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                            }

                            Spacer()

                            if isEditing {
                                TextField("金额", text: $draftAmount)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 18, weight: .bold))
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 110)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(AppTheme.bgSecondary)
                                    .cornerRadius(10)
                            } else if let amount = receipt.amount {
                                Text("¥\(String(format: "%.2f", amount))")
                                    .font(.system(size: 26, weight: .heavy))
                                    .foregroundColor(AppTheme.brandPrimary)
                            }
                        }
                        .padding(.top, 4)

                        // 编辑模式下的分类选择
                        if isEditing {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(categories) { cat in
                                        Button {
                                            draftCategory = cat.name
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: cat.iconName)
                                                    .font(.system(size: 12))
                                                Text(cat.name)
                                                    .font(.system(size: 13))
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(draftCategory == cat.name ? AppTheme.brandPrimary : AppTheme.bgSecondary)
                                            .foregroundColor(draftCategory == cat.name ? .white : AppTheme.textPrimary)
                                            .cornerRadius(8)
                                        }
                                    }
                                }
                            }
                        }

                        // 识别字段
                        if isEditing {
                            VStack(spacing: 16) {
                                ForEach(editKeys, id: \.self) { key in
                                    FieldRow(label: key, text: Binding(
                                        get: { draftFields[key] ?? "" },
                                        set: { draftFields[key] = $0 }
                                    ))
                                }

                                // 自定义字段
                                ForEach($customDrafts) { $field in
                                    HStack(spacing: 8) {
                                        TextField("字段名", text: $field.key)
                                            .font(.system(size: 15))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 12)
                                            .background(AppTheme.bgSecondary)
                                            .cornerRadius(10)
                                            .frame(width: 110)

                                        TextField("内容", text: $field.value)
                                            .font(.system(size: 15))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 12)
                                            .background(AppTheme.bgSecondary)
                                            .cornerRadius(10)

                                        Button {
                                            customDrafts.removeAll { $0.id == field.id }
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(.red.opacity(0.7))
                                        }
                                    }
                                }

                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation { customDrafts.append(CustomFieldDraft()) }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus.circle")
                                        Text("添加字段")
                                    }
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AppTheme.brandPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(AppTheme.brandPrimary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5]))
                                    )
                                }
                            }
                        } else if !detailFields.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(Array(detailFields.enumerated()), id: \.offset) { index, item in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(item.0)
                                            .font(.system(size: 14))
                                            .foregroundColor(AppTheme.textSecondary)
                                        Spacer()
                                        Text(item.1)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(AppTheme.textPrimary)
                                            .multilineTextAlignment(.trailing)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)

                                    if index < detailFields.count - 1 {
                                        Divider().padding(.leading, 16)
                                    }
                                }
                            }
                            .background(AppTheme.bgSecondary)
                            .cornerRadius(12)
                        }

                        // 检验项目
                        if isEditing {
                            if !draftItems.isEmpty || receipt.additionalFields?["检验项目详情"] != nil {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("检验项目（每行一条）")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(AppTheme.textSecondary)
                                    TextEditor(text: $draftItems)
                                        .font(.system(size: 13))
                                        .frame(minHeight: 120)
                                        .padding(8)
                                        .scrollContentBackground(.hidden)
                                        .background(AppTheme.bgSecondary)
                                        .cornerRadius(10)
                                }
                            }
                        } else if let items = receipt.additionalFields?["检验项目详情"], !items.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("检验项目")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.textSecondary)
                                Text(items)
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.textPrimary)
                                    .lineSpacing(6)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(AppTheme.bgSecondary)
                            .cornerRadius(12)
                        }

                        // 编辑操作按钮 / 识别原文
                        if isEditing {
                            VStack(spacing: 10) {
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    saveEdit()
                                } label: {
                                    Text("保存修改")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(AppTheme.brandPrimary)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }

                                Button {
                                    withAnimation { isEditing = false }
                                } label: {
                                    Text("取消")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(AppTheme.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                }
                            }
                        } else if !receipt.extractedText.isEmpty {
                            DisclosureGroup {
                                Text(receipt.extractedText)
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                    .lineSpacing(4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 8)
                            } label: {
                                Text("查看识别原文")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AppTheme.brandPrimary)
                            }
                            .padding(16)
                            .background(AppTheme.bgSecondary)
                            .cornerRadius(12)
                        }

                        Spacer().frame(height: 60)
                    }
                    .padding(24)
                    .background(AppTheme.bgPrimary)
                    .cornerRadius(24, corners: [.topLeft, .topRight])
                    .offset(y: -30)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            if let image = uiImage {
                FullScreenImageView(image: image)
            }
        }
        .onAppear {
            uiImage = UIImage(data: receipt.imageData)
        }
    }

    /// 展示保存下来的识别字段：按常用顺序排列，隐藏内部字段，去掉值重复的别名字段（如 医院/医疗机构/商家名称）。
    private var detailFields: [(String, String)] {
        var fields = receipt.additionalFields ?? [:]

        // 旧数据键名归一（仅影响显示）：非医疗票据把医疗叫法换成通用叫法
        if receipt.type != .medical {
            if let value = fields.removeValue(forKey: "病人姓名") {
                fields["姓名"] = fields["姓名"] ?? value
            }
            for key in ["医疗机构", "医院"] {
                if let value = fields.removeValue(forKey: key) {
                    fields["商家名称"] = fields["商家名称"] ?? value
                }
            }
        }
        let hiddenKeys = Set(["分类", "票据类型", "AI结构化文本", "AI解析状态", "模型版本", "解析模式", "明细信息", "项目数", "检验项目详情"])
        let preferredOrder = [
            "商家名称", "医疗机构", "医院", "门店名称", "商户名称",
            "总金额", "金额", "实付金额", "合计", "费用",
            "病人姓名", "姓名", "客户姓名", "乘客姓名",
            "性别", "年龄", "科室", "门诊号", "条码号",
            "时间", "日期", "开票时间",
            "临床诊断", "送检医生", "采集者",
            "单号", "票号", "订单号",
            "地址", "电话"
        ]
        let availableKeys = fields.keys.filter { !hiddenKeys.contains($0) }
        let orderedKeys = preferredOrder.filter { availableKeys.contains($0) }
            + availableKeys.filter { !preferredOrder.contains($0) }.sorted()

        var result: [(String, String)] = []
        var seenValues = Set<String>()
        for key in orderedKeys {
            guard let value = fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty, !seenValues.contains(value) else { continue }
            seenValues.insert(value)
            result.append((key, value))
        }
        return result
    }

    private func beginEdit() {
        editKeys = detailFields.map(\.0)
        draftFields = Dictionary(uniqueKeysWithValues: detailFields)
        draftAmount = receipt.amount.map { String(format: "%.2f", $0) } ?? ""
        draftCategory = receipt.category
        draftItems = receipt.additionalFields?["检验项目详情"] ?? ""
        customDrafts = []
        withAnimation { isEditing = true }
    }

    private func saveEdit() {
        var fields = receipt.additionalFields ?? [:]

        for key in editKeys {
            let value = (draftFields[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // 别名字段（如 医院/医疗机构/商家名称）同步更新，避免详情与列表显示不一致
            let group = Self.aliasGroups.first { $0.contains(key) } ?? [key]
            for aliasKey in group where fields[aliasKey] != nil || aliasKey == key {
                if value.isEmpty {
                    fields.removeValue(forKey: aliasKey)
                } else {
                    fields[aliasKey] = value
                }
            }
        }

        let amountText = draftAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        if let amount = Double(amountText) {
            receipt.amount = amount
            fields["总金额"] = amountText
        } else {
            receipt.amount = nil
            fields.removeValue(forKey: "总金额")
        }

        let items = draftItems.trimmingCharacters(in: .whitespacesAndNewlines)
        if items.isEmpty {
            fields.removeValue(forKey: "检验项目详情")
            fields.removeValue(forKey: "项目数")
        } else {
            let itemLines = items.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            fields["检验项目详情"] = itemLines.joined(separator: "\n")
            fields["项目数"] = "\(itemLines.count)"
        }

        // 用户自定义字段
        for custom in customDrafts {
            let key = custom.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = custom.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            fields[key] = value
        }

        receipt.category = draftCategory
        receipt.additionalFields = fields
        receipt.merchantName = Self.firstValue(in: fields, keys: ["商家名称", "医疗机构", "医院", "门店名称", "商户名称"])
        receipt.patientName = Self.firstValue(in: fields, keys: ["病人姓名", "姓名", "客户姓名", "乘客姓名"])
        try? modelContext.save()
        withAnimation { isEditing = false }
    }

    private static func firstValue(in fields: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func exportAsImage() {
        guard let image = uiImage else { return }
        shareItems = [image]
        showShareSheet = true
    }
}

// ── 中文日期格式化
extension Date {
    var chineseDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: self)
    }
}

struct FullScreenImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var rotation: Double = 0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 6.0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .font(.system(size: 20, weight: .bold))
                            .padding(12)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring()) {
                            rotation += 90
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "rotate.right.fill")
                            Text("旋转")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(20)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Spacer()
                
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .rotationEffect(.degrees(rotation))
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { _ in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    scale = min(max(scale, minScale), maxScale)
                                    if scale <= minScale {
                                        offset = .zero
                                        lastOffset = .zero
                                    } else {
                                        offset = clampedOffset(offset)
                                        lastOffset = offset
                                    }
                                }
                                lastScale = max(scale, minScale)
                            }
                            .simultaneously(with:
                                DragGesture()
                                    .onChanged { value in
                                        guard scale > minScale else { return }
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        guard scale > minScale else { return }
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            offset = clampedOffset(offset)
                                        }
                                        lastOffset = clampedOffset(offset)
                                    }
                            )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if scale > minScale {
                                scale = minScale
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.5
                            }
                            lastScale = scale
                        }
                    }

                Spacer()

                Text("双指缩放 · 双击放大 · 放大后可拖动")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.bottom, 30)
            }
        }
    }

    /// 限制拖动范围，避免图片被拖出屏幕太远回不来
    private func clampedOffset(_ offset: CGSize) -> CGSize {
        let screen = UIScreen.main.bounds
        let maxX = screen.width * (scale - 1) / 2 + 40
        let maxY = screen.height * (scale - 1) / 2 + 40
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }
}
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
