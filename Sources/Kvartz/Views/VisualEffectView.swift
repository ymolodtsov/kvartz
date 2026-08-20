import AppKit
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}

struct GlassSurface: ViewModifier {
    let radius: CGFloat
    private let transitionHeight: CGFloat = 140

    private var materialMask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: Color.white.opacity(0.62), location: 0.16),
                    .init(color: .white, location: 0.34),
                    .init(color: .white, location: 1.00)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: transitionHeight)
            Color.white
        }
    }

    private var surfaceFill: some View {
        VStack(spacing: 0) {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.black.opacity(0.03), location: 0.00),
                    .init(color: Color.black.opacity(0.54), location: 0.16),
                    .init(color: Color.black.opacity(0.84), location: 0.34),
                    .init(color: Color.black.opacity(0.93), location: 1.00)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: transitionHeight)
            Color.black.opacity(0.93)
        }
    }

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    VisualEffectView(material: .underWindowBackground)
                        .mask(materialMask)
                    surfaceFill
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
    }
}

extension View {
    func glassSurface(radius: CGFloat) -> some View { modifier(GlassSurface(radius: radius)) }
}
