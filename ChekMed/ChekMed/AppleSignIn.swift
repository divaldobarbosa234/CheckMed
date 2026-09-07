import AuthenticationServices
import Foundation
import UIKit

struct AppleIDSignInResult: Sendable {
    var idToken: String
    var fullName: String?
}

enum AppleSignInError: LocalizedError {
    case missingToken
    case noWindow

    var errorDescription: String? {
        switch self {
        case .missingToken:
            "Apple did not return an ID token. Try again."
        case .noWindow:
            "Sign in with Apple needs a visible window."
        }
    }
}

/// Presents the system Sign in with Apple sheet and returns the identity token.
@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleIDSignInResult, Error>?

    func signIn(hashedNonce: String) async throws -> AppleIDSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { continuation = nil }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              !idToken.isEmpty
        else {
            continuation?.resume(throwing: AppleSignInError.missingToken)
            return
        }
        var fullName: String?
        if let components = credential.fullName {
            let formatted = PersonNameComponentsFormatter().string(from: components)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !formatted.isEmpty { fullName = formatted }
        }
        continuation?.resume(returning: AppleIDSignInResult(idToken: idToken, fullName: fullName))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
