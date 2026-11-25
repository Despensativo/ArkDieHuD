import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// Hosts the AVSampleBufferDisplayLayer as its primary layerClass so AVKit / AVPictureInPictureController
/// can find the host UIView and UIWindow in the responder chain.
struct PiPPreviewView: UIViewRepresentable {
    @Bindable var hudController: PiPHUDController

    func makeUIView(context: Context) -> SampleBufferHostView {
        let view = SampleBufferHostView()
        view.backgroundColor = .clear
        view.layer.cornerRadius = 8
        view.clipsToBounds = true
        hudController.attachHostView(view)
        return view
    }

    func updateUIView(_ uiView: SampleBufferHostView, context: Context) {
        uiView.setNeedsLayout()
    }
}

final class SampleBufferHostView: UIView {
    override class var layerClass: AnyClass {
        AVSampleBufferDisplayLayer.self
    }

    var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
    }
}
