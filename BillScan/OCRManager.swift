import Foundation
import Vision
import UIKit

struct TextBlock {
    let text: String
    let box: CGRect
}

private struct OCRAttempt {
    let text: String
    let blocks: [TextBlock]
    let score: Int
}

class OCRManager: NSObject {
    static let shared = OCRManager()

    func recognizeText(from image: UIImage, completion: @escaping (String, ReceiptType, [String: String]) -> Void) {
        performOCRRecognition(image: image, completion: completion)
    }

    // 原有的OCR识别流程，提取为单独方法
    private func performOCRRecognition(image: UIImage, completion: @escaping (String, ReceiptType, [String: String]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion("无法处理图片", .other, [:])
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let baseOrientation = self.cgImageOrientation(image.imageOrientation)
            let orientations = self.ocrOrientations(startingFrom: baseOrientation)
            let bestAttempt = orientations.compactMap { orientation in
                self.performRecognition(cgImage: cgImage, orientation: orientation)
            }.max { $0.score < $1.score }

            guard let bestAttempt, !bestAttempt.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                DispatchQueue.main.async {
                    completion("", .other, [:])
                }
                return
            }

            // 📝 调试打印：OCR识别原始文本
            print("\n=====================================")
            print("🔍 OCR识别完成，原始文本：")
            print("-------------------------------------")
            print(bestAttempt.text)
            print("=====================================\n")

            DispatchQueue.main.async {
                self.enrichOCRResult(bestAttempt.text, blocks: bestAttempt.blocks, completion: completion)
            }
        }
    }

    private func reconstructLayout(from blocks: [TextBlock]) -> String {
        guard !blocks.isEmpty else { return "" }

        let isRotated = blocks.count > 5 && self.detectRotation(blocks)

        if isRotated {
            let sortedBlocks = blocks.sorted { $0.box.minX < $1.box.minX }
            var lines: [String] = []
            var currentLineBlocks: [TextBlock] = []

            for block in sortedBlocks {
                if let last = currentLineBlocks.last {
                    if abs(last.box.midX - block.box.midX) < 0.03 {
                        currentLineBlocks.append(block)
                    } else {
                        lines.append(processLine(currentLineBlocks, sortByY: true))
                        currentLineBlocks = [block]
                    }
                } else {
                    currentLineBlocks = [block]
                }
            }
            lines.append(processLine(currentLineBlocks, sortByY: true))
            return lines.joined(separator: "\n")
        } else {
            let sortedBlocks = blocks.sorted { $0.box.minY > $1.box.minY }
            var lines: [String] = []
            var currentLineBlocks: [TextBlock] = []

            for block in sortedBlocks {
                if let last = currentLineBlocks.last {
                    if abs(last.box.midY - block.box.midY) < 0.02 {
                        currentLineBlocks.append(block)
                    } else {
                        lines.append(processLine(currentLineBlocks, sortByY: false))
                        currentLineBlocks = [block]
                    }
                } else {
                    currentLineBlocks = [block]
                }
            }
            lines.append(processLine(currentLineBlocks, sortByY: false))
            return lines.joined(separator: "\n")
        }
    }

    private func performRecognition(cgImage: CGImage, orientation: CGImagePropertyOrientation) -> OCRAttempt? {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true

        do {
            try requestHandler.perform([request])
            guard let observations = request.results, !observations.isEmpty else {
                return nil
            }

            let blocks = observations.compactMap { observation -> TextBlock? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return TextBlock(text: candidate.string, box: observation.boundingBox)
            }

            let fullText = reconstructLayout(from: blocks)
            let score = scoreRecognizedText(fullText, blockCount: blocks.count)
            return OCRAttempt(text: fullText, blocks: blocks, score: score)
        } catch {
            return nil
        }
    }

    private func detectRotation(_ blocks: [TextBlock]) -> Bool {
        var rotatedVotes = 0
        for block in blocks.prefix(10) {
            if block.box.height > block.box.width * 1.5 { rotatedVotes += 1 }
        }
        return rotatedVotes > 5
    }

    private func processLine(_ blocks: [TextBlock], sortByY: Bool) -> String {
        if sortByY {
            return blocks.sorted { $0.box.minY > $1.box.minY }.map { $0.text }.joined(separator: " ")
        } else {
            return blocks.sorted { $0.box.minX < $1.box.minX }.map { $0.text }.joined(separator: " ")
        }
    }

    private func enrichOCRResult(_ text: String, blocks: [TextBlock], completion: @escaping (String, ReceiptType, [String: String]) -> Void) {
        self.parseText(text) { fullText, type, fields in
            var enhancedFields = fields
            let modelManager = ModelManager.shared
            enhancedFields["解析模式"] = modelManager.parsingModeIsAI ? "云模型解析" : "OCR原文"
            let lineHints = self.buildLineHints(from: blocks)

            // 📝 调试打印：解析模式
            print("\n=====================================")
            print("⚙️ 当前解析模式：\(modelManager.parsingModeLabel)")
            print("-------------------------------------")
            print("模型是否可用：\(modelManager.parsingModeIsAI)")
            print("当前使用模型：\(modelManager.currentModelName)")
            print("=====================================\n")

            guard modelManager.parsingModeIsAI else {
                // 📝 调试打印：OCR解析结果
                print("\n=====================================")
                print("📋 OCR解析完成，结果字段：")
                print("-------------------------------------")
                for (key, value) in enhancedFields {
                    print("\(key): \(value)")
                }
                print("=====================================\n")

                completion(fullText, type, enhancedFields)
                return
            }

            // 📝 调试打印：模型输入
            print("\n=====================================")
            print("🤖 调用云模型，输入文本：")
            print("-------------------------------------")
            print(text.prefix(500)) // 只打印前500字符，太长截断
            if text.count > 500 {
                print("...（共\(text.count)字符）")
            }
            print("=====================================\n")

            LocalLLMService.shared.summarizeOCRText(text, lineHints: lineHints) { [weak self] summary in
                guard let self else { return }
                var finalFields = enhancedFields
                finalFields["模型版本"] = modelManager.cloudModelID.isEmpty ? modelManager.currentModelName : modelManager.cloudModelID

                if let summary, !summary.isEmpty {
                    // 📝 调试打印：模型原始输出
                    print("\n=====================================")
                    print("📝 大模型返回原始结果：")
                    print("-------------------------------------")
                    print(summary)
                    print("=====================================\n")

                    // 过滤幻觉内容
                    let cleanedSummary = self.cleanupModelOutput(summary)
                    finalFields["AI结构化文本"] = cleanedSummary
                    finalFields["AI解析状态"] = "云模型文本解析（基于 OCR）"
                    let extractedFields = self.extractFields(fromStructuredText: cleanedSummary)
                    finalFields.merge(extractedFields) { current, new in
                        current.isEmpty ? new : current
                    }

                    // 📝 调试打印：模型解析结果
                    print("\n=====================================")
                    print("✅ 模型解析完成，最终字段：")
                    print("-------------------------------------")
                    for (key, value) in finalFields {
                        print("\(key): \(value)")
                    }
                    print("=====================================\n")
                } else {
                    finalFields["解析模式"] = "OCR原文"

                    // 📝 调试打印：模型调用失败，保留 OCR 原文
                    print("\n=====================================")
                    print("⚠️ 大模型调用失败，保留 OCR 原文")
                    print("-------------------------------------")
                    for (key, value) in finalFields {
                        print("\(key): \(value)")
                    }
                    print("=====================================\n")
                }
                completion(fullText, type, finalFields)
            }
        }
    }

    private func parseText(_ text: String, completion: @escaping (String, ReceiptType, [String: String]) -> Void) {
        var type: ReceiptType = .other
        var fields: [String: String] = [:]
        let normalizedText = text.replacingOccurrences(of: " ", with: "")
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // 判断票据类型
        if normalizedText.contains("医院") || normalizedText.contains("报告") || normalizedText.contains("检验") || normalizedText.contains("检查") {
            type = .medical
            fields["分类"] = "医疗"
            fields["票据类型"] = "医疗"
        } else if normalizedText.contains("餐饮") || normalizedText.contains("饭店") || normalizedText.contains("餐厅") || normalizedText.contains("小吃") || normalizedText.contains("外卖") {
            type = .food
            fields["分类"] = "餐饮"
            fields["票据类型"] = "餐饮"
        } else if normalizedText.contains("超市") || normalizedText.contains("购物") || normalizedText.contains("商品") || normalizedText.contains("合计") {
            type = .shopping
            fields["分类"] = "购物"
            fields["票据类型"] = "购物"
        } else if normalizedText.contains("机票") || normalizedText.contains("火车票") || normalizedText.contains("打车") || normalizedText.contains("地铁") || normalizedText.contains("交通") || normalizedText.contains("出行") {
            type = .transport
            fields["分类"] = "交通"
            fields["票据类型"] = "交通"
        }

        let isMedicalType = type == .medical

        // 提取通用字段
        if let hospital = extractHospital(from: text) {
            fields["医疗机构"] = hospital
            fields["商家名称"] = hospital
            fields["医院"] = hospital
        }
        if let amount = extractRegex(normalizedText, pattern: "(?:合计|总金额|金额|应收|实收)[^0-9]{0,6}([0-9]+(?:\\.[0-9]{1,2})?)") {
            fields["总金额"] = amount
        }

        if isMedicalType {
            if let patientName = extractNamedField(in: text, keys: ["姓名"]) {
                fields["病人姓名"] = patientName
                fields["姓名"] = patientName
            }
            if let gender = extractNamedField(in: text, keys: ["性别"]) {
                fields["性别"] = gender
            }
            if let age = extractNamedField(in: text, keys: ["年龄"]) {
                fields["年龄"] = age
            }
            if let outpatientID = extractNamedField(in: text, keys: ["门诊号", "门诊ID", "就诊号", "样本号"]) {
                fields["门诊号"] = outpatientID
            }
            if let barcode = extractNamedField(in: text, keys: ["条码", "条码号"]) {
                fields["条码号"] = barcode
            }
            if let department = extractNamedField(in: text, keys: ["科室"]) {
                fields["科室"] = department
            }
            if let diagnosis = extractNamedField(in: text, keys: ["临床诊断"]) {
                fields["临床诊断"] = diagnosis
            }
            if let doctor = extractNamedField(in: text, keys: ["送检医生"]) {
                fields["送检医生"] = doctor
            }
            if let collector = extractNamedField(in: text, keys: ["采集者"]) {
                fields["采集者"] = collector
            }
        }

        // 提取时间相关字段
        let datePattern = "\\d{4}-\\d{2}-\\d{2}"
        let timePattern = "\\d{2}:\\d{2}"
        let fullDateTimePattern = "\(datePattern)\\s*\(timePattern)"
        if let reportTime = extractRegex(text, pattern: "报告时间.*?(\(fullDateTimePattern))") {
            fields["报告时间"] = reportTime
        }
        if let collectTime = extractRegex(text, pattern: "采集时间.*?(\(fullDateTimePattern))") {
            fields["采集时间"] = collectTime
        }
        if let receiveTime = extractRegex(text, pattern: "接收时间.*?(\(fullDateTimePattern))") {
            fields["接收时间"] = receiveTime
        }
        if let anyTime = extractRegex(text, pattern: "(\(fullDateTimePattern))") {
            fields["时间"] = anyTime
        }

        // 仅医疗票据提取检验项目
        if isMedicalType {
            let medicalItems = extractMedicalItems(from: lines)
            if !medicalItems.isEmpty {
                fields["项目数"] = "\(medicalItems.count)"
                fields["检验项目详情"] = medicalItems.map {
                    "\($0.name): \($0.result)\($0.range.isEmpty ? "" : " (参考: \($0.range))")"
                }.joined(separator: "\n")
            }
        }

        completion(text, type, fields)
    }

    private func extractRegex(_ text: String, pattern: String) -> String? {
        guard !text.isEmpty, !pattern.isEmpty else { return nil }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, range: range) {
            let groupIndex = match.numberOfRanges > 1 ? match.numberOfRanges - 1 : 0
            if let r = Range(match.range(at: groupIndex), in: text) { return String(text[r]).trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    private func buildLineHints(from blocks: [TextBlock]) -> [String] {
        guard !blocks.isEmpty else { return [] }

        let isRotated = blocks.count > 5 && detectRotation(blocks)
        let sortedBlocks = isRotated
            ? blocks.sorted { $0.box.minX < $1.box.minX }
            : blocks.sorted { $0.box.minY > $1.box.minY }

        var groupedLines: [[TextBlock]] = []
        for block in sortedBlocks {
            guard var lastLine = groupedLines.last else {
                groupedLines.append([block])
                continue
            }

            let reference = lastLine.last!
            let sameLine = isRotated
                ? abs(reference.box.midX - block.box.midX) < 0.03
                : abs(reference.box.midY - block.box.midY) < 0.02

            if sameLine {
                lastLine.append(block)
                groupedLines[groupedLines.count - 1] = lastLine
            } else {
                groupedLines.append([block])
            }
        }

        return groupedLines
            .map { processLine($0, sortByY: isRotated).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func extractFields(fromStructuredText text: String) -> [String: String] {
        var fields: [String: String] = [:]
        let lines = text.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 提取所有包含":"的行，自动作为键值对
        for line in lines {
            guard line.contains(":") || line.contains("：") else { continue }
            guard !line.contains("【") else { continue } // 跳过标题行

            // 分割键和值
            let separator = line.contains(":") ? ":" : "："
            let components = line.components(separatedBy: separator)
            guard components.count >= 2 else { continue }

            let key = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = components.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !key.isEmpty, !value.isEmpty else { continue }
            guard value != "未识别" else { continue } // 跳过未识别的字段

            // 统一常用字段名称
            switch key {
            case "姓名":
                fields["病人姓名"] = value
                fields["姓名"] = value
            case "医院", "医疗机构", "商家名称":
                fields["商家名称"] = value
                fields["医疗机构"] = value
                fields["医院"] = value
            case "总金额", "金额", "合计": fields["总金额"] = value
            case "时间", "日期", "开票时间": fields["时间"] = value
            default: fields[key] = value
            }
        }

        // 收集所有明细项
        let detailLines = lines.filter {
            $0.contains(":") && !$0.contains("【") && !fields.keys.contains($0.components(separatedBy: ":")[0].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !detailLines.isEmpty {
            fields["明细信息"] = detailLines.joined(separator: "\n")
            fields["项目数"] = "\(detailLines.count)"
        }

        return fields
    }

    private func extractLabeledValue(in text: String, keys: [String]) -> String? {
        for key in keys {
            if let value = extractRegex(text, pattern: "\(key)[:：]?([\\u4e00-\\u9fa5A-Za-z0-9·]{1,12})") {
                return value
            }
        }
        return nil
    }

    private func extractNamedField(in text: String, keys: [String]) -> String? {
        let stopKeys = ["姓名", "性别", "年龄", "门诊号", "门诊", "条码号", "条码", "样本号", "科室", "备注", "单位", "电话", "地址", "时间", "医院", "商家", "采集者", "送检医生", "临床诊断"]
        let stopPattern = stopKeys.joined(separator: "|")
        for key in keys {
            // 标准格式匹配：字段名: 值 或 字段名：值
            if let value = extractRegex(text, pattern: "\(key)[:：]?([\\u4e00-\\u9fa5A-Za-z0-9·\\s]{1,30}?)(?=\(stopPattern)|$)"), !value.isEmpty {
                return cleanupExtractedValue(value, for: key)
            }
        }

        // 特殊匹配：姓名和年龄在同一行的情况，比如 "31岁 邢嘉幸"
        if keys.contains("姓名") {
            if let nameMatch = extractRegex(text, pattern: "岁\\s*([\\u4e00-\\u9fa5]{2,4})"), !nameMatch.isEmpty {
                return nameMatch
            }
        }
        if keys.contains("年龄") {
            if let ageMatch = extractRegex(text, pattern: "(\\d{1,3})岁"), !ageMatch.isEmpty {
                return ageMatch + "岁"
            }
        }
        // 特殊匹配：条码号
        if keys.contains("条码号") {
            // 只提取条码号后面的数字部分，忽略后面的其他内容
            if let barcodeMatch = extractRegex(text, pattern: "条码号[:：]?\\s*(\\d{10,20})"), !barcodeMatch.isEmpty {
                return barcodeMatch
            }
            // 匹配行首或行中连续的10-20位数字（可能是条码号）
            if let barcodeMatch2 = extractRegex(text, pattern: "(?:^|\\s)(\\d{10,20})(?:\\s|$)"), !barcodeMatch2.isEmpty {
                return barcodeMatch2
            }
        }
        // 特殊匹配：门诊号/样本号
        if keys.contains("门诊号") {
            if let outpatientMatch = extractRegex(text, pattern: "(202\\d{10,}CLI\\d+)"), !outpatientMatch.isEmpty {
                return outpatientMatch
            }
        }
        // 特殊匹配：临床诊断
        if keys.contains("临床诊断") {
            // 匹配临床诊断后面的内容，直到遇到其他字段关键词或结束
            let stopPattern = "医院|门诊号|条码号|科室|医生|采集者|时间|年龄|性别|姓名"
            if let diagnosisMatch = extractRegex(text, pattern: "临床诊断[:：]?\\s*([\\u4e00-\\u9fa5a-zA-Z0-9\\s]{2,30}?)(?=\(stopPattern)|$)"), !diagnosisMatch.isEmpty {
                return diagnosisMatch.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // 特殊匹配：科室
        if keys.contains("科室") {
            // 匹配"科室:"后面的内容，直到遇到数字、性别等无关信息
            if let departmentMatch = extractRegex(text, pattern: "科室[:：]?\\s*([\\u4e00-\\u9fa5]{2,10}科)(?![\\u4e00-\\u9fa5]*[0-9岁男女])"), !departmentMatch.isEmpty {
                return departmentMatch
            }
            // 匹配包含"科"字的科室名称，排除后面跟着年龄、性别的情况
            if let departmentMatch2 = extractRegex(text, pattern: "([\\u4e00-\\u9fa5]{2,10}科)(?!.*[0-9岁男女])"), !departmentMatch2.isEmpty {
                return departmentMatch2
            }
        }
        // 特殊匹配：送检医生/采集者
        if keys.contains("送检医生") {
            if let doctorMatch = extractRegex(text, pattern: "送检医生\\s*([\\u4e00-\\u9fa5]{2,4})"), !doctorMatch.isEmpty {
                return doctorMatch
            }
        }
        if keys.contains("采集者") {
            if let collectorMatch = extractRegex(text, pattern: "采集者\\s*([\\u4e00-\\u9fa5]{2,4})"), !collectorMatch.isEmpty {
                return collectorMatch
            }
        }

        return nil
    }

    private func extractStructuredValue(in lines: [String], key: String) -> String? {
        for line in lines {
            guard line.hasPrefix("\(key):") || line.hasPrefix("\(key)：") else { continue }
            let value = line
                .replacingOccurrences(of: "\(key):", with: "")
                .replacingOccurrences(of: "\(key)：", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func cleanupExtractedValue(_ value: String, for key: String) -> String {
        var cleaned = value
        let noiseWords = ["姓名", "性别", "年龄", "门诊号", "门诊", "条码号", "条码", "样本号", "号", "岁"]
        for word in noiseWords where word != key {
            cleaned = cleaned.replacingOccurrences(of: word, with: "")
        }
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ":： "))

        // 年龄字段特殊处理
        if key == "年龄" {
            // 过滤掉非数字内容
            let digits = cleaned.filter { $0.isNumber }
            if digits.isEmpty {
                return "未识别"
            }
            if cleaned.contains("岁") == false, digits.allSatisfy({ $0.isNumber }) {
                return digits + "岁"
            }
            return cleaned
        }

        // 如果清理后内容为空，返回未识别
        if cleaned.isEmpty {
            return "未识别"
        }

        return cleaned
    }

    private func extractMedicalItems(from lines: [String]) -> [MedicalOCRItem] {
        let blacklist = ["结果", "单位", "参考", "范围", "标志", "状态", "样本", "类型", "项目", "名称", "备注", "性别", "姓名", "年龄", "门诊", "条码", "科室", "病区", "报告"]
        var items: [MedicalOCRItem] = []

        for rawLine in lines {
            let line = rawLine.replacingOccurrences(of: "★", with: "")
                .replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if line.count < 4 { continue }
            if blacklist.contains(where: { line == $0 || line.contains($0 + ":") }) { continue }

            let numbers = line.matches(for: "\\d+(?:\\.\\d+)?")
            guard numbers.count >= 1 else { continue }

            let result = numbers[0]
            let range = numbers.count >= 3 ? "\(numbers[1])~\(numbers[2])" : (numbers.count == 2 ? numbers[1] : "")

            var name = line
            name = name.replacingOccurrences(of: "^\\d+[\\.、]?", with: "", options: .regularExpression)
            name = name.replacingOccurrences(of: result, with: "")
            name = name.replacingOccurrences(of: "\\d+(?:\\.\\d+)?", with: " ", options: .regularExpression)
            name = name.replacingOccurrences(of: "[()（）~<>-]", with: " ", options: .regularExpression)
            name = name.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

            guard name.count >= 2 else { continue }
            guard !blacklist.contains(where: { name.contains($0) }) else { continue }

            if items.contains(where: { $0.name == name && $0.result == result }) {
                continue
            }

            items.append(MedicalOCRItem(name: name, result: result, range: range))
        }

        return items
    }

    private func cleanupModelOutput(_ output: String) -> String {
        // 过滤明显的幻觉内容
        let hallucinationKeywords = [
            "自适应旋转引擎",
            "系统已自动检测到图片存在",
            "90度偏转",
            "重组了纵向文本流",
            "引擎已激活",
            "注意事项",
            "建议咨询医生"
        ]

        let lines = output.components(separatedBy: .newlines)
        var cleanedLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // 检查是否包含幻觉关键词
            let isHallucination = hallucinationKeywords.contains { keyword in
                trimmed.contains(keyword)
            }

            guard !isHallucination else { continue }

            // 保留有效的行
            cleanedLines.append(trimmed)
        }

        return cleanedLines.joined(separator: "\n")
    }

    private func extractHospital(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // 先尝试从包含医院关键词的行中提取医院名称部分
        if let lineWithHospital = lines.first(where: { $0.contains("医院") || $0.contains("卫生院") || $0.contains("诊所") }) {
            // 提取医院名称：匹配到"医院"、"卫生院"或"诊所"结尾的部分
            if let hospitalRange = lineWithHospital.range(of: ".*?(?:医院|卫生院|诊所)", options: .regularExpression) {
                let hospitalName = String(lineWithHospital[hospitalRange])
                    .replacingOccurrences(of: " ", with: "")
                    // 过滤掉医院名称前面的数字和其他无关字符
                    .replacingOccurrences(of: "^[0-9\\s\\-]+", with: "", options: .regularExpression)
                if !hospitalName.isEmpty {
                    return hospitalName
                }
            }
        }

        // 如果行匹配失败，再用正则表达式从全文提取
        let normalizedText = text.replacingOccurrences(of: " ", with: "")
        return extractRegex(normalizedText, pattern: "([\\u4e00-\\u9fa5]{2,30}(?:医院|卫生院|诊所))")
    }

    private func scoreRecognizedText(_ text: String, blockCount: Int) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let chineseCount = trimmed.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
        let digitCount = trimmed.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let lineCount = trimmed.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
        let keywordBonus = ["医院", "报告", "检验", "结果", "参考范围", "姓名", "年龄", "门诊号"]
            .reduce(0) { partialResult, keyword in
                partialResult + (trimmed.contains(keyword) ? 30 : 0)
            }

        return chineseCount * 3 + digitCount + lineCount * 8 + blockCount * 5 + keywordBonus
    }

    private func ocrOrientations(startingFrom orientation: CGImagePropertyOrientation) -> [CGImagePropertyOrientation] {
        var orientations: [CGImagePropertyOrientation] = [orientation]
        for candidate in [CGImagePropertyOrientation.up, .right, .left, .down] where !orientations.contains(candidate) {
            orientations.append(candidate)
        }
        return orientations
    }

    /// 解析多模态模型返回的结构化结果
    private func parseMultimodalResult(_ result: String) -> (String, ReceiptType, [String: String]) {
        var fields: [String: String] = [:]
        var type: ReceiptType = .other
        let lines = result.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // 提取所有键值对
        for line in lines {
            guard line.contains(":") || line.contains("：") else { continue }
            guard !line.contains("【") else { continue } // 跳过标题行

            let separator = line.contains(":") ? ":" : "："
            let components = line.components(separatedBy: separator)
            guard components.count >= 2 else { continue }

            let key = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = components.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !key.isEmpty, !value.isEmpty, value != "未识别" else { continue }

            // 统一字段名
            switch key {
            case "票据类型":
                if value.contains("医疗") {
                    type = .medical
                    fields["分类"] = "医疗"
                    fields["票据类型"] = "医疗"
                } else if value.contains("餐饮") || value.contains("吃饭") || value.contains("餐") {
                    type = .food
                    fields["分类"] = "餐饮"
                    fields["票据类型"] = "餐饮"
                } else if value.contains("购物") || value.contains("超市") || value.contains("商品") {
                    type = .shopping
                    fields["分类"] = "购物"
                    fields["票据类型"] = "购物"
                } else if value.contains("交通") || value.contains("打车") || value.contains("机票") || value.contains("火车") {
                    type = .transport
                    fields["分类"] = "交通"
                    fields["票据类型"] = "交通"
                }
            case "医疗机构", "医院", "商家名称":
                fields["商家名称"] = value
                fields["医疗机构"] = value
                fields["医院"] = value
            case "病人姓名", "姓名":
                fields["病人姓名"] = value
                fields["姓名"] = value
            case "性别": fields["性别"] = value
            case "年龄": fields["年龄"] = value
            case "科室": fields["科室"] = value
            case "门诊号", "就诊号": fields["门诊号"] = value
            case "条码号", "票据号", "编号": fields["条码号"] = value
            case "时间", "日期", "就诊时间", "开票时间": fields["时间"] = value
            case "临床诊断", "诊断": fields["临床诊断"] = value
            case "总金额", "金额", "合计", "总价": fields["总金额"] = value
            default: fields[key] = value
            }
        }

        // 补充解析模式字段
        fields["解析模式"] = "多模态直接识图"
        fields["模型版本"] = ModelManager.shared.currentModelName

        return (result, type, fields)
    }

    private func cgImageOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

private struct MedicalOCRItem {
    let name: String
    let result: String
    let range: String
}

private extension String {
    func matches(for pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..., in: self)
        return regex.matches(in: self, range: range).compactMap { match in
            guard let r = Range(match.range, in: self) else { return nil }
            return String(self[r])
        }
    }
}
