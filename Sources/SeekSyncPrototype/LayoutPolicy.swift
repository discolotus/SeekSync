import CoreGraphics

enum SeekSyncLayoutMode: Equatable {
    case compact
    case standard
    case wide

    init(width: CGFloat) {
        if width < 1_050 {
            self = .compact
        } else if width < 1_200 {
            self = .standard
        } else {
            self = .wide
        }
    }

    var defaultsToOpenInspector: Bool { self != .compact }
    var usesOverlayInspector: Bool { self == .compact }
}
