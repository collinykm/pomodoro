import Foundation
import AppKit
import CryptoKit
import Network
import Security

// MARK: - Models

struct GTaskList: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
}

struct GTask: Identifiable, Decodable, Hashable {
    let id: String
    var title: String
    var status: String
    var due: String?
    var notes: String?

    var isCompleted: Bool { status == "completed" }

    var dueDate: Date? {
        guard let due else { return nil }
        return ISO8601DateFormatter().date(from: due)
    }
}

private struct ListResponse<T: Decodable>: Decodable {
    let items: [T]?
}

private struct TokenResponse: Decodable {
    let access_token: String
    let expires_in: Int
    let refresh_token: String?
}

enum GoogleTasksError: LocalizedError {
    case missingClientID
    case notConnected
    case authFailed(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingClientID: return "Add your Google OAuth client ID in Settings first."
        case .notConnected: return "Not connected to Google Tasks."
        case .authFailed(let why): return "Sign-in failed: \(why)"
        case .http(let code, let body): return "Google returned HTTP \(code). \(body.prefix(160))"
        }
    }
}

// MARK: - Service

/// Google Tasks via OAuth 2.0 "installed app" flow: PKCE + a loopback redirect caught by a
/// tiny local HTTP listener. The user supplies their own client ID (and the client secret
/// Google issues for Desktop clients, which Google documents as not actually secret).
@Observable
@MainActor
final class GoogleTasksService {
    static let shared = GoogleTasksService()

    private(set) var isConnected: Bool
    private(set) var isBusy = false
    private(set) var lists: [GTaskList] = []
    private(set) var tasks: [GTask] = []
    var errorMessage: String?

    private let settings = AppSettings.shared
    private let scope = "https://www.googleapis.com/auth/tasks"
    private let base = URL(string: "https://tasks.googleapis.com/tasks/v1")!

    private init() {
        isConnected = Keychain.get("google.refresh") != nil
    }

    var clientSecret: String {
        get { Keychain.get("google.clientSecret") ?? "" }
        set {
            if newValue.isEmpty { Keychain.delete("google.clientSecret") } else { Keychain.set(newValue, for: "google.clientSecret") }
        }
    }

    // MARK: Connect / disconnect

