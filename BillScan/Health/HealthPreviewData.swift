#if DEBUG
import SwiftUI
import SwiftData

/// Opt-in simulator fixture. Never writes sample health records into the user's database.
enum HealthPreviewData {
    static func populate(_ context: ModelContext) throws {
        let names = ["这次感冒", "胃部不适", "过敏复诊"]
        for (index, name) in names.enumerated() {
            let episode = HealthEpisode(name: name)
            episode.createdAt = Calendar.current.date(byAdding: .day, value: -index * 25 - 2, to: Date())!
            episode.updatedAt = episode.createdAt
            episode.archived = index > 0
            context.insert(episode)
            for item in 0..<(index == 0 ? 4 : 2) {
                let kind: HealthDocumentKind = item % 2 == 0 ? .record : .prescription
                let document = HealthDocument(title: kind == .record ? "门诊病历" : "门诊药方", kind: kind, episode: episode)
                document.date = Calendar.current.date(byAdding: .day, value: item < 2 ? 0 : -7, to: episode.createdAt)!
                document.institution = "示例医院 · 门诊"
                document.extractedText = kind == .record ? "门诊病历\n示例资料\n主诉：咽部不适。\n就诊记录：此处为界面预览数据。\n请保留原始病历，并核对识别结果。" : "门诊处方笺\n示例资料\n示例药品 A\n每次1片，每日2次，共7天\n示例药品 B\n用法待确认"
                if kind == .prescription {
                    var medicine = MedicationEntry(name: "示例药品 A", dose: "1片", frequency: 2, days: 7, confirmed: true)
                    medicine.startDate = Date()
                    document.medications = [medicine, MedicationEntry(name: "示例药品 B")]
                    document.historical = item > 1 || index > 0
                }
                document.images = [page(document.extractedText)]
                context.insert(document)
            }
        }
        try context.save()
    }
    private static func page(_ text: String) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 760))
        return renderer.jpegData(withCompressionQuality: 0.9) { ctx in
            UIColor(white: 0.98, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 760))
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 22
            (text as NSString).draw(in: CGRect(x: 45, y: 60, width: 510, height: 640), withAttributes: [.font: UIFont.systemFont(ofSize: 25), .foregroundColor: UIColor.darkGray, .paragraphStyle: paragraph])
        }
    }
}
#endif
