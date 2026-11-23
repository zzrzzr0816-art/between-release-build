import Foundation
import Combine
import Security
import SwiftUI
import AuthenticationServices

// MARK: - Backend contract (client side of the agreement)
//
// All endpoints live under https://minglimaster.com/between/api
//
// POST /auth/apple
//   { "identity_token": "...", "authorization_code": "..." }
//   200 { "token": "...", "user": { "id": "A7K2M9", "nickname": "晚风4821" } }
//   Server assigns a random unique nickname on registration. If it returns null,
//   the client generates one and PATCHes it, so setup is never blocking.
//
// GET /me                       Authorization: Bearer <token>
//   -> { "user": { "id": "A7K2M9", "nickname": "晚风" } }
//
// PATCH /me                     { "nickname": "晚风" }
//   200 { "user": { ... } } | 409 { "error": "nickname_taken" }
//
// DELETE /me                    -> 204
//
// Guests carry no token and may only call read endpoints.

enum BetweenAPI {
    static var base: String {
        ProcessInfo.processInfo.environment["BETWEEN_API_BASE"] ?? "https://minglimaster.com/between/api"
    }
}

struct BetweenAccount: Codable, Equatable {
    let id: String
    var nickname: String?
    var public_id: String? = nil
}

struct AuthUserPayload: Decodable {
    let id: String
    let nickname: String?
    let public_id: String?
}

struct AuthResponse: Decodable {
    let token: String
    let user: AuthUserPayload
}

private struct AuthUserEnvelope: Decodable { let user: AuthUserPayload }

struct SupportTicket: Decodable, Identifiable {
    let id: String
    let message: String
    let reply: String?
    let closed: Int?
}

enum NicknameRule {
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCompatibilityMapping
    }

    static func random(zh: Bool) -> String {
        let zhWords = ["晚风", "微光", "旅人", "小岛", "回声", "月亮", "纸船", "星尘"]
        let enWords = ["Drift", "Echo", "Lantern", "Harbor", "Moth", "Dawn", "Pebble", "Comet"]
        let word = (zh ? zhWords : enWords).randomElement() ?? "Drift"
        return word + String(format: "%04d", Int.random(in: 1000...9999))
    }

    static func validate(_ raw: String, zh: Bool) -> String? {
        let name = normalize(raw)
        if name.count < 2 { return zh ? "昵称至少需要 2 个字符" : "Use at least 2 characters" }
        if name.count > 16 { return zh ? "昵称最多 16 个字符" : "Use at most 16 characters" }
        let contactHints = "微信|微訊|微讯|薇信|威信|加微|加我|扣扣|企鹅号|手机号|电话|电郵|电邮|邮箱|联系|聯絡|聯繫|账号|帳號|私信|私聊|二维码|二維碼|小红书|小紅書|抖音|qq|wechat|weixin|vx|wx|whatsapp|telegram|discord|instagram|tiktok|gmail|outlook|hotmail|yahoo|email|snapchat|facebook|https?|www|dotcom|[零〇一二三四五六七八九十幺壹贰叁肆伍陆柒捌玖]{4,}"
        if name.range(of: "^[A-Za-z一-鿿]{2,16}$", options: .regularExpression) == nil
            || name.range(of: contactHints, options: [.caseInsensitive, .regularExpression]) != nil {
            return zh ? "昵称仅支持中文汉字和英文字母，不能包含联系方式或引导联系的内容"
                      : "Use Chinese or English letters only. Contact details and contact invitations are not allowed."
        }
        return nil
    }
}

private enum KeychainStore {
    static let service = "com.dukaili.halohorn.account"

