import Foundation
import UIKit

/// 扣子（Coze）智能体服务：上传票据图片后由多模态智能体直接识别。
/// 接口参考 speak 项目 backend/app/services/ai.py 的 _coze_chat 实现。
final class CozeService {
    static let shared = CozeService()

    private init() {}

    struct ServiceError: Error {
        let message: String
    }

    private static let uploadURL = URL(string: "https://api.coze.cn/v1/files/upload")!
    private static let chatURL = URL(string: "https://api.coze.cn/v3/chat")!

    private static let receiptPrompt = """
    你是票据整理助手。请仔细查看这张票据图片，提取真实存在的信息，输出简洁中文结构化结果。

    要求：
    1. 只输出图片中真实存在的信息，不要脑补。
    2. 第一行输出“票据类型: 值”，值从 医疗/餐饮/购物/交通/其他 中选择。
    3. 优先输出：商家名称（医疗票据用“医院”）、姓名、时间、总金额。
    4. 如果是医疗票据，补充性别、年龄、科室、门诊号、条码号、临床诊断、检验项目。
    5. 每行一个字段，格式为“字段名: 值”，不要输出 markdown、代码块或任何解释。
    6. 没有把握的字段不要输出。
    """

    /// 识别票据图片，返回“字段名: 值”结构化文本。失败自动重试一次（对齐 speak 的做法）。
    func parseReceipt(image: UIImage, completion: @escaping (Result<String, ServiceError>) -> Void) {
        let modelManager = ModelManager.shared
        guard modelManager.hasValidCozeConfiguration else {
            complete(completion, with: .failure(ServiceError(message: "扣子未配置")))
            return
        }
        guard let imageData = Self.compressedJPEG(from: image) else {
            complete(completion, with: .failure(ServiceError(message: "图片编码失败")))
            return
        }

        let token = modelManager.cozeAPIToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let botID = modelManager.cozeBotID.trimmingCharacters(in: .whitespacesAndNewlines)

        uploadFile(imageData, token: token) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let fileID):
                self.chat(token: token, botID: botID, fileID: fileID, hasRetried: false, completion: completion)
            case .failure(let error):
                self.complete(completion, with: .failure(error))
            }
        }
    }

    /// 连通性测试：发一条纯文本消息，收到任意回复即成功。
    func testConnection(token: String, botID: String, completion: @escaping (Bool, String) -> Void) {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let botID = botID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !botID.isEmpty else {
            completion(false, "配置不完整")
            return
        }

        sendChat(token: token, botID: botID, contentType: "text", content: "请只回复 OK") { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    completion(true, "连接成功")
                case .failure(let error):
                    completion(false, error.message)
                }
            }
        }
    }

    // MARK: - 私有实现

    private func chat(
        token: String,
        botID: String,
        fileID: String,
        hasRetried: Bool,
        completion: @escaping (Result<String, ServiceError>) -> Void
    ) {
        // 多模态消息：content_type 为 object_string，content 是 JSON 编码后的字符串
        let objectItems: [[String: String]] = [
            ["type": "image", "file_id": fileID],
            ["type": "text", "text": Self.receiptPrompt]
        ]
        guard let objectData = try? JSONSerialization.data(withJSONObject: objectItems),
              let objectString = String(data: objectData, encoding: .utf8) else {
            complete(completion, with: .failure(ServiceError(message: "消息编码失败")))
            return
        }

        sendChat(token: token, botID: botID, contentType: "object_string", content: objectString) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let answer):
                self.complete(completion, with: .success(answer))
            case .failure(let error):
                // 扣子偶发 "gen fail"，失败自动重试一次
                if hasRetried {
                    self.complete(completion, with: .failure(error))
                } else {
                    self.chat(token: token, botID: botID, fileID: fileID, hasRetried: true, completion: completion)
                }
            }
        }
    }

    private func sendChat(
        token: String,
        botID: String,
        contentType: String,
        content: String,
        completion: @escaping (Result<String, ServiceError>) -> Void
    ) {
        var request = URLRequest(url: Self.chatURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "bot_id": botID,
            "user_id": "billscan",
            "stream": true,
            "auto_save_history": false,
            "additional_messages": [
                [
                    "role": "user",
                    "content_type": contentType,
                    "content": content
                ]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(ServiceError(message: error.localizedDescription)))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, let data else {
                completion(.failure(ServiceError(message: "没有拿到服务端响应")))
                return
            }
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                let detail = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
                completion(.failure(ServiceError(message: "HTTP \(httpResponse.statusCode): \(detail)")))
                return
            }
            completion(Self.parseStreamResponse(data))
        }.resume()
    }

    /// 解析扣子 v3 chat 的 SSE 响应：收集 conversation.message.completed 中 type=answer 的内容。
    private static func parseStreamResponse(_ data: Data) -> Result<String, ServiceError> {
        guard let body = String(data: data, encoding: .utf8) else {
            return .failure(ServiceError(message: "响应解码失败"))
        }

        // 权限/参数错误时扣子返回 200 + 纯 JSON 错误体（非 SSE）
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.hasPrefix("{"),
           let object = try? JSONSerialization.jsonObject(with: Data(trimmedBody.utf8)) as? [String: Any] {
            let code = object["code"] as? Int ?? -1
            let msg = (object["msg"] as? String)?.prefix(200) ?? ""
            return .failure(ServiceError(message: "扣子错误 \(code): \(msg)"))
        }

        var answerParts: [String] = []
        var event = ""
        for rawLine in body.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("event:") {
                event = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                if event == "conversation.message.completed" {
                    if let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                       object["type"] as? String == "answer",
                       let content = object["content"] as? String {
                        answerParts.append(content)
                    }
                } else if event == "conversation.chat.failed" || event == "error" {
                    return .failure(ServiceError(message: "扣子对话失败: \(payload.prefix(200))"))
                }
            }
        }

        let answer = answerParts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        // 扣子偶发把生成失败以字面文本（如 "gen fail"）当正常回复返回，按失败处理
        guard answer.count >= 4 else {
            return .failure(ServiceError(message: "扣子回复异常: \(answer)"))
        }
        return .success(answer)
    }

    private func uploadFile(_ data: Data, token: String, completion: @escaping (Result<String, ServiceError>) -> Void) {
        var request = URLRequest(url: Self.uploadURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let boundary = "billscan-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"receipt.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(ServiceError(message: error.localizedDescription)))
                return
            }
            guard let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(ServiceError(message: "上传响应解析失败")))
                return
            }
            if let code = object["code"] as? Int, code != 0 {
                let msg = (object["msg"] as? String)?.prefix(200) ?? ""
                completion(.failure(ServiceError(message: "图片上传失败 \(code): \(msg)")))
                return
            }
            guard let fileInfo = object["data"] as? [String: Any],
                  let fileID = fileInfo["id"] as? String else {
                completion(.failure(ServiceError(message: "上传响应缺少文件 ID")))
                return
            }
            completion(.success(fileID))
        }.resume()
    }

    /// 长边压到 1600px 以内再转 JPEG，控制上传体积和识别耗时。
    private static func compressedJPEG(from image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1600
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maxDimension else {
            return image.jpegData(compressionQuality: 0.8)
        }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    private func complete(_ completion: @escaping (Result<String, ServiceError>) -> Void, with result: Result<String, ServiceError>) {
        DispatchQueue.main.async {
            completion(result)
        }
    }
}
