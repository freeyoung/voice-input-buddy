import Network

public enum AppleRemoteAudioListenerPolicy {
    /// This IPC service is local-only, including when an ephemeral port is used.
    public static func parameters(port: UInt16) -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(
            host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any
        )
        return parameters
    }
}
