import SwiftUI

// Liquid Glass needs macOS 26. These wrappers use it there and fall back to
// bordered buttons and materials on macOS 15, so that SyncGlass still runs on
// Macs that cannot update. Use them instead of the glass APIs directly.

extension View {
    /// `.buttonStyle(.glass)`, or `.bordered` before macOS 26.
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// A round icon button: `.buttonStyle(.glass)` with a circle border shape.
    /// Before macOS 26 a filled circle with the padding glass adds; `.bordered`
    /// would hug the label.
    @ViewBuilder
    func glassCircleButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass).buttonBorderShape(.circle)
        } else {
            buttonStyle(CircleIconButtonStyle())
        }
    }

    /// `.buttonStyle(.glassProminent)`, or `.borderedProminent` before macOS 26.
    @ViewBuilder
    func glassProminentButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// `.glassEffect(.regular.tint(tint), in: shape)`, or a material filled
    /// with the tint before macOS 26. Without a tint a light fill and an outline
    /// keep the shape visible; the material alone vanishes on a dark window.
    @ViewBuilder
    func glassBackground(tint: Color? = nil, in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(tint), in: shape)
        } else {
            background {
                ZStack {
                    shape.fill(.regularMaterial)
                    shape.fill(tint ?? .primary.opacity(0.06))
                }
            }
            .overlay(shape.stroke(.primary.opacity(0.08)))
        }
    }
}

/// The macOS 15 stand-in for a round glass button.
private struct CircleIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CircleIconButton(configuration: configuration)
    }

    private struct CircleIconButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.controlSize) private var controlSize
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                // Matches the padding of glass buttons on macOS 26.
                .padding(controlSize == .small || controlSize == .mini ? 3 : 4.5)
                .background(Circle().fill(.primary.opacity(configuration.isPressed ? 0.2 : 0.1)))
                .overlay(Circle().strokeBorder(.primary.opacity(0.08)))
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.5)
        }
    }
}

/// `GlassEffectContainer`, or its content unchanged before macOS 26.
struct GlassContainer<Content: View>: View {
    let spacing: CGFloat?
    @ViewBuilder let content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