    func connect() async {
        errorMessage = nil
        let clientID = settings.googleClientID.trimmingCharacters(in: .whitespaces)
        guard !clientID.isEmpty else {
            errorMessage = GoogleTasksError.missingClientID.localizedDescription
            return
        }
        isBusy = true
        defer { isBusy = false }

        do {
            let verifier = PKCE.verifier()
            let challenge = PKCE.challenge(for: verifier)
            let state = PKCE.verifier()

            let listener = try LoopbackListener()
            let port = try await listener.start()
            let redirect = "http://127.0.0.1:\(port)"

            var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            comps.queryItems = [
                .init(name: "client_id", value: clientID),
                .init(name: "redirect_uri", value: redirect),
                .init(name: "response_type", value: "code"),
                .init(name: "scope", value: scope),
                .init(name: "code_challenge", value: challenge),
                .init(name: "code_challenge_method", value: "S256"),
                .init(name: "state", value: state),
                .init(name: "access_type", value: "offline"),
                .init(name: "prompt", value: "consent"),
            ]
            NSWorkspace.shared.open(comps.url!)

            let result = try await listener.waitForCode()
            guard result.state == state else { throw GoogleTasksError.authFailed("state mismatch") }

            var body: [String: String] = [
                "client_id": clientID,
                "code": result.code,
                "code_verifier": verifier,
                "grant_type": "authorization_code",
                "redirect_uri": redirect,
            ]
            if !clientSecret.isEmpty { body["client_secret"] = clientSecret }
            let token = try await requestToken(body)
            store(token)
            isConnected = true
            await refresh()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func disconnect() {
        Keychain.delete("google.access")
        Keychain.delete("google.refresh")
        Keychain.delete("google.expiry")
        isConnected = false
        lists = []
        tasks = []
    }

    // MARK: Data

    func refresh() async {
        guard isConnected else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let listResp: ListResponse<GTaskList> = try await get(base.appending(path: "users/@me/lists"), query: ["maxResults": "100"])
            lists = listResp.items ?? []
            if settings.googleTaskListID.isEmpty || !lists.contains(where: { $0.id == settings.googleTaskListID }) {
                settings.googleTaskListID = lists.first?.id ?? ""
            }
            try await loadTasks()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func selectList(_ id: String) async {
        settings.googleTaskListID = id
        isBusy = true
        defer { isBusy = false }
        do { try await loadTasks() } catch { errorMessage = error.localizedDescription }
    }

    private func loadTasks() async throws {
        guard !settings.googleTaskListID.isEmpty else { tasks = []; return }
        let resp: ListResponse<GTask> = try await get(
            base.appending(path: "lists/\(settings.googleTaskListID)/tasks"),
            query: ["showCompleted": "false", "showHidden": "false", "maxResults": "100"]
        )
        tasks = (resp.items ?? [])
            .filter { !$0.title.isEmpty }
            .sorted { a, b in
                switch (a.dueDate, b.dueDate) {
                case let (x?, y?): return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.title < b.title
                }
            }
    }

    func complete(_ task: GTask) async {
        tasks.removeAll { $0.id == task.id }
        do {
            let url = base.appending(path: "lists/\(settings.googleTaskListID)/tasks/\(task.id)")
            _ = try await send("PATCH", url, json: ["status": "completed"])
        } catch {
            errorMessage = error.localizedDescription
            try? await loadTasks()
        }
    }

    func add(title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !settings.googleTaskListID.isEmpty else { return }
        do {
            let url = base.appending(path: "lists/\(settings.googleTaskListID)/tasks")
            _ = try await send("POST", url, json: ["title": trimmed])
            try await loadTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: HTTP plumbing

    private func validAccessToken() async throws -> String {
        if let access = Keychain.get("google.access"),
           let expiryString = Keychain.get("google.expiry"),
           let expiry = TimeInterval(expiryString),
           Date().timeIntervalSince1970 < expiry - 60 {
            return access
        }
        guard let refreshToken = Keychain.get("google.refresh") else { throw GoogleTasksError.notConnected }
        var body: [String: String] = [
            "client_id": settings.googleClientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        if !clientSecret.isEmpty { body["client_secret"] = clientSecret }
        let token = try await requestToken(body)
        store(token)
        return token.access_token
    }

    private func store(_ token: TokenResponse) {
        Keychain.set(token.access_token, for: "google.access")
        Keychain.set(String(Date().timeIntervalSince1970 + Double(token.expires_in)), for: "google.expiry")
        if let refresh = token.refresh_token { Keychain.set(refresh, for: "google.refresh") }
    }

    private func requestToken(_ form: [String: String]) async throws -> TokenResponse {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw GoogleTasksError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func get<T: Decodable>(_ url: URL, query: [String: String]) async throws -> T {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        let data = try await send("GET", comps.url!, json: nil)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    private func send(_ method: String, _ url: URL, json: [String: Any]?) async throws -> Data {
        let token = try await validAccessToken()
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 {
            Keychain.delete("google.access")
            throw GoogleTasksError.http(code, "Token rejected; try again.")
        }
        guard (200..<300).contains(code) else {
            throw GoogleTasksError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}

// MARK: - PKCE

enum PKCE {
    static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URL()
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URL()
    }
}

private extension Data {
    func base64URL() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Loopback redirect listener

/// Listens on 127.0.0.1 for the single OAuth redirect, replies with a tiny page, and hands
/// back the authorization code.
final class LoopbackListener: @unchecked Sendable {
    struct Result { let code: String; let state: String }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "lockin.oauth.loopback")
    private var continuation: CheckedContinuation<Result, Error>?
    private var connections: [NWConnection] = []

    init() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
    }

    /// Starts listening and resolves with the chosen port.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            var resumed = false
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if !resumed, let port = self.listener.port?.rawValue {
                        resumed = true
                        cont.resume(returning: port)
                    }
                case .failed(let error):
                    if !resumed { resumed = true; cont.resume(throwing: error) }
                    self.finish(.failure(error))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        }
    }

    func waitForCode() async throws -> Result {
        try await withCheckedThrowingContinuation { cont in
            queue.async { self.continuation = cont }
        }
    }

    private func handle(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
            let firstLine = request.split(separator: "\r\n").first.map(String.init) ?? ""
            let parts = firstLine.split(separator: " ")
            var outcome: Swift.Result<Result, Error>?
            if parts.count >= 2, let comps = URLComponents(string: "http://127.0.0.1\(parts[1])") {
                let items = comps.queryItems ?? []
                if let code = items.first(where: { $0.name == "code" })?.value {
                    let state = items.first(where: { $0.name == "state" })?.value ?? ""
                    outcome = .success(Result(code: code, state: state))
                } else if let err = items.first(where: { $0.name == "error" })?.value {
                    outcome = .failure(GoogleTasksError.authFailed(err))
                }
            }
            let ok: Bool = { if case .success? = outcome { return true } else { return false } }()
            let html = """
            <!doctype html><html><head><meta charset="utf-8"><title>LockIn</title></head>
            <body style="font-family:-apple-system,Helvetica,sans-serif;background:#FFFBF0;display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
            <div style="border:4px solid #111;box-shadow:8px 8px 0 #111;background:\(ok ? "#FFD93D" : "#FF6B6B");padding:32px 40px;max-width:420px">
            <h1 style="margin:0 0 8px;font-weight:900;letter-spacing:-1px">\(ok ? "LOCKED IN." : "SOMETHING BROKE.")</h1>
            <p style="margin:0;font-weight:600">\(ok ? "Google Tasks is connected. You can close this tab and go back to LockIn." : "Sign-in did not complete. Head back to LockIn and try again.")</p>
            </div></body></html>
            """
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
                if let outcome { self.finish(outcome) }
            })
        }
    }

    private func finish(_ outcome: Swift.Result<Result, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        listener.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
        cont.resume(with: outcome)
    }
}
