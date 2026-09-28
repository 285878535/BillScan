import XCTest
import SwiftData
import UserNotifications
import UIKit
@testable import BillScan

final class HealthTests: XCTestCase {
    func testLiteralInstructionsAreExtractedButNeverConfirmed() {
        let medicines = MedicationParser.parse("门诊处方笺\n阿莫西林胶囊\n用法：每次2粒，每日三次，连用5天\n氯雷他定片\n每次1片 每日1次 共7天")
        XCTAssertEqual(medicines.count, 2)
        XCTAssertEqual(medicines.first?.name, "阿莫西林胶囊")
        XCTAssertEqual(medicines.first?.frequency, 3)
        XCTAssertEqual(medicines.first?.days, 5)
        XCTAssertEqual(medicines.first?.dose, "2粒")
        XCTAssertEqual(medicines.last?.frequency, 1)
        XCTAssertFalse(medicines.contains { $0.confirmed || $0.reminderEnabled })
    }
    func testMissingInstructionsStayUnknown() {
        let medicines = MedicationParser.parse("氯雷他定片\n规格：10mg×10片")
        XCTAssertEqual(medicines.count, 1)
        XCTAssertEqual(medicines.first?.frequency, 0)
        XCTAssertEqual(medicines.first?.days, 0)
        XCTAssertEqual(medicines.first?.dose, "")
    }
    func testIntervalInstructionsAreNotDailyFrequency() {
        let medicines = MedicationParser.parse("阿莫西林胶囊\n每次1粒，每隔8小时一次，必要时服用")
        XCTAssertEqual(medicines.first?.frequency, 0)
        XCTAssertTrue(medicines.first?.instructions.contains("每隔8小时") == true)
    }
    @MainActor func testDataSurvivesReopenAndCascadeDeletes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("health.store")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let schema = Schema([HealthEpisode.self, HealthDocument.self])
        let configuration = ModelConfiguration(schema: schema, url: url)
        var container: ModelContainer? = try ModelContainer(for: schema, configurations: configuration)
        let episodeID: UUID
        do {
            let context = ModelContext(container!)
            let episode = HealthEpisode(name: "保存测试")
            episodeID = episode.id
            context.insert(episode)
            let document = HealthDocument(title: "门诊药方", kind: .prescription, episode: episode)
            document.medications = [MedicationEntry(name: "测试药", dose: "1片", frequency: 2, days: 3)]
            document.images = [Data([1,2,3,4])]
            context.insert(document)
            try context.save()
        }
        container = nil
        let reopened = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(reopened)
        let episodes = try context.fetch(FetchDescriptor<HealthEpisode>())
        XCTAssertEqual(episodes.first?.id, episodeID)
        XCTAssertEqual(episodes.first?.documents.count, 1)
        XCTAssertEqual(episodes.first?.documents.first?.images.first, Data([1,2,3,4]))
        XCTAssertEqual(episodes.first?.documents.first?.medications.first?.frequency, 2)
        context.delete(try XCTUnwrap(episodes.first)); try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<HealthDocument>()), 0)
    }
}

extension HealthTests {
    @MainActor func testReminderDatesAreFiniteAndPastTimesExcluded() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29))!
        let now = calendar.date(byAdding: .hour, value: 9, to: start)!
        let medicine = MedicationEntry(name: "测试药", dose: "1片", frequency: 2, days: 3, confirmed: true, startDate: start, times: [8 * 60, 18 * 60], reminderEnabled: true)
        let requests = try HealthReminders.requests(documentID: UUID(), medications: [medicine], now: now, calendar: calendar)
        XCTAssertEqual(requests.count, 5)
        XCTAssertTrue(requests.allSatisfy { ($0.trigger as? UNCalendarNotificationTrigger)?.repeats == false })
        let last = try XCTUnwrap(requests.last?.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(last.dateComponents.day, 1)
        XCTAssertEqual(last.dateComponents.month, 10)
        XCTAssertEqual(last.dateComponents.hour, 18)
    }
    @MainActor func testLegacyStoreMigrationRetainsExistingReceipts() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("legacy.store")
        let oldSchema = Schema([Receipt.self, Category.self])
        var old: ModelContainer? = try ModelContainer(for: oldSchema, configurations: ModelConfiguration(schema: oldSchema, url: url))
        do {
            let context = ModelContext(old!)
            context.insert(Receipt(type: .medical, category: "原有医疗资料", extractedText: "原有内容", imageData: Data([9,8,7])))
            try context.save()
        }
        old = nil
        let newSchema = Schema([Receipt.self, Category.self, HealthEpisode.self, HealthDocument.self])
        let upgraded = try ModelContainer(for: newSchema, configurations: ModelConfiguration(schema: newSchema, url: url))
        let receipts = try ModelContext(upgraded).fetch(FetchDescriptor<Receipt>())
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts.first?.extractedText, "原有内容")
        XCTAssertEqual(receipts.first?.imageData, Data([9,8,7]))
    }
}

