import Foundation

struct DiagnosticLogEntry: Equatable {
    let sequence: Int
    let message: String
}

enum DiagnosticLogUploadError: Error, Equatable {
    case serviceNotConfigured
    case invalidServiceConfiguration
    case noLogs
    case uploadFailed
}

final class DiagnosticLogUploader: @unchecked Sendable {
    static let shared = DiagnosticLogUploader()

    typealias Sender = (_ entries: [DiagnosticLogEntry]) throws -> Void
    typealias ConfigurationStateProvider = () -> DiagnosticUploadConfigurationState

    private let eventProvider: () -> [PublicDiagnosticEvent]
    private let publicEventAcknowledger: ([PublicDiagnosticEvent]) -> Void
    private let configurationStateProvider: ConfigurationStateProvider
    private let sender: Sender
    private let queue = DispatchQueue(label: "VoiceInputBuddy.diagnosticUpload", qos: .userInitiated)
    private weak var privateEventProvider: (any PrivateDiagnosticUploadProvider)?

    init(
        eventProvider: @escaping () -> [PublicDiagnosticEvent] = {
            AppLogger.shared.publicDiagnosticEvents()
        },
        publicEventAcknowledger: @escaping ([PublicDiagnosticEvent]) -> Void = {
            AppLogger.shared.markPublicDiagnosticEventsUploaded($0)
        },
        configurationStateProvider: @escaping ConfigurationStateProvider = {
            DiagnosticUploadTransportFactory.configurationState
        },
        sender: @escaping Sender = DiagnosticUploadTransportFactory.send
    ) {
        self.eventProvider = eventProvider
        self.publicEventAcknowledger = publicEventAcknowledger
        self.configurationStateProvider = configurationStateProvider
        self.sender = sender
    }

    func setPrivateEventProvider(_ provider: (any PrivateDiagnosticUploadProvider)?) {
        queue.sync {
            privateEventProvider = provider
        }
    }

    // This product never sends diagnostics, even if a legacy configuration is imported.
    func upload(completion: @escaping (Result<Int, DiagnosticLogUploadError>) -> Void) {
        DispatchQueue.main.async { completion(.failure(.serviceNotConfigured)) }
    }

    func uploadSynchronously() -> Result<Int, DiagnosticLogUploadError> {
        .failure(.serviceNotConfigured)
    }

    func uploadSynchronously(
        privateRecords: [PrivateDiagnosticUploadRecord]
    ) -> Result<Int, DiagnosticLogUploadError> {
        .failure(.serviceNotConfigured)
    }
}
