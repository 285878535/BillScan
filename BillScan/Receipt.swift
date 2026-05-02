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

enum ReceiptType: String, Codable, CaseIterable {
    case medical = "医疗检验单"
    case shopping = "购物小票"
    case food = "餐饮发票"
    case transport = "交通票据"
    case other = "其他票据"
}
