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
            if code == 429 { return "Слишком много запросов (429)" }
            return "HTTP \(code)"
        case .network(let msg):
            return "Сеть: \(msg)"
        case .decode(let msg):
            return "Ошибка разбора ответа: \(msg)"
        }
    }

    /// Transient errors (rate limit / server / network) don't invalidate the
    /// last successful reading — we keep showing it, marked stale, and recover
    /// on the next poll. Actionable errors (`noToken`/`unauthorized`) must stay
    /// prominent so the user knows to reopen Claude Code.
    var isTransient: Bool {
        switch self {
        case .http(let code):
            return code == 429 || (500...599).contains(code)
        case .network:
            return true
        case .noToken, .unauthorized, .decode:
            return false
        }
    }
}

/// Fetches usage from the (undocumented) OAuth usage endpoint.
final class UsageClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Number of extra attempts on a transient failure (network/proxy/5xx/429).
    /// Corporate proxies drop the CONNECT tunnel intermittently (CFNetwork 310);
    /// a quick retry usually succeeds, so a single blip never reaches the UI.
    private static let maxRetries = 2
    private static let retryDelay: TimeInterval = 1.5

    func fetch(completion: @escaping (Result<[Limit], UsageError>) -> Void) {
        attempt(retriesLeft: Self.maxRetries, completion: completion)
    }

    private func attempt(retriesLeft: Int, completion: @escaping (Result<[Limit], UsageError>) -> Void) {
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

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            defer { session.finishTasksAndInvalidate() }   // release the delegate
            let deliver: (Result<[Limit], UsageError>) -> Void = { result in
                // Retry transient failures (proxy/network/5xx/429) before surfacing.
                if case .failure(let err) = result, err.isTransient, retriesLeft > 0, let self = self {
                    DispatchQueue.global().asyncAfter(deadline: .now() + Self.retryDelay) {
                        self.attempt(retriesLeft: retriesLeft - 1, completion: completion)
                    }
                    return
                }
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
