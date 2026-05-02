import SwiftUI
import UIKit
import SwiftData
import Vision
import VisionKit
import CoreImage

struct CaptureReceiptView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingImagePicker = false
    @State private var showDocumentScanner = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .camera
    @State private var showCaptureOptionMenu = false
    @State private var capturedImage: UIImage?
    @State private var extractedText = ""
    @State private var receiptType: ReceiptType = .other
    @State private var formFields: [String: String] = [:]
    @State private var isRecognizing = false
    @State private var showSaveAnimation = false
    @State private var showEnvelope = false
    @State private var envelopeIsOpen = false
    @State private var billInEnvelope = false
    @State private var animationOffset: CGSize = .zero
    @State private var animationScale: CGFloat = 1.0
    @State private var animationOpacity = 1.0
    @State private var envelopeOffset: CGSize = .zero
    @State private var showSuccessToast = false
    @State private var shouldAutoCropSelectedPhoto = false
    @Query(sort: \Category.createdAt) private var categories: [Category]
    @Binding var showTabBar: Bool
    
    var isPushed: Bool = false

    init(showTabBar: Binding<Bool>, initialImage: UIImage? = nil, isPushed: Bool = false) {
        self._showTabBar = showTabBar
        self._capturedImage = State(initialValue: initialImage)
        self.isPushed = isPushed
    }

    var body: some View {
        if isPushed {
            mainContent
                .navigationBarBackButtonHidden(true)
        } else {
            NavigationStack {
                mainContent
            }
        }
    }

    private var mainContent: some View {
        ZStack {
            AppTheme.bgSecondary.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: AppTheme.spacingLG) {
                    // 拍照区域
                    if let image = capturedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                            .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 6)
                    } else {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showCaptureOptionMenu = true
                        }) {
                            VStack(spacing: AppTheme.spacingMD) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 56, weight: .light))
                                    .foregroundColor(AppTheme.brandPrimary)
                                
                                VStack(spacing: 4) {
                                    Text("拍摄票据")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(AppTheme.textPrimary)
                                    Text("支持检验单、发票、小票等")
                                        .font(.system(size: 15))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                            }
                            .frame(height: 280)
                            .frame(maxWidth: .infinity)
                            .modernCardStyle()
                        }
                    }

                    if capturedImage != nil {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showCaptureOptionMenu = true
                        }) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("重新拍摄/选择")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.brandPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(AppTheme.brandPrimary.opacity(0.1))
                            .cornerRadius(AppTheme.radiusFull)
                        }
                    }

                    // 识别结果区域
                    if isRecognizing {
                        VStack(spacing: AppTheme.spacingMD) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("智能识别中...")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .modernCardStyle()
                    } else if capturedImage != nil {
                        VStack(alignment: .leading, spacing: AppTheme.spacingLG) {
                            // ── AI 状态指示灯
                            HStack {
                                Circle()
                                    .fill(ModelManager.shared.parsingModeIsAI ? Color.green : Color.gray.opacity(0.3))
                                    .frame(width: 8, height: 8)
                                
                                Text(ModelManager.shared.parsingModeLabel)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(ModelManager.shared.parsingModeIsAI ? .green : AppTheme.textSecondary)
                                
                                Spacer()
                                
                                if ModelManager.shared.parsingModeIsAI {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.purple)
                                        .font(.system(size: 12))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(ModelManager.shared.parsingModeIsAI ? Color.green.opacity(0.05) : Color.gray.opacity(0.05))
                            .cornerRadius(8)

                            SectionHeader(title: formFields.isEmpty ? "手动录入" : "智能提取结果")

                            VStack(spacing: 16) {
                                FieldRow(label: "票据类型", text: Binding(
                                    get: { receiptType.rawValue },
                                    set: { receiptType = ReceiptType(rawValue: $0) ?? .other }
                                ))

                                ForEach(displayFieldKeys, id: \.self) { key in
                                    FieldRow(label: key, text: Binding(
                                        get: { formFields[key] ?? "" },
                                        set: { formFields[key] = $0 }
                                    ), keyboardType: keyboardType(for: key))
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("分类")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(AppTheme.textSecondary)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(categories) { cat in
                                                Button(action: {
                                                    formFields["分类"] = cat.name
                                                }) {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: cat.iconName)
                                                            .font(.system(size: 12))
                                                        Text(cat.name)
                                                            .font(.system(size: 13))
                                                    }
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                                    .background(formFields["分类"] == cat.name ? AppTheme.brandPrimary : AppTheme.bgSecondary)
                                                    .foregroundColor(formFields["分类"] == cat.name ? .white : AppTheme.textPrimary)
                                                    .cornerRadius(8)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            if !extractedText.isEmpty {
                                DisclosureGroup {
                                    Text(extractedText)
                                        .font(.system(size: 12))
                                        .foregroundColor(AppTheme.textSecondary)
                                        .lineSpacing(4)
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(AppTheme.bgSecondary)
                                        .cornerRadius(AppTheme.radiusSm)
                                } label: {
                                    Text("查看 OCR 原文")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(AppTheme.brandPrimary)
                                }
                            }

                            PrimaryButton(title: "收藏到票夹") {
                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                saveReceipt()
                            }
                            .padding(.top, 8)
                        }
                        .padding(AppTheme.spacingLG)
                        .modernCardStyle()
                    }
                }
                .frame(width: UIScreen.main.bounds.width - 32)
                .padding(.vertical, AppTheme.spacingMD)
            }
        }
        .navigationTitle(isPushed ? "识别票据" : "扫描")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isPushed {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .foregroundColor(AppTheme.textPrimary)
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingImagePicker) {
            ImagePicker(image: $capturedImage, sourceType: imagePickerSourceType)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showDocumentScanner) {
            DocumentScannerView { images in
                capturedImage = DocumentScanComposer.compose(images: images)
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("选择图片来源", isPresented: $showCaptureOptionMenu, titleVisibility: .visible) {
            if VNDocumentCameraViewController.isSupported {
                Button("扫描文稿") {
                    showDocumentScanner = true
                }
            }
            Button("拍照") {
                shouldAutoCropSelectedPhoto = false
                imagePickerSourceType = .camera
                isShowingImagePicker = true
            }
            Button("从相册选择") {
                shouldAutoCropSelectedPhoto = true
                imagePickerSourceType = .photoLibrary
                isShowingImagePicker = true
            }
            Button("取消", role: .cancel) {}
        }
        .onChange(of: capturedImage) { _, newImage in
            guard let image = newImage else { return }
            if shouldAutoCropSelectedPhoto {
                shouldAutoCropSelectedPhoto = false
                DocumentImageProcessor.autoCropIfNeeded(image: image) { processedImage in
                    capturedImage = processedImage
                }
                return
            }
            recognizeImage(image: image)
        }
        .overlay(
            ZStack {
                if showSaveAnimation, let image = capturedImage {
                    ZStack {
                        if showEnvelope {
                            EnvelopeView(isOpen: envelopeIsOpen)
                                .offset(envelopeOffset)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                        }
                        
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(showEnvelope ? 0.3 : 0))
                    .ignoresSafeArea()
                }
            }
            .zIndex(100)
        )
        .overlay(
            VStack {
                if showSuccessToast {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                        Text("已存入票夹")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppTheme.brandPrimary)
                    .cornerRadius(AppTheme.radiusFull)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 20)
                }
                Spacer()
            }
            .padding(.top, 40) // 确保在刘海屏下方
            .zIndex(110)
        )
        .onAppear {
            if !isPushed {
                showTabBar = true
            }
            if let image = capturedImage, formFields.isEmpty {
                recognizeImage(image: image)
            }
        }
    }

    private func recognizeImage(image: UIImage) {
        isRecognizing = true
        formFields.removeAll()
        extractedText = ""

        OCRManager.shared.recognizeText(from: image) { text, type, fields in
            isRecognizing = false
            extractedText = text
            receiptType = type
            formFields = fields
        }
    }

    private func saveReceipt() {
        guard let image = capturedImage,
              let imageData = image.jpegData(compressionQuality: 0.8) else {
            return
        }

        let amount = Double(firstValue(for: ["总金额", "金额", "实付金额", "合计", "费用"]) ?? "")
        let category = formFields["分类"] ?? receiptType.rawValue
        let patientName = firstValue(for: ["病人姓名", "姓名", "客户姓名", "乘客姓名"])
        let merchantName = firstValue(for: ["商家名称", "医疗机构", "医院名称", "机构名称", "门店名称", "商户名称"])

        let receipt = Receipt(
            type: receiptType,
            patientName: patientName,
            amount: amount,
            merchantName: merchantName,
            category: category,
            extractedText: extractedText,
            additionalFields: formFields,
            imageData: imageData
        )

        modelContext.insert(receipt)
        try? modelContext.save()

        // ── 丝滑的信封收纳动画序列 ──
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showSaveAnimation = true
            showEnvelope = true
            animationOffset = CGSize(width: 0, height: -100)
            animationScale = 1.0
            animationOpacity = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                envelopeIsOpen = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.6)) {
                    animationOffset = CGSize(width: 0, height: 20)
                    animationScale = 0.5
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    billInEnvelope = true
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        envelopeIsOpen = false
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            envelopeOffset = CGSize(width: 300, height: -800)
                            animationOpacity = 0
                            showSuccessToast = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            withAnimation {
                                showSuccessToast = false
                            }
                            
                            if isPushed {
                                dismiss()
                            } else {
                                capturedImage = nil
                                formFields.removeAll()
                                extractedText = ""
                            }
                            
                            showSaveAnimation = false
                            showEnvelope = false
                            billInEnvelope = false
                            envelopeOffset = .zero
                        }
                    }
                }
            }
        }
    }

    private var displayFieldKeys: [String] {
        let hiddenKeys = Set(["分类", "AI结构化文本", "AI解析状态", "模型版本", "解析模式", "明细信息", "项目数", "检验项目详情"])
        let medicalOnlyKeys = Set(["病人姓名", "姓名", "性别", "年龄", "门诊号", "条码号", "科室", "临床诊断", "送检医生", "采集者"])
        let preferredOrder = [
            "票据类型",
            "商家名称", "医疗机构", "医院", "商家", "门店名称", "商户名称",
            "总金额", "金额", "实付金额", "合计", "费用",
            "病人姓名", "姓名", "客户姓名", "乘客姓名",
            "性别", "年龄", "门诊号", "条码号",
            "时间", "日期", "开票时间",
            "单号", "票号", "订单号",
            "地址", "电话"
        ]
        let availableKeys = formFields.keys.filter {
            !hiddenKeys.contains($0) && (receiptType == .medical || !medicalOnlyKeys.contains($0))
        }
        let orderedPreferredKeys = preferredOrder.filter { availableKeys.contains($0) }
        let remainingKeys = availableKeys.filter { !orderedPreferredKeys.contains($0) }.sorted()
        return orderedPreferredKeys + remainingKeys
    }

    private func firstValue(for keys: [String]) -> String? {
        for key in keys {
            if let value = formFields[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func keyboardType(for key: String) -> UIKeyboardType {
        if key.contains("金额") || key.contains("价格") || key.contains("费用") || key.contains("合计") {
            return .decimalPad
        }
        if key.contains("电话") || key.contains("手机号") {
            return .phonePad
        }
        if key.contains("日期") || key.contains("时间") {
            return .numbersAndPunctuation
        }
        return .default
    }
}

enum DocumentImageProcessor {
    private static let ciContext = CIContext()

    static func autoCropIfNeeded(image: UIImage, completion: @escaping (UIImage) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let processed = autoCropIfNeeded(image: image)
            DispatchQueue.main.async {
                completion(processed)
            }
        }
    }

    static func autoCropIfNeeded(image: UIImage) -> UIImage {
        let normalizedImage = normalized(image: image)
        guard let cgImage = normalizedImage.cgImage else {
            return image
        }

        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumConfidence = 0.7
        request.minimumSize = 0.2
        request.minimumAspectRatio = 0.3
        request.quadratureTolerance = 20

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else {
                return normalizedImage
            }
            return perspectiveCorrectedImage(from: normalizedImage, rectangle: observation) ?? normalizedImage
        } catch {
            return normalizedImage
        }
    }

    private static func normalized(image: UIImage) -> UIImage {
        if image.imageOrientation == .up {
            return image
        }

        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func perspectiveCorrectedImage(from image: UIImage, rectangle: VNRectangleObservation) -> UIImage? {
        guard let inputCIImage = CIImage(image: image) else {
            return nil
        }

        let extent = inputCIImage.extent
        let topLeft = CGPoint(x: rectangle.topLeft.x * extent.width, y: rectangle.topLeft.y * extent.height)
        let topRight = CGPoint(x: rectangle.topRight.x * extent.width, y: rectangle.topRight.y * extent.height)
        let bottomLeft = CGPoint(x: rectangle.bottomLeft.x * extent.width, y: rectangle.bottomLeft.y * extent.height)
        let bottomRight = CGPoint(x: rectangle.bottomRight.x * extent.width, y: rectangle.bottomRight.y * extent.height)

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            return nil
        }

        filter.setValue(inputCIImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")

        guard let outputImage = filter.outputImage,
              let correctedCGImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }

        return UIImage(cgImage: correctedCGImage)
    }
}

