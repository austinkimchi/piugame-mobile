import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

enum MyPIUOAuthError: LocalizedError {
    case alreadyAuthenticating
    case cancelled
    case invalidCallback
    case randomGenerationFailed(OSStatus)
    case sessionFailedToStart

    var errorDescription: String? {
        switch self {
        case .alreadyAuthenticating: "A MyPIU sign-in is already open."
        case .cancelled: "MyPIU sign-in was cancelled."
        case .invalidCallback: "MyPIU returned an invalid sign-in callback."
        case .randomGenerationFailed: "MyPIU could not create a secure sign-in request."
        case .sessionFailedToStart: "MyPIU could not open the sign-in page."
        }
    }
}

@MainActor
final class MyPIUOAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let apiClient: MyPIUAPIClient
    private let installationID: String
    private let appVersion: String?
    private var activeSession: ASWebAuthenticationSession?
    private var appleNonce: String?

    init(apiClient: MyPIUAPIClient, installationID: String, appVersion: String?) {
        self.apiClient = apiClient
        self.installationID = installationID
        self.appVersion = appVersion
    }

    func authorize(provider: MyPIUAuthProvider) async throws -> MyPIUAccessToken {
        guard activeSession == nil, appleNonce == nil else { throw MyPIUOAuthError.alreadyAuthenticating }
        let verifier = try secureRandomURLString(byteCount: 32)
        let state = try secureRandomURLString(byteCount: 24)
        let challenge = mobilePkceChallenge(verifier)
        let url = apiClient.authorizationURL(provider: provider, challenge: challenge, state: state)

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "mypiu"
            ) { [weak self] callbackURL, error in
                Task { @MainActor [weak self] in
                    self?.activeSession = nil
                    if let authenticationError = error as? ASWebAuthenticationSessionError,
                       authenticationError.code == .canceledLogin {
                        continuation.resume(throwing: MyPIUOAuthError.cancelled)
                        return
                    }
                    guard error == nil,
                          let callbackURL,
                          let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                          components.scheme == "mypiu",
                          components.host == "oauth",
                          components.path == "/callback",
                          components.queryValue(named: "state") == state,
                          let code = components.queryValue(named: "code"),
                          !code.isEmpty else {
                        continuation.resume(throwing: error ?? MyPIUOAuthError.invalidCallback)
                        return
                    }

                    guard let self else {
                        continuation.resume(throwing: MyPIUOAuthError.invalidCallback)
                        return
                    }
                    do {
                        let token = try await self.apiClient.exchangeAuthorizationCode(
                            code: code,
                            verifier: verifier,
                            installationID: self.installationID,
                            appVersion: self.appVersion
                        )
                        continuation.resume(returning: token)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            if !session.start() {
                activeSession = nil
                continuation.resume(throwing: MyPIUOAuthError.sessionFailedToStart)
            }
        }
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) throws {
        guard activeSession == nil, appleNonce == nil else { throw MyPIUOAuthError.alreadyAuthenticating }
        let nonce = try secureRandomURLString(byteCount: 32)
        request.requestedScopes = [.fullName, .email]
        request.nonce = appleNonceHash(nonce)
        appleNonce = nonce
    }

    func authorizeWithApple(_ result: Result<ASAuthorization, Error>) async throws -> MyPIUAccessToken {
        guard let nonce = appleNonce else { throw MyPIUOAuthError.invalidCallback }
        appleNonce = nil
        let authorization: ASAuthorization
        do {
            authorization = try result.get()
        } catch let error as ASAuthorizationError where error.code == .canceled {
            throw MyPIUOAuthError.cancelled
        }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw MyPIUOAuthError.invalidCallback
        }
        return try await apiClient.exchangeAppleIdentityToken(
            identityToken: identityToken,
            nonce: nonce,
            firstName: credential.fullName?.givenName,
            lastName: credential.fullName?.familyName,
            installationID: installationID,
            appVersion: appVersion
        )
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap { $0.windows }.first(where: \.isKeyWindow) ?? UIWindow()
    }
}

func mobilePkceChallenge(_ verifier: String) -> String {
    Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
}

func appleNonceHash(_ nonce: String) -> String {
    SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
}

private func secureRandomURLString(byteCount: Int) throws -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    let status = bytes.withUnsafeMutableBytes { buffer in
        SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
    }
    guard status == errSecSuccess else { throw MyPIUOAuthError.randomGenerationFailed(status) }
    return Data(bytes).base64URLEncodedString()
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension URLComponents {
    func queryValue(named name: String) -> String? {
        queryItems?.first(where: { $0.name == name })?.value
    }
}
