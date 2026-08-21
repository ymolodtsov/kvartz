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

    private var surfaceShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    private var materialMask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.white.opacity(0.0), location: 0.00),
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
                    .init(color: Color.black.opacity(0.0), location: 0.00),
                    .init(color: Color.black.opacity(1), location: 1.00)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: transitionHeight)
        }
    }

    private var nativeSurfaceFill: some View {
        LinearGradient(
            stops: [
                .init(color: Color.black.opacity(0.50), location: 0.00),
                .init(color: Color.black.opacity(0.60), location: 0.10),
                .init(color: Color.black.opacity(1), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }


    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background {
                    ZStack {
                        Color.clear
                            .glassEffect(
                                .clear,
                                in: surfaceShape
                            )
                        nativeSurfaceFill
                    }

                }
                .clipShape(surfaceShape)
                .shadow(color: .black.opacity(0.40), radius: 6, x: 0, y: 3)
        } else {
            content
                .background {
                    ZStack {
                        VisualEffectView(material: .underWindowBackground)
                            .mask(materialMask)
                        surfaceFill
                    }
                    .clipShape(surfaceShape)
                }
        }
    }
}

public extension View {
    func glassSurface(radius: CGFloat) -> some View { modifier(GlassSurface(radius: radius)) }
}

private struct GlassSurfacePreview: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo, .cyan.opacity(0.72), .orange.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.pink.opacity(0.75))
                .frame(width: 180, height: 180)
                .blur(radius: 28)
                .offset(x: 150, y: -80)

            VStack(spacing: 14) {
                HStack {
                    Label("Kvartz", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: "gearshape")
                    Image(systemName: "xmark")
                }

                Text("Ask anything…")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .frame(height: 58)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))

                HStack {
                    Text("Liquid Glass preview")
                    Spacer()
                    Text("⌘ ⇧ Space")
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
            }
            .foregroundStyle(.white.opacity(0.88))
            .padding(18)
            .frame(width: 372, height: 180, alignment: .top)
            .glassSurface(radius: 30)
        }
        .frame(width: 420, height: 228)
        .environment(\.colorScheme, .dark)
    }
}

#Preview("Glass Surface") {
    GlassSurfacePreview()
}
