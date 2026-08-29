import Foundation
import Security

/// Google Cloud OCR for prescription photos/PDFs. Text only — then `PrescriptionParser` + catalog.
/// Never reuse `GOOGLE_IOS_CLIENT_ID` / iOS OAuth client secret as a Vision or Document AI key.
enum GoogleCloudOCR {
    static func visionAPIKey() -> String? {
        SecretPlist.nonEmpty("GOOGLE_CLOUD_VISION_API_KEY")
    }

    static func documentAIConfig() -> DocumentAIConfig? {
        guard let project = SecretPlist.nonEmpty("GOOGLE_CLOUD_PROJECT_ID"),
              let processor = SecretPlist.nonEmpty("GOOGLE_DOCUMENT_AI_PROCESSOR_ID")
        else { return nil }
        let location = SecretPlist.nonEmpty("GOOGLE_DOCUMENT_AI_LOCATION") ?? "us"
        let credentials = GoogleServiceAccountAuth.credentialsData()
        let apiKey = SecretPlist.nonEmpty("GOOGLE_DOCUMENT_AI_API_KEY") ?? visionAPIKey()
        guard credentials != nil || apiKey != nil else { return nil }
        return DocumentAIConfig(
            project: project,
            location: location,
            processor: processor,
            credentialsJSON: credentials,
            apiKey: apiKey
        )
    }

    struct DocumentAIConfig: Sendable {
        var project: String
        var location: String
        var processor: String
        var credentialsJSON: Data?
        var apiKey: String?
    }

