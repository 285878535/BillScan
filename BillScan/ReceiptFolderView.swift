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
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("票夹")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                        Spacer()
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
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: AppTheme.spacingLG) {
                                ForEach(Array(groupedReceipts.keys.sorted()), id: \.self) { category in
                                    VStack(alignment: .leading, spacing: 12) {
                                        SectionHeader(title: category, actionTitle: "\(groupedReceipts[category]?.count ?? 0)张")
                                        
                                        VStack(spacing: 12) {
                                            ForEach(groupedReceipts[category] ?? []) { receipt in
                                                ReceiptRowCard(receipt: receipt)
                                                    .onTapGesture {
                                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                        startOpeningAnimation(for: receipt)
                                                    }
                                                    .contextMenu {
                                                        Button(role: .destructive) {
                                                            deleteReceipt(receipt)
                                                        } label: {
                                                            Label("删除", systemImage: "trash")
                                                        }
                                                    }
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                }
                            }
                            .padding(.bottom, 32)
                        }
                    }
                }

                // ── 悬浮按钮
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
            .sheet(item: $selectedReceipt) { receipt in
                ReceiptDetailView(receipt: receipt)
            }
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
        
        // 1. 准备：显示信封和遮罩
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showOpenAnimation = true
            showEnvelope = true
            envelopeOffset = CGSize(width: 0, height: 100) // 从下方升起
            billInEnvelope = true // 初始在信封里
            animationOffset = CGSize(width: 0, height: 40) // 在信封中心
            animationScale = 0.5
            animationOpacity = 0
        }
        
        // 2. 升起并显示票据微缩图
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                envelopeOffset = .zero
                animationOpacity = 1.0
            }
            
            // 3. 打开信封
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    envelopeIsOpen = true
                }
                
                // 4. 票据钻出并放大
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    billInEnvelope = false // 切换到上层
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        animationOffset = CGSize(width: 0, height: -150)
                        animationScale = 1.1
                    }
                    
                    // 5. 最终呈现详情页
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        selectedReceipt = receipt

                        // 6. 清理动画状态
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showOpenAnimation = false
                            showEnvelope = false
                            envelopeIsOpen = false
                            billInEnvelope = false
                            openingImage = nil
                            animationOffset = .zero
                            animationScale = 1.0
                        }
                    }
                }
            }
        }
    }

    private func deleteReceipt(_ receipt: Receipt) {
        withAnimation {
            modelContext.delete(receipt)
            try? modelContext.save()
        }
    }

    private func insertMockDataIfNeeded() {
        // 初始化默认分类
        if userCategories.isEmpty {
            let defaults = ["医疗", "购物", "餐饮"]
            for name in defaults {
                modelContext.insert(Category(name: name))
            }
        }
        
        guard receipts.isEmpty else { return }
        
        // 创建一个带有颜色块的占位图数据，避免白屏
        let placeholderData = UIImage(systemName: "doc.text.fill")?
            .withTintColor(.systemOrange)
            .jpegData(compressionQuality: 0.1) ?? Data()

        let mockReceipts = [
            Receipt(type: .medical, patientName: "王小明", amount: nil, date: Date(), merchantName: "第一人民医院", category: "医疗", extractedText: "急性上呼吸道感染\n白细胞：11.2\n报告日期：2026-04-29", additionalFields: [:], imageData: placeholderData),
            Receipt(type: .food, amount: 65.0, date: Date().addingTimeInterval(-172800), merchantName: "星巴克", category: "餐饮", extractedText: "拿铁：32\n三明治：33", additionalFields: [:], imageData: placeholderData),
            Receipt(type: .shopping, amount: 299.0, date: Date().addingTimeInterval(-259200), merchantName: "优衣库", category: "购物", extractedText: "外套：299", additionalFields: [:], imageData: placeholderData)
        ]
        
        for r in mockReceipts {
            modelContext.insert(r)
        }
        try? modelContext.save()
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
            .frame(width: 80, height: 80)
            .cornerRadius(12)
            .clipped()
            
            VStack(alignment: .leading, spacing: 4) {
                Text(receipt.type.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text(receipt.merchantName ?? "未知商家")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(1)
                
                HStack {
                    Text(receipt.date.formatted(date: .abbreviated, time: .omitted))
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
    @Environment(\.dismiss) private var dismiss
    @State private var uiImage: UIImage?
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showFullScreen = false

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
                                Button { dismiss() } label: {
                                    Image(systemName: "chevron.left")
                                        .foregroundColor(.white)
                                        .font(.system(size: 16, weight: .semibold))
                                        .frame(width: 36, height: 36)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                }
                                Spacer()
                                Button { exportAsImage() } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .foregroundColor(.white)
                                        .font(.system(size: 16, weight: .semibold))
                                        .frame(width: 36, height: 36)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 52)
                            Spacer()
                        }
                    }
                    
                    // ── 信息卡片
                    VStack(spacing: 20) {
                        // 分类标签 + 类型 + 金额
                        VStack(spacing: 10) {
                            Text(receipt.category)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(AppTheme.brandPrimary)
                                .cornerRadius(6)

                            Text(receipt.type.rawValue)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary)

                            if let amount = receipt.amount {
                                Text("¥\(String(format: "%.2f", amount))")
                                    .font(.system(size: 32, weight: .heavy))
                                    .foregroundColor(AppTheme.brandPrimary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        
                        // 日期
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(AppTheme.textDisabled)
                                .font(.system(size: 14))
                            Text(receipt.date.formatted(date: .long, time: .omitted))
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(AppTheme.bgSecondary)
                        .cornerRadius(12)
                        
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

    private func exportAsImage() {
        guard let image = uiImage else { return }
        shareItems = [image]
        showShareSheet = true
    }
}

struct FullScreenImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var rotation: Double = 0
    @State private var offset: CGSize = .zero
    
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
                                scale = value
                            }
                            .onEnded { _ in
                                withAnimation {
                                    if scale < 1.0 { scale = 1.0 }
                                }
                            }
                    )
                
                Spacer()
                
                Text("双指缩放查看细节")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.bottom, 30)
            }
        }
    }
}
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
