import SwiftUI

enum Palette {
    static let paper = color(0xF6F5EF)
    static let surface = color(0xFDFCF8)
    static let ink = color(0x1F2326)
    static let muted = color(0x62545A)
    static let line = color(0xE5D4DB)
    static let accent = color(0x7B2F4A)
    static let tint = color(0xF3E3E9)
    static let deep = color(0x411B2C)
    static let light = color(0xF2D2E0)

    static func color(_ hex: UInt32) -> Color {
        Color(red: Double(hex >> 16) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

enum BoardButtonKind: Equatable { case plain, bordered, primary, tablePrimary, tablePlain }

struct BoardButton: View {
    var key: String
    var id: String
    var kind: BoardButtonKind = .plain
    var action: () -> Void

    init(_ key: String, id: String, kind: BoardButtonKind = .plain, action: @escaping () -> Void) {
        self.key = key
        self.id = id
        self.kind = kind
        self.action = action
    }

    private var filled: Bool { kind == .primary || kind == .tablePrimary }
    private var bare: Bool { kind == .plain || kind == .tablePlain }
    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .tablePrimary: return Palette.deep
        case .tablePlain: return Palette.light
        default: return Palette.accent
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: return Palette.accent
        case .tablePrimary: return Palette.tint
        case .bordered: return Palette.surface
        default: return .clear
        }
    }

    var body: some View {
        Button(action: action) {
            Text(L.t(key))
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(foreground)
                .padding(.horizontal, 6)
                .frame(minWidth: 44, maxWidth: bare ? nil : .infinity, minHeight: filled ? 53 : 44)
                .background(fill, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if kind == .bordered { RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line).allowsHitTesting(false) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressedBoardStyle())
        .accessibilityIdentifier(id)
    }
}

private struct PressedBoardStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.46)
    }
}

struct Panel: ViewModifier {
    var fill = Palette.surface
    func body(content: Content) -> some View {
        content.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.line).allowsHitTesting(false) }
    }
}

struct BoardField: View {
    var key: String
    var placeholder: String
    var id: String
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.t(key)).font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            TextField(L.t(placeholder), text: $value)
                .font(.body)
                .padding(.horizontal, 8).frame(minHeight: 44)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line).allowsHitTesting(false) }
                .accessibilityLabel(L.t(key))
                .accessibilityIdentifier(id)
        }
    }
}

struct SheetHeader: View {
    var key: String
    var close: () -> Void

    var body: some View {
        HStack {
            Text(L.t(key)).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Spacer()
            BoardButton("close", id: "sheet.close", action: close)
        }
    }
}