extension HealthTests {
    @MainActor func testRealVisionOCRProducesEditablePrescription() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 700))
        let data = renderer.jpegData(withCompressionQuality: 0.95) { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1000, height: 700))
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 30
            ("门诊处方笺\n阿莫西林胶囊\n用法：每次2粒，每日三次，连用5天" as NSString).draw(in: CGRect(x: 50, y: 50, width: 900, height: 600), withAttributes: [.font: UIFont.systemFont(ofSize: 44), .foregroundColor: UIColor.black, .paragraphStyle: paragraph])
        }
        let result = try await HealthOCR.recognize(data)
        XCTAssertEqual(result.kind, .prescription)
        XCTAssertTrue(result.text.contains("阿莫西林"))
        XCTAssertEqual(result.medications.first?.frequency, 3)
        XCTAssertEqual(result.medications.first?.days, 5)
        XCTAssertFalse(result.medications.first?.confirmed ?? true)
    }
}

extension HealthTests {
    @MainActor func testUnconfirmedAndDuplicateReminderTimesRejected() throws {
        var medicine = MedicationEntry(name: "测试", dose: "1片", frequency: 2, days: 3, times: [480, 1080], reminderEnabled: true)
        XCTAssertThrowsError(try HealthReminders.requests(documentID: UUID(), medications: [medicine]))
        medicine.confirmed = true
        medicine.times = [480, 480]
        XCTAssertThrowsError(try HealthReminders.requests(documentID: UUID(), medications: [medicine]))
        medicine.times = [480, 1080]
        medicine.days = -1
        XCTAssertThrowsError(try HealthReminders.requests(documentID: UUID(), medications: [medicine]))
    }
    @MainActor func testCancellationKeepsOtherPrescriptions() async throws {
        let center = UNUserNotificationCenter.current()
        let first = UUID(), second = UUID()
        for id in [first, second] {
            let content = UNMutableNotificationContent(); content.title = "自动测试"
            try await center.add(UNNotificationRequest(identifier: "health.\(id.uuidString).test", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)))
        }
        await HealthReminders.cancel(documentID: first)
        let pending = await center.pendingNotificationRequests()
        XCTAssertFalse(pending.contains { $0.identifier.contains(first.uuidString) })
        XCTAssertTrue(pending.contains { $0.identifier.contains(second.uuidString) })
        await HealthReminders.cancel(documentID: second)
    }
}

extension HealthTests {
    @MainActor func testSameTimeMedicinesShareOneNotification() throws {
        let start = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
        let first = MedicationEntry(name: "药品A", dose: "1片", frequency: 2, days: 3, confirmed: true, startDate: start, times: [480, 1080], reminderEnabled: true)
        var second = first; second.id = UUID(); second.name = "药品B"
        let requests = try HealthReminders.requests(documentID: UUID(), medications: [first, second])
        XCTAssertEqual(requests.count, 6)
        XCTAssertTrue(requests.allSatisfy { $0.content.body.contains("药品A") && $0.content.body.contains("药品B") })
    }
}

extension HealthTests {
    @MainActor func testNotificationCoverageDoesNotChangePrescriptionCourse() throws {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date().addingTimeInterval(86400))
        let through = calendar.date(byAdding: .day, value: 6, to: start)!
        let medicine = MedicationEntry(name: "药品A", dose: "1片", frequency: 2, days: 90, confirmed: true, startDate: start, times: [480, 1080], reminderEnabled: true, reminderThrough: through)
        let requests = try HealthReminders.requests(documentID: UUID(), medications: [medicine])
        XCTAssertEqual(requests.count, 14)
        XCTAssertEqual(medicine.days, 90)
        let data = try JSONEncoder().encode(medicine)
        XCTAssertEqual(try JSONDecoder().decode(MedicationEntry.self, from: data).reminderThrough, through)
    }
}