// 图片选择器封装
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let sourceType: UIImagePickerController.SourceType
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let originalImage = info[.originalImage] as? UIImage {
                parent.image = originalImage
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct DocumentScannerView: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let parent: DocumentScannerView

        init(_ parent: DocumentScannerView) {
            self.parent = parent
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            print("文稿扫描失败: \(error)")
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onScan(images)
            parent.dismiss()
        }
    }
}

enum DocumentScanComposer {
    static func compose(images: [UIImage]) -> UIImage? {
        guard !images.isEmpty else { return nil }
        if images.count == 1 {
            return images[0]
        }

        let targetWidth = images.map(\.size.width).max() ?? 0
        let totalHeight = images.reduce(CGFloat.zero) { partial, image in
            let scale = targetWidth / max(image.size.width, 1)
            return partial + image.size.height * scale
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetWidth, height: totalHeight))
        return renderer.image { _ in
            var yOffset: CGFloat = 0
            for image in images {
                let scale = targetWidth / max(image.size.width, 1)
                let drawHeight = image.size.height * scale
                image.draw(in: CGRect(x: 0, y: yOffset, width: targetWidth, height: drawHeight))
                yOffset += drawHeight
            }
        }
    }
}

struct FieldRow: View {
    let label: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
            
            TextField(label, text: $text)
                .font(.system(size: 16))
                .keyboardType(keyboardType)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppTheme.bgSecondary)
                .cornerRadius(10)
                .autocorrectionDisabled()
        }
    }
}