    static func verifyDevicePasscode(reason: String) -> OSStatus {
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .devicePasscode, nil
        ) else { return errSecAuthFailed }

        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service + ".deletion",
            kSecAttrAccount as String: UUID().uuidString
        ]
        var add = item
        add[kSecAttrAccessControl as String] = access
        add[kSecValueData as String] = Data([0])
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { return status }
        defer { SecItemDelete(item as CFDictionary) }

        var query = item
        query[kSecReturnData as String] = true
        query[kSecUseOperationPrompt as String] = reason
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result)
    }

    static func set(_ value: String, for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let data = Data(value.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var account: BetweenAccount?
    @Published var busy = false
    @Published var errorText: String?

    private let tokenKey = "session.token"
    private let cacheKey = "between.account.v1"
    private var checkingSession = false

    var isPreview: Bool { BetweenPreviewMode.enabled }

    var localStorageKey: String {
        let namespace = isPreview ? "native.preview.v2." : "native.local.v2."
        return namespace + (account?.id ?? "guest")
    }

    func usePreviewAccount() {
        guard isPreview else { return }
        errorText = nil
        account = BetweenAccount(id: "A7K2M9", nickname: "AD-9FX2", public_id: "5102793")
    }

    var isGuest: Bool { account == nil }
    var isReady: Bool { account != nil }
    var accountAccessEnabled: Bool {
        if let configured = Bundle.main.object(forInfoDictionaryKey:"BetweenAccountAccessEnabled") as? Bool {
            return configured
        }
        return Bundle.main.bundleIdentifier == "com.dukaili.halohorn"
    }
    func discussionToken(for viewer: String) -> String? {
        guard accountAccessEnabled, !isPreview, account?.id == viewer else { return nil }
        return KeychainStore.get(tokenKey)
    }
    var displayName: String { account?.nickname ?? "" }
    var userId: String? { account?.id }

    private var zh: Bool {
        if let language = UserDefaults.standard.string(forKey:"native.language") { return language == "zh" }
        return ProcessInfo.processInfo.arguments.contains("-ui-zh")
    }
    private func t(_ a: String, _ b: String) -> String { zh ? a : b }

    init() {
        if isPreview {
            let args = ProcessInfo.processInfo.arguments
            account = args.contains("-ui-guest") ? nil : BetweenAccount(id: "A7K2M9", nickname: "AD-9FX2", public_id: "5102793")
            return
        }
        if KeychainStore.get(tokenKey) != nil, let cached = loadCachedAccount() {
            var restored = cached
            if restored.nickname?.isEmpty ?? true { restored.nickname = NicknameRule.random(zh: zh) }
            account = restored
        }
    }

    // MARK: Session bootstrap

    func bootstrap() async {
        guard !isPreview, !busy, !checkingSession, let token = KeychainStore.get(tokenKey) else { return }
        checkingSession = true
        defer { checkingSession = false }
        do {
            let fresh = try await fetchMe(token)
            guard !busy, KeychainStore.get(tokenKey) == token else { return }
            persist(fresh)
        } catch AuthFailure.unauthorized {
            if !busy, KeychainStore.get(tokenKey) == token { clearSession() }
        } catch {
            // Keep the cached account while connectivity is unavailable.
        }
    }

    // MARK: Apple sign-in

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        guard !isPreview, !busy else { return }
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityData = credential.identityToken,
                  let identityToken = String(data: identityData, encoding: .utf8) else {
                errorText = t("无法读取 Apple 登录凭证，请稍后再试", "Could not read the Apple credential. Try again.")
                return
            }
            let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            Task { await exchange(identityToken: identityToken, authorizationCode: code) }
        case .failure(let error):
            if let appleError = error as? ASAuthorizationError, appleError.code == .canceled { return }
            errorText = t("登录没有完成，请稍后再试", "Sign in didn’t finish. Try again.")
        }
    }

    private func exchange(identityToken: String, authorizationCode: String) async {
        await exchangeCredentials(
            route: "auth/apple",
            fields: ["identity_token": identityToken, "authorization_code": authorizationCode]
        )
    }

    func signInWithPassword(username: String, password: String, register: Bool, email: String = "", code: String = "") async -> Bool {
        guard !isPreview, !busy else { return false }
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let route = register ? "auth/register" : (name == "halohorn-review" ? "auth/review" : "auth/password")
        var fields = ["username": name, "password": password]
        if register {
            fields["email"] = email
            fields["code"] = code
        }
        await exchangeCredentials(route: route, fields: fields)
        return account != nil
    }

    func sendRegistrationCode(to email: String) async -> Bool {
        guard !busy else { return false }
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            var request = try authRequest("auth/email-code")
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["email": email])
            let (_, response) = try await URLSession.shared.data(for: request)
            try validate(response, allowing: [200])
            return true
        } catch {
            errorText = t("无法发送验证码，请检查邮箱或稍后重试", "Could not send a code. Check the email or try again later.")
            return false
        }
    }

    private func exchangeCredentials(route: String, fields: [String: String]) async {
        guard !busy else { return }
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            var request = try authRequest(route)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(fields)
            let (data, response) = try await URLSession.shared.data(for: request)
            if route == "auth/register", let status = (response as? HTTPURLResponse)?.statusCode {
                if status == 409 {
                    errorText = t("账号已被使用", "That username is taken.")
                    return
                }
                if status == 400 {
                    errorText = t("请检查账号和密码格式", "Check the username and password format.")
                    return
                }
            }
            try validate(response, allowing:[200])
            let payload = try JSONDecoder().decode(AuthResponse.self, from: data)
            guard !payload.token.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
                  !payload.user.id.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw AuthFailure.server }
            guard KeychainStore.set(payload.token, for: tokenKey) else {
                errorText = t("无法安全保存登录凭证，请解锁设备后重试", "Couldn’t securely save your sign-in. Unlock your device and try again.")
                return
            }
            persist(BetweenAccount(id: payload.user.id, nickname: payload.user.nickname, public_id: payload.user.public_id))
        } catch AuthFailure.unavailable {
            errorText = t("登录服务暂不可用，请稍后重试", "Sign-in is temporarily unavailable. Try again later.")
        } catch {
            errorText = t("登录失败，请检查网络后重试", "Sign in failed. Check your connection and try again.")
        }
    }

    // MARK: Nickname

    /// Returns an error message when the nickname cannot be used.
    func submitNickname(_ raw: String) async -> String? {
        guard !busy else { return t("请稍候再试", "Try again in a moment") }
        let name = NicknameRule.normalize(raw)
        guard let current = account else {
            return t("请先通过 Apple 登录", "Sign in with Apple first")
        }
        if current.nickname == name { return nil }
        if let message = NicknameRule.validate(name, zh: zh) { return message }
        busy = true
        errorText = nil
        defer { busy = false }
        if isPreview {
            if ["admin", "管理员", "angel", "devil"].contains(name.lowercased()) {
                return t("这个昵称已被占用", "That nickname is taken")
            }
            var updated = current
            updated.nickname = name
            persist(updated)
            return nil
        }
        guard let token = KeychainStore.get(tokenKey) else {
            return t("登录已过期，请重新登录", "Your session expired. Sign in again.")
        }
        do {
            let updated = try await patchNickname(name, token: token)
            guard KeychainStore.get(tokenKey) == token else { return t("登录已过期，请重新登录", "Your session expired. Sign in again.") }
            persist(updated)
            return nil
        } catch AuthFailure.unauthorized {
            if KeychainStore.get(tokenKey) == token { clearSession() }
            return t("登录已过期，请重新登录", "Your session expired. Sign in again.")
        } catch AuthFailure.nicknameTaken {
            return t("这个昵称已被占用，换一个试试", "That nickname is taken. Try another.")
        } catch {
            return t("保存昵称失败，请稍后再试", "Could not save the nickname. Try again.")
        }
    }

    // MARK: Sign out / delete

    func signOut() async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        if !isPreview, let token = KeychainStore.get(tokenKey) {
            do {
                var request = try authRequest("auth/logout")
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField:"Content-Type")
                request.setValue("Bearer \(token)", forHTTPHeaderField:"Authorization")
                request.httpBody = Data("{}".utf8)
                let (_,response) = try await URLSession.shared.data(for:request)
                try validate(response,allowing:[200])
            } catch {
                errorText = t("未能注销服务器会话，请检查网络后重试。","Could not revoke your session. Check your connection and try again.")
                return false
            }
        }
        guard isPreview || KeychainStore.remove(tokenKey) else {
            errorText = t("退出登录失败，请解锁设备后重试", "Couldn’t sign out. Unlock your device and try again.")
            return false
        }
        clearCachedAccount()
        errorText = nil
        return true
    }

    func deleteAccount() async -> Bool {
        guard !busy, account != nil else { return false }
        busy = true
        errorText = nil
        defer { busy = false }
        if !isPreview {
            let reason = t("输入 iPhone 锁屏密码以删除 HaloHorn 账号", "Enter your iPhone passcode to delete your HaloHorn account")
            let status = await Task.detached {
                KeychainStore.verifyDevicePasscode(reason: reason)
            }.value
            guard status == errSecSuccess else {
                if status != errSecUserCanceled {
                    errorText = t("锁屏密码验证未完成。请确认已设置 iPhone 锁屏密码，再重试。", "Passcode verification did not finish. Make sure your iPhone has a passcode and try again.")
                }
                return false
            }
            guard let token = KeychainStore.get(tokenKey) else {
                errorText = t("登录已过期，请重新登录", "Your session expired. Sign in again.")
                return false
            }
            do {
                var request = try authRequest("me")
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (_, response) = try await URLSession.shared.data(for: request)
                try validate(response,allowing:[200,204])
            } catch AuthFailure.unauthorized {
                clearSession()
                errorText = t("登录已过期，请重新登录后删除账号", "Your session expired. Sign in again to delete the account.")
                return false
            } catch {
                errorText = t("删除账号失败，请稍后再试", "Could not delete the account. Try again.")
                return false
            }
        }
        clearSession()
        return true
    }

    // MARK: Helpers

    func supportTickets(message: String? = nil) async throws -> [SupportTicket] {
        struct TicketList: Decodable { let tickets: [SupportTicket] }
        guard !isPreview, account != nil, let token = KeychainStore.get(tokenKey) else {
            throw AuthFailure.unauthorized
        }
        var request = try authRequest("support/tickets")
        request.setValue("Bearer \(token)", forHTTPHeaderField:"Authorization")
        if let message {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField:"Content-Type")
            request.httpBody = try JSONEncoder().encode(["message":message])
        }
        let (data,response) = try await URLSession.shared.data(for:request)
        guard KeychainStore.get(tokenKey) == token else { throw AuthFailure.unauthorized }
        try validate(response,allowing:message == nil ? [200] : [201])
        return message == nil ? try JSONDecoder().decode(TicketList.self,from:data).tickets : []
    }

    private func authRequest(_ path: String) throws -> URLRequest {
        guard let base = URL(string:BetweenAPI.base),
              let host = base.host, !host.isEmpty,
              base.scheme == "http" || base.scheme == "https" else { throw AuthFailure.unavailable }
        let url = path.split(separator:"/").reduce(base) { $0.appendingPathComponent(String($1)) }
        return URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:15)
    }

    private func validate(_ response: URLResponse, allowing accepted: Set<Int>) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw AuthFailure.server }
        switch status {
        case 401: throw AuthFailure.unauthorized
        case 404, 405, 501, 503: throw AuthFailure.unavailable
        default: guard accepted.contains(status) else { throw AuthFailure.server }
        }
    }

    private func fetchMe(_ token: String) async throws -> BetweenAccount {
        var request = try authRequest("me")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response,allowing:[200])
        let envelope = try JSONDecoder().decode(AuthUserEnvelope.self, from: data)
        return BetweenAccount(id: envelope.user.id, nickname: envelope.user.nickname, public_id: envelope.user.public_id)
    }

    private func patchNickname(_ name: String, token: String) async throws -> BetweenAccount {
        var request = try authRequest("me")
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["nickname": name])
        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 409 { throw AuthFailure.nicknameTaken }
        try validate(response,allowing:[200])
        let envelope = try JSONDecoder().decode(AuthUserEnvelope.self, from: data)
        return BetweenAccount(id: envelope.user.id, nickname: envelope.user.nickname ?? name, public_id: envelope.user.public_id)
    }

    private func persist(_ fresh: BetweenAccount) {
        account = fresh
        guard !isPreview else { return }
        if let data = try? JSONEncoder().encode(fresh) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func loadCachedAccount() -> BetweenAccount? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(BetweenAccount.self, from: data)
    }

    private func clearSession() {
        if !isPreview { _ = KeychainStore.remove(tokenKey) }
        clearCachedAccount()
    }

    private func clearCachedAccount() {
        if !isPreview { UserDefaults.standard.removeObject(forKey: cacheKey) }
        account = nil
    }
}