    static func documentAIText(data: Data, mimeType: String) async -> String? {
        guard let config = documentAIConfig() else { return nil }
        let encoded = data.base64EncodedString()
        let body: [String: Any] = [
            "rawDocument": [
                "content": encoded,
                "mimeType": mimeType,
            ],
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        let path = "https://\(config.location)-documentai.googleapis.com/v1/projects/\(config.project)/locations/\(config.location)/processors/\(config.processor):process"
        if let json = config.credentialsJSON,
           let token = await GoogleServiceAccountAuth.accessToken(from: json) {
            if let text = await processDocumentAI(urlString: path, payload: payload, bearer: token, apiKey: nil) {
                return text
            }
        }
        if let key = config.apiKey {
            return await processDocumentAI(urlString: path, payload: payload, bearer: nil, apiKey: key)
        }
        return nil
    }

    static func visionDocumentText(jpeg: Data, apiKey: String) async -> String? {
        if let text = await visionAnnotate(jpeg: jpeg, apiKey: apiKey, types: ["DOCUMENT_TEXT_DETECTION"]) {
            return text
        }
        return await visionAnnotate(jpeg: jpeg, apiKey: apiKey, types: ["TEXT_DETECTION"])
    }

    private static func processDocumentAI(
        urlString: String,
        payload: Data,
        bearer: String?,
        apiKey: String?
    ) async -> String? {
        var raw = urlString
        if let apiKey, bearer == nil {
            let encoded = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
            raw += "?key=\(encoded)"
        }
        guard let url = URL(string: raw) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        request.timeoutInterval = 45
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let document = json["document"] as? [String: Any],
           let text = document["text"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func visionAnnotate(jpeg: Data, apiKey: String, types: [String]) async -> String? {
        guard let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://vision.googleapis.com/v1/images:annotate?key=\(encodedKey)") else {
            return nil
        }
        let features = types.map { ["type": $0] }
        let body: [String: Any] = [
            "requests": [[
                "image": ["content": jpeg.base64EncodedString()],
                "features": features,
            ]],
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        request.timeoutInterval = 25
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responses = json["responses"] as? [[String: Any]],
              let first = responses.first
        else { return nil }
        if let annotation = first["fullTextAnnotation"] as? [String: Any],
           let text = annotation["text"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let annotations = first["textAnnotations"] as? [[String: Any]],
           let text = annotations.first?["description"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}

enum SecretPlist {
    static func nonEmpty(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.contains("$(") { return nil }
        if trimmed == "YOUR_KEY" { return nil }
        return trimmed
    }
}

/// Service-account JWT → access token. JSON is gitignored; never commit it.
enum GoogleServiceAccountAuth {
    static func credentialsData() -> Data? {
        if let env = ProcessInfo.processInfo.environment["GOOGLE_APPLICATION_CREDENTIALS"],
           let data = readFile(env) {
            return data
        }
        if let path = SecretPlist.nonEmpty("GOOGLE_DOCUMENT_AI_CREDENTIALS_PATH"),
           let data = readFile(path) {
            return data
        }
        if let url = Bundle.main.url(forResource: "GoogleDocumentAI", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            return data
        }
        let fallbacks = [
            "GoogleDocumentAI.json",
            "ChekMed/GoogleDocumentAI.json",
        ]
        for relative in fallbacks {
            if let data = readFile(relative) { return data }
        }
        return nil
    }

    static func accessToken(from json: Data) async -> String? {
        await GoogleAccessTokenCache.shared.token(for: json)
    }

    private static func readFile(_ path: String) -> Data? {
        let expanded = (path as NSString).expandingTildeInPath
        if let data = try? Data(contentsOf: URL(fileURLWithPath: expanded)), !data.isEmpty {
            return data
        }
        return nil
    }

    static func mintAccessToken(from json: Data) async -> (token: String, expiry: Date)? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let email = object["client_email"] as? String,
              var pem = object["private_key"] as? String
        else { return nil }
        pem = pem.replacingOccurrences(of: "\\n", with: "\n")
        let now = Int(Date().timeIntervalSince1970)
        let header = #"{"alg":"RS256","typ":"JWT"}"#
        let claimsDict: [String: Any] = [
            "iss": email,
            "scope": "https://www.googleapis.com/auth/cloud-platform",
            "aud": "https://oauth2.googleapis.com/token",
            "iat": now,
            "exp": now + 3600,
        ]
        guard let claimsData = try? JSONSerialization.data(withJSONObject: claimsDict),
              let claims = String(data: claimsData, encoding: .utf8)
        else { return nil }
        let signingInput = base64URL(header) + "." + base64URL(claims)
        guard let signature = rsaSHA256(signingInput, pem: pem) else { return nil }
        let assertion = signingInput + "." + base64URL(signature)
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:jwt-bearer"),
            URLQueryItem(name: "assertion", value: assertion),
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = body["access_token"] as? String
        else { return nil }
        let seconds = (body["expires_in"] as? Int) ?? 3600
        return (token, Date().addingTimeInterval(TimeInterval(max(60, seconds - 60))))
    }

    private static func base64URL(_ string: String) -> String {
        base64URL(Data(string.utf8))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func rsaSHA256(_ message: String, pem: String) -> Data? {
        guard let key = privateKey(fromPEM: pem),
              let messageData = message.data(using: .utf8)
        else { return nil }
        let algorithm = SecKeyAlgorithm.rsaSignatureMessagePKCS1v15SHA256
        guard SecKeyIsAlgorithmSupported(key, .sign, algorithm) else { return nil }
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, algorithm, messageData as CFData, &error) as Data? else {
            return nil
        }
        return signature
    }

    private static func privateKey(fromPEM pem: String) -> SecKey? {
        let stripped = pem
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard let der = Data(base64Encoded: stripped) else { return nil }
        if let key = secKey(fromDER: der) { return key }
        if let pkcs1 = pkcs1(fromPKCS8: der) {
            return secKey(fromDER: pkcs1)
        }
        return nil
    }

    private static func secKey(fromDER der: Data) -> SecKey? {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        return SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error)
    }

    private static func pkcs1(fromPKCS8 der: Data) -> Data? {
        var index = 0
        guard der.count > 8, der[index] == 0x30 else { return nil }
        index += 1
        guard readLength(der, &index) != nil, index < der.count, der[index] == 0x02 else { return nil }
        index += 1
        guard let versionLen = readLength(der, &index) else { return nil }
        index += versionLen
        guard index < der.count, der[index] == 0x30 else { return nil }
        index += 1
        guard let algLen = readLength(der, &index) else { return nil }
        index += algLen
        guard index < der.count, der[index] == 0x04 else { return nil }
        index += 1
        guard let octLen = readLength(der, &index), index + octLen <= der.count else { return nil }
        return der.subdata(in: index..<(index + octLen))
    }

    private static func readLength(_ data: Data, _ index: inout Int) -> Int? {
        guard index < data.count else { return nil }
        let first = Int(data[index])
        index += 1
        if first & 0x80 == 0 { return first }
        let count = first & 0x7F
        guard count > 0, count <= 4, index + count <= data.count else { return nil }
        var length = 0
        for _ in 0..<count {
            length = (length << 8) | Int(data[index])
            index += 1
        }
        return length
    }
}

actor GoogleAccessTokenCache {
    static let shared = GoogleAccessTokenCache()

    private var token: String?
    private var expiry = Date.distantPast
    private var fingerprint: Int = 0

    func token(for json: Data) async -> String? {
        let hash = json.hashValue
        if hash == fingerprint, let token, expiry > Date() {
            return token
        }
        guard let minted = await GoogleServiceAccountAuth.mintAccessToken(from: json) else {
            return nil
        }
        fingerprint = hash
        token = minted.token
        expiry = minted.expiry
        return minted.token
    }
}
