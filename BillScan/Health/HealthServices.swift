import Foundation
import Vision
import UIKit
import UserNotifications

struct HealthRecognition {
    var text: String
    var medications: [MedicationEntry]
    var kind: HealthDocumentKind
}

enum HealthOCR {
    /// Uses only the local Vision framework. Never uploads health documents.
    static func recognize(_ data: Data) async throws -> HealthRecognition {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(data: data)
            try handler.perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            guard !text.isEmpty else { throw HealthServiceError.message("没有识别到清晰文字。请重新拍摄，或保留原图并手动填写。") }
            let kind: HealthDocumentKind = text.contains("处方") || text.contains("药方") || text.contains("用法") ? .prescription : .record
            return HealthRecognition(text: text, medications: MedicationParser.parse(text), kind: kind)
        }.value
    }
}

enum HealthServiceError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

/// Only extracts literal instructions associated with a medicine line. It does not infer from drug names.
nonisolated enum MedicationParser {
    static func capture(_ pattern: String, _ text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
    static func number(_ text: String?) -> Int {
        guard let text else { return 0 }
        return Int(text) ?? ["一":1,"二":2,"两":2,"三":3,"四":4][text] ?? 0
    }
    static func parse(_ text: String) -> [MedicationEntry] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var results: [MedicationEntry] = []
        for line in lines {
            // Recognizable dosage-form suffix, plus an explicit sample format for deterministic tests.
            let name = capture(#"(?:^|\s|[0-9]+[.、])([\p{Han}A-Za-z][\p{Han}A-Za-z0-9·（）()\-]{1,30}(?:片|胶囊|颗粒|口服液|滴眼液|软膏|丸|散|注射液))"#, line)
                ?? capture(#"(示例药品\s*[A-Z])"#, line)
            if let name, !["每次", "每日", "每天", "用法", "规格", "口服", "一次", "一日", "用量"].contains(where: { name.hasPrefix($0) }) {
                results.append(MedicationEntry(name: name))
            }
            guard !results.isEmpty else { continue }
            let i = results.count - 1
            if let dose = capture(#"每次\s*([0-9]+(?:\.[0-9]+)?\s*(?:片|粒|袋|丸|滴|毫升|ml|mg|克|毫克))"#, line) { results[i].dose = dose }
            let frequency = number(capture(#"(?:每日|一天|每天|一日)\s*([1-4一二两三四])\s*次"#, line))
            if frequency > 0 { results[i].frequency = frequency }
            // Do not reinterpret 'every 8 hours' as 'three times daily'. Preserve the original instruction.
            if let days = capture(#"(?:服用|连用|疗程|共|用药)\s*([0-9]{1,3})\s*[天日]"#, line) { results[i].days = Int(days) ?? 0 }
            if line.contains("用法") || line.contains("每次") || line.contains("餐") || line.contains("饭") || line.contains("小时") {
                results[i].instructions += (results[i].instructions.isEmpty ? "" : "\n") + line
            }
        }
        return results
    }
}

enum HealthReminders {
    static let center = UNUserNotificationCenter.current()
    static func cancel(documentID: UUID) async {
        let prefix = "health.\(documentID.uuidString)."
        let requests = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: requests.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier))
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix(prefix) }.map { $0.request.identifier })
    }
    static func requests(documentID: UUID, medications: [MedicationEntry], now: Date = Date(), calendar: Calendar = .current) throws -> [UNNotificationRequest] {
        let enabled = medications.filter(\.reminderEnabled)
        guard enabled.allSatisfy({ $0.isComplete && $0.times.count == $0.frequency && Set($0.times).count == $0.times.count && $0.times.allSatisfy { (0..<1440).contains($0) } }) else {
            throw HealthServiceError.message("请核对药名、每次用量、频次和疗程，并为每次用药设置不同的提醒时间。")
        }
        let prefix = "health.\(documentID.uuidString)."
        var doses: [Date: [MedicationEntry]] = [:]
        for medicine in enabled {
            for day in 0..<medicine.days {
                guard let date = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: medicine.startDate)) else { continue }
                if let through = medicine.reminderThrough, calendar.startOfDay(for: date) > calendar.startOfDay(for: through) { continue }
                for minute in medicine.times {
                    guard let fire = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: date), fire > now else { continue }
                    doses[fire, default: []].append(medicine)
                }
            }
        }
        // One notification per prescription/time slot avoids multiple simultaneous alerts and saves system slots.
        let requests = doses.keys.sorted().map { fire -> UNNotificationRequest in
            let content = UNMutableNotificationContent()
            content.title = "用药提醒"
            content.body = (doses[fire] ?? []).map { "\($0.name) · 本次 \($0.dose)" }.joined(separator: "\n") + "\n请按已确认的医嘱服用。"
            content.sound = .default
            content.userInfo = ["documentID": documentID.uuidString]
            let id = prefix + String(Int(fire.timeIntervalSince1970))
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            return UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        }
        guard !requests.isEmpty else { throw HealthServiceError.message("所选疗程已经结束，或本疗程的提醒时间均已过去。请核对开始日期和天数。") }
        return requests
    }
    static func schedule(documentID: UUID, medications: [MedicationEntry], historical: Bool) async throws {
        let enabled = medications.filter(\.reminderEnabled)
        if historical || enabled.isEmpty { await cancel(documentID: documentID); return }
        let requests = try requests(documentID: documentID, medications: medications)
        guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else {
            throw HealthServiceError.message("通知权限未开启，请到系统设置中允许通知后重试。药方仍可正常保存。")
        }
        let prefix = "health.\(documentID.uuidString)."
        let pending = await center.pendingNotificationRequests()
        let old = pending.filter { $0.identifier.hasPrefix(prefix) }
        guard pending.count - old.count + requests.count <= 60 else {
            throw HealthServiceError.message("当前疗程超出系统可安排的通知数量。请调整“本次提醒至”的日期，或关闭其他药方提醒后重试；不需要修改原药方疗程。超出所选日期的时间不会自动提醒。")
        }
        center.removePendingNotificationRequests(withIdentifiers: old.map(\.identifier))
        do { for request in requests { try await center.add(request) } }
        catch {
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier))
            for request in old { try? await center.add(request) }
            throw error
        }
    }
}
