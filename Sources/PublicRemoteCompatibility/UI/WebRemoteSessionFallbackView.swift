import BuddyRemoteCore
import SwiftUI

@MainActor
public protocol WebRemoteSessionModel: ObservableObject {
    var webRemoteState: WebRemoteSessionState { get }

    func enableWebRemoteConnection()
    func disableWebRemoteConnection()
}

public struct WebRemoteSessionLocalization {
    public let locale: Locale
    private let resolve: (String) -> String

    public init(
        locale: Locale = .current,
        text: @escaping (String) -> String
    ) {
        self.locale = locale
        resolve = text
    }

    public func text(_ key: String) -> String { resolve(key) }
}

/// Explains that this planned connection method is unavailable in the current build.
public struct WebRemoteMiniProgramCodeView<Model: WebRemoteSessionModel>: View {
    private let localization: WebRemoteSessionLocalization

    public init(
        model: Model,
        localization: WebRemoteSessionLocalization,
        size: CGFloat = 224,
        onDiagnostic: @escaping (String) -> Void = { _ in }
    ) {
        self.localization = localization
    }

    public var body: some View {
        Text(localization.text("connection.web.unavailable_help"))
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}
