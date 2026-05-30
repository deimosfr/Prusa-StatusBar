import Foundation

/// A resolved request to play one camera stream. Carries the source URL plus
/// the RTSP transport so the VLC media factory can apply the matching libvlc
/// options. Pure value type so SwiftUI views compare it for identity and
/// tests construct it without VLCKit.
public struct CameraStreamRequest: Equatable, Sendable {
    public let url: URL
    public let transport: GenericCameraRTSPTransport

    public init(url: URL, transport: GenericCameraRTSPTransport = .tcp) {
        self.url = url
        self.transport = transport
    }
}
