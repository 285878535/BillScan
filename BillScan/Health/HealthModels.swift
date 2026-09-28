import Foundation
import SwiftData

@Model
final class HealthEpisode {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var archived: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \HealthDocument.episode)
    var documents: [HealthDocument] = []

    init(name: String) { self.name = name }
}

enum HealthDocumentKind: String, Codable, CaseIterable {
    case record = "病历"
    case prescription = "药方"
}

struct MedicationEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var dose = ""
    var instructions = ""
    var frequency = 0
    var days = 0
    var confirmed = false
    var startDate = Date()
    /// Minutes after local midnight, explicitly confirmed by the user.
    var times: [Int] = []
    var reminderEnabled = false
    /// Optional notification coverage limit, separate from the physician's full course.
    var reminderThrough: Date? = nil

    var courseEnd: Date {
        Calendar.current.date(byAdding: .day, value: max(0, days - 1), to: Calendar.current.startOfDay(for: startDate)) ?? startDate
    }

    var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !dose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (1...6).contains(frequency) && (1...365).contains(days) && confirmed
    }
    var summary: String {
        let components = [dose.isEmpty ? nil : "每次 \(dose)", frequency > 0 ? "每日 \(frequency) 次" : nil]
        return components.compactMap { $0 }.joined(separator: " · ")
    }
}

@Model
final class HealthDocument {
    var id: UUID = UUID()
    var title: String = ""
    var kindRaw: String = HealthDocumentKind.record.rawValue
    var date: Date = Date()
    var createdAt: Date = Date()
    var institution: String = ""
    var notes: String = ""
    var extractedText: String = ""
    var historical: Bool = false
    @Attribute(.externalStorage) var images: [Data] = []
    var medicationData: Data = Data()
    var episode: HealthEpisode?

    var kind: HealthDocumentKind {
        get { HealthDocumentKind(rawValue: kindRaw) ?? .record }
        set { kindRaw = newValue.rawValue }
    }
    var medications: [MedicationEntry] {
        get { (try? JSONDecoder().decode([MedicationEntry].self, from: medicationData)) ?? [] }
        set { medicationData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
    init(title: String, kind: HealthDocumentKind, episode: HealthEpisode? = nil) {
        self.title = title
        self.kindRaw = kind.rawValue
        self.episode = episode
    }
}
