import CoreGraphics
import Foundation

/// Display density mode for the floating Picture-in-Picture telemetry HUD
enum HUDLayoutMode: String, CaseIterable, Identifiable {
    case gamerBar = "Barra Gamer (1 Linha Transparente)"
    case gamerMini = "Overlay Gamer (2 Linhas)"
    case compact = "Grid Compacto"
    case detailed = "Detalhado"

    var id: String { rawValue }

    /// Logical canvas size in points (rendered at 2x for Retina sharpness in PiP)
    var canvasSize: CGSize {
        switch self {
        case .gamerBar:
            return CGSize(width: 540, height: 32)
        case .gamerMini:
            return CGSize(width: 285, height: 56)
        case .compact:
            return CGSize(width: 380, height: 86)
        case .detailed:
            return CGSize(width: 440, height: 210)
        }
    }

    var aspectRatio: CGFloat {
        canvasSize.width / canvasSize.height
    }
}
