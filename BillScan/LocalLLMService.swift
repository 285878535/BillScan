import Foundation

private struct OpenAIChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let max_tokens: Int?
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
            let reasoning_content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct AnthropicMessageRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let system: String
    let messages: [Message]
    let max_tokens: Int
}

final class LocalLLMService {
    static let shared = LocalLLMService()

    private init() {}

    struct ServiceError: Error {
        let message: String
    }

    var isRuntimeAvailable: Bool {
        ModelManager.shared.hasValidCloudConfiguration
    }

    var canProcessSelectedModel: Bool {
        ModelManager.shared.parsingModeIsAI
    }

    func unloadModel() {}

    func summarizeOCRText(_ text: String, lineHints: [String], completion: @escaping (String?) -> Void) {
        guard canProcessSelectedModel else {
            completion(nil)
            return
        }

        let prompt = buildPrompt(text: text, lineHints: lineHints)
        sendChat(prompt: prompt, systemPrompt: "你是严谨的票据整理助手。") { result in
            switch result {
            case .success(let content):
                completion(content)
            case .failure:
                completion(nil)
            }
        }
    }

    func testConnection(profile: CloudModelProfile, completion: @escaping (Bool, String) -> Void) {
        guard profile.isComplete else {
            completion(false, "配置不完整")
            return
        }

        sendChat(
            prompt: "请只回复 OK",
            systemPrompt: "你是连通性测试助手。",
            isConnectivityTest: true,
            profile: profile
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response) where !response.isEmpty:
                    completion(true, "连接成功")
                case .success:
                    completion(false, "接口返回空内容")
                case .failure(let error):
                    completion(false, error.message)
                }
            }
        }
    }

    private func buildPrompt(text: String, lineHints: [String]) -> String {
        let hintText = lineHints.prefix(20).joined(separator: "\n")
        return """
        你是票据整理助手。请根据 OCR 文本提取真实存在的信息，输出简洁中文结构化结果。

        要求：
        1. 只保留原文中真实存在的信息，不要脑补。
        2. 优先输出：票据类型、商家/医院、姓名、日期、金额、分类、关键项目。
        3. 如果是医疗票据，补充科室、诊断、检验项目。
        4. 每行一个字段，格式为“字段名: 值”。
        5. 没有把握的字段不要输出。

        OCR 原文：
        \(text)

        行布局参考：
        \(hintText)
        """
    }

    private func sendChat(
        prompt: String,
        systemPrompt: String,
        isConnectivityTest: Bool = false,
        profile: CloudModelProfile? = nil,
        completion: @escaping (Result<String, ServiceError>) -> Void
    ) {
        let profile = profile ?? ModelManager.shared.activeCloudProfile
        guard let profile, let request = buildRequest(
            prompt: prompt,
            systemPrompt: systemPrompt,
            profile: profile,
            useLowercasedModelID: false,
            isConnectivityTest: isConnectivityTest
        ) else {
            completion(.failure(ServiceError(message: "URL 无效，请检查 API 地址")))
            return
        }

        execute(
            request: request,
            profile: profile,
            prompt: prompt,
            systemPrompt: systemPrompt,
            isConnectivityTest: isConnectivityTest,
            hasRetried: false,
            completion: completion
        )
    }

    private func execute(
        request: URLRequest,
        profile: CloudModelProfile,
        prompt: String,
        systemPrompt: String,
        isConnectivityTest: Bool,
        hasRetried: Bool,
        completion: @escaping (Result<String, ServiceError>) -> Void
    ) {
        URLSession.shared.dataTask(with: request) { [self] data, response, error in
            if let error {
                completion(.failure(ServiceError(message: Self.describe(error: error))))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(ServiceError(message: "没有拿到服务端响应")))
                return
            }

            guard let data else {
                completion(.failure(ServiceError(message: "响应数据为空")))
                return
            }

            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                let detail = Self.extractErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)

                if !hasRetried,
                   Self.shouldRetryForXiaomi(profile: profile, statusCode: httpResponse.statusCode, detail: detail),
                   let retryRequest = self.buildRequest(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    profile: profile,
                    useLowercasedModelID: true,
                    isConnectivityTest: isConnectivityTest
                   ) {
                    self.execute(
                        request: retryRequest,
                        profile: profile,
                        prompt: prompt,
                        systemPrompt: systemPrompt,
                        isConnectivityTest: isConnectivityTest,
                        hasRetried: true,
                        completion: completion
                    )
                    return
                }

                completion(.failure(ServiceError(message: "HTTP \(httpResponse.statusCode): \(detail)")))
                return
            }

            if isConnectivityTest {
                completion(.success("OK"))
                return
            }

            guard let content = Self.extractContent(from: data, apiProtocol: profile.apiProtocol), !content.isEmpty else {
                let fallback = String(data: data, encoding: .utf8)?.prefix(160) ?? ""
                completion(.failure(ServiceError(message: "无法解析返回内容\(fallback.isEmpty ? "" : "：\(fallback)")")))
                return
            }

            completion(.success(content))
        }.resume()
    }

    private func buildRequest(
        prompt: String,
        systemPrompt: String,
        profile: CloudModelProfile,
        useLowercasedModelID: Bool,
        isConnectivityTest: Bool
    ) -> URLRequest? {
        guard let url = URL(string: normalizedEndpoint(from: profile.trimmedBaseURL, protocolType: profile.apiProtocol)) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        switch profile.apiProtocol {
        case .openAICompatible:
            request.setValue("Bearer \(profile.trimmedAPIKey)", forHTTPHeaderField: "Authorization")
            let messages: [OpenAIChatRequest.Message] = isConnectivityTest
                ? [.init(role: "user", content: prompt)]
                : [
                    .init(role: "system", content: systemPrompt),
                    .init(role: "user", content: prompt)
                ]
            let body = OpenAIChatRequest(
                model: useLowercasedModelID ? profile.trimmedModelID.lowercased() : profile.trimmedModelID,
                messages: messages,
                temperature: 0.2,
                max_tokens: isConnectivityTest ? 16 : nil
            )
            request.httpBody = try? JSONEncoder().encode(body)

        case .anthropicCompatible:
            request.setValue(profile.trimmedAPIKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let body = AnthropicMessageRequest(
                model: profile.trimmedModelID,
                system: systemPrompt,
                messages: [.init(role: "user", content: prompt)],
                max_tokens: 800
            )
            request.httpBody = try? JSONEncoder().encode(body)
        }

        return request
    }

    private func normalizedEndpoint(from value: String, protocolType: CloudAPIProtocol) -> String {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = raw.contains("://") ? raw : "https://\(raw)"

        switch protocolType {
        case .openAICompatible:
            if trimmed.hasSuffix("/chat/completions") || trimmed.hasSuffix("/v1/chat/completions") {
                return trimmed
            }
            if trimmed.hasSuffix("/v1") {
                return "\(trimmed)/chat/completions"
            }
            return "\(trimmed)/v1/chat/completions"

        case .anthropicCompatible:
            if trimmed.hasSuffix("/messages") || trimmed.hasSuffix("/v1/messages") {
                return trimmed
            }
            if trimmed.hasSuffix("/v1") {
                return "\(trimmed)/messages"
            }
            return "\(trimmed)/v1/messages"
        }
    }

    private static func extractContent(from data: Data, apiProtocol: CloudAPIProtocol) -> String? {
        switch apiProtocol {
        case .openAICompatible:
            if let decoded = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data),
               let message = decoded.choices.first?.message {
                let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !content.isEmpty {
                    return content
                }

                let reasoning = message.reasoning_content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !reasoning.isEmpty {
                    return reasoning
                }
            }

            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = object["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any] else {
                return nil
            }

            if let content = message["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let contentItems = message["content"] as? [[String: Any]] {
                let text = contentItems.compactMap { $0["text"] as? String }.joined()
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

            return nil

        case .anthropicCompatible:
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let contents = object["content"] as? [[String: Any]] else {
                return nil
            }

            let text = contents.compactMap { $0["text"] as? String }.joined(separator: "\n")
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any] {
                if let message = error["message"] as? String {
                    return message
                }
                if let type = error["type"] as? String {
                    return type
                }
            }

            if let message = object["message"] as? String {
                return message
            }

            if let detail = object["detail"] as? String {
                return detail
            }
        }

        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func describe(error: Error) -> String {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorAppTransportSecurityRequiresSecureConnection:
                return "iOS 拒绝了非 HTTPS 请求，请改用 HTTPS 或允许 HTTP"
            case NSURLErrorTimedOut:
                return "请求超时"
            case NSURLErrorCannotFindHost:
                return "找不到服务器"
            case NSURLErrorCannotConnectToHost:
                return "无法连接到服务器"
            case NSURLErrorSecureConnectionFailed:
                return "TLS 握手失败"
            case NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot:
                return "证书不受信任"
            default:
                break
            }
        }

        return nsError.localizedDescription
    }

    private static func shouldRetryForXiaomi(profile: CloudModelProfile, statusCode: Int, detail: String) -> Bool {
        let host = URL(string: profile.trimmedBaseURL)?.host?.lowercased() ?? ""
        guard host.contains("xiaomimimo.com"), statusCode == 400 else { return false }
        return detail.localizedCaseInsensitiveContains("not supported model")
    }
}
