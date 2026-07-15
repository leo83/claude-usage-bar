import Foundation

enum UsageError: Error, LocalizedError {
    case noToken
    case unauthorized
    case http(Int)
    case network(String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "Токен Claude Code не найден в Keychain"
        case .unauthorized:
            return "Токен истёк или недействителен (401). Откройте Claude Code, чтобы обновить сессию."
        case .http(let code):
            return "HTTP \(code)"
        case .network(let msg):
            return "Сеть: \(msg)"
        case .decode(let msg):
            return "Ошибка разбора ответа: \(msg)"
        }
    }
}

/// Fetches usage from the (undocumented) OAuth usage endpoint.
final class UsageClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    func fetch(completion: @escaping (Result<[Limit], UsageError>) -> Void) {
        guard let token = Credentials.accessToken() else {
            completion(.failure(.noToken))
            return
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let proxy = Settings.activeProxy
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        if let proxy = proxy {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: proxy.host,
                kCFNetworkProxiesHTTPPort as String: proxy.port,
                // HTTPS proxy keys (string literals — CFNetwork constants for
                // HTTPS are unavailable on some SDKs). Our endpoint is https,
                // so the connection is tunneled via CONNECT through this proxy.
                "HTTPSEnable": true,
                "HTTPSProxy": proxy.host,
                "HTTPSPort": proxy.port,
            ]
        }

        // A delegate answers the proxy's 407 auth challenge with credentials.
        let delegate = ProxyAuthDelegate(username: proxy?.username, password: proxy?.password)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        let task = session.dataTask(with: request) { data, response, error in
            defer { session.finishTasksAndInvalidate() }   // release the delegate
            let deliver: (Result<[Limit], UsageError>) -> Void = { result in
                DispatchQueue.main.async { completion(result) }
            }

            if let error = error {
                deliver(.failure(.network(error.localizedDescription)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                deliver(.failure(.network("нет ответа")))
                return
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                deliver(.failure(.unauthorized))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                deliver(.failure(.http(http.statusCode)))
                return
            }
            guard let data = data else {
                deliver(.failure(.decode("пустое тело")))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
                deliver(.success(decoded.limits))
            } catch {
                deliver(.failure(.decode(error.localizedDescription)))
            }
        }
        task.resume()
    }
}

/// Supplies proxy credentials in response to a 407 challenge, while letting
/// server TLS trust and all non-proxy challenges fall through to the default.
private final class ProxyAuthDelegate: NSObject, URLSessionTaskDelegate {
    let username: String?
    let password: String?

    init(username: String?, password: String?) {
        self.username = username
        self.password = password
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod
        let proxyMethods = [
            NSURLAuthenticationMethodHTTPBasic,
            NSURLAuthenticationMethodHTTPDigest,
            NSURLAuthenticationMethodNTLM,
        ]
        if proxyMethods.contains(method),
           challenge.previousFailureCount == 0,
           let username, let password {
            let credential = URLCredential(user: username, password: password, persistence: .forSession)
            completionHandler(.useCredential, credential)
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
