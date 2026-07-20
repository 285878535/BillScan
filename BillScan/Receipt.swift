import Foundation
import SwiftData

@Model
class Category: Identifiable {
    var id: UUID
    var name: String
    var iconName: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, iconName: String = "folder", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.createdAt = createdAt
    }
}

@Model
class Receipt: Identifiable {
    var id: UUID
    var type: ReceiptType
    var patientName: String?
    var amount: Double?
    var date: Date
    var merchantName: String?
    var category: String
    var extractedText: String
    var additionalFields: [String: String]?
    var imageData: Data
    var createdAt: Date

    init(
        id: UUID = UUID(),
        type: ReceiptType,
        patientName: String? = nil,
        amount: Double? = nil,
        date: Date = Date(),
        merchantName: String? = nil,
        category: String,
        extractedText: String,
        additionalFields: [String: String]? = [:],
        imageData: Data,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.patientName = patientName
        self.amount = amount
        self.date = date
        self.merchantName = merchantName
        self.category = category
        self.extractedText = extractedText
        self.additionalFields = additionalFields
        self.imageData = imageData
        self.createdAt = createdAt
    }
}

extension Receipt {
    /// 列表和详情的展示标题：优先用能区分单据的具体信息，而不是笼统的类型名。
    var displayTitle: String {
        let fields = additionalFields ?? [:]
        switch type {
        case .medical:
            let name = patientName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail = (fields["临床诊断"] ?? fields["科室"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !detail.isEmpty {
                return "\(name) · \(detail)"
            }
            if !detail.isEmpty {
                return detail
            }
            if !name.isEmpty {
                return name
            }
            return merchantName ?? type.rawValue
        case .shopping, .food, .transport, .other:
            if let merchant = merchantName?.trimmingCharacters(in: .whitespacesAndNewlines), !merchant.isEmpty {
                return merchant
            }
            return type.rawValue
        }
    }

    /// 列表的副标题：医疗显示医院，其他显示票据类型（标题已被商家名占用）；与标题重复时返回空。
    var displaySubtitle: String {
        let subtitle: String
        if type == .medical, let hospital = merchantName?.trimmingCharacters(in: .whitespacesAndNewlines), !hospital.isEmpty {
            subtitle = hospital
        } else {
            subtitle = type.rawValue
        }
        return subtitle == displayTitle ? "" : subtitle
    }
}

enum ReceiptType: String, Codable, CaseIterable {
    case medical = "医疗检验单"
    case shopping = "购物小票"
    case food = "餐饮发票"
    case transport = "交通票据"
    case other = "其他票据"
}