private enum AuthFailure: Error {
    case unauthorized
    case unavailable
    case nicknameTaken
    case server
}

/// System Sign in with Apple control, styled to match the paper UI.
struct AppleSignInControl: View {
    @ObservedObject var auth: AuthManager
    @State private var showsPasswordSignIn = false
    private var zh: Bool { UserDefaults.standard.string(forKey: "native.language") == "zh" }

    var body: some View {
        if auth.isPreview {
            Button { auth.usePreviewAccount() } label: {
                Text(UserDefaults.standard.string(forKey: "native.language") == "zh" ? "登录测试账号" : "Sign in to test account")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(.black, in: RoundedRectangle(cornerRadius: 14))
            }
        } else {
            VStack(spacing: 10) {
                appleButton
                Button {
                    showsPasswordSignIn = true
                } label: {
                    Text(zh ? "账号密码登录" : "Sign In with Password")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(H5Design.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(hex: 0xe7deda)))
                }
                .buttonStyle(.plain)
                .disabled(auth.busy)
            }
            .sheet(isPresented: $showsPasswordSignIn) {
                PasswordSignInForm(auth: auth, zh: zh)
            }
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = []
        } onCompletion: { result in
            Task { @MainActor in auth.handleAppleCompletion(result) }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .opacity(auth.busy ? 0.55 : 1)
        .disabled(auth.busy)
    }
}


