import Foundation


enum DiagnosticUploadConfigurationState: Equatable, Sendable {
    case unavailable
    case configured
    case invalid
}

enum DiagnosticUploadTransportFactory {
    static var configurationState: DiagnosticUploadConfigurationState {
        return .unavailable
    }

    static func send(entries: [DiagnosticLogEntry]) throws {
        throw DiagnosticLogUploadError.serviceNotConfigured
    }
}