private struct PasswordSignInForm: View {
    @ObservedObject var auth: AuthManager
    let zh: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var isRegistering = false
    @State private var email = ""
    @State private var code = ""
    @State private var sentEmail = ""

    private func switchMode() {
        isRegistering.toggle()
        password = ""
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ZStack(alignment: .leading) {
                    Text(isRegistering ? (zh ? "注册账号" : "Create Account") : (zh ? "账号密码登录" : "Sign In with Password"))
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 44)
                    Button {
                        if isRegistering { switchMode() } else { dismiss() }
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(zh ? "返回" : "Back")
                }
                .foregroundStyle(H5Design.ink)
                TextField(zh ? "账号" : "Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                SecureField(zh ? "密码" : "Password", text: $password)
                    .textContentType(isRegistering ? .newPassword : .password)
                if isRegistering {
                    TextField(zh ? "邮箱" : "Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                    HStack {
                        TextField(zh ? "邮箱验证码" : "Email code", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        Button(sentEmail == email && !email.isEmpty ? (zh ? "重发" : "Resend") : (zh ? "发送验证码" : "Send code")) {
                            let address = email
                            Task { if await auth.sendRegistrationCode(to: address) { sentEmail = address } }
                        }
                        .disabled(auth.busy || !email.contains("@"))
                    }
                }
                Button {
                    let submittedPassword = password
                    password = ""
                    Task {
                        if await auth.signInWithPassword(username: username, password: submittedPassword, register: isRegistering, email: email, code: code) {
                            dismiss()
                        }
                    }
                } label: {
                    Text(isRegistering ? (zh ? "注册" : "Register") : (zh ? "登录" : "Sign In"))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(H5Design.ink)
                .disabled(auth.busy || username.isEmpty || password.isEmpty || (isRegistering && (email.isEmpty || code.count != 6)))
                Button(isRegistering ? (zh ? "已有账号？返回登录" : "Back to Sign In") : (zh ? "注册账号" : "Create Account")) {
                    switchMode()
                }
                .font(.footnote)
                .disabled(auth.busy)
                if isRegistering {
                    Text(zh ? "账号使用 3–32 位英文、数字、下划线或连字符，密码至少 12 位。" : "Use 3–32 letters, numbers, underscores, or hyphens for your username, and at least 12 characters for your password.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if auth.busy { ProgressView() }
                if let error = auth.errorText {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(24)
        }
    }
}
