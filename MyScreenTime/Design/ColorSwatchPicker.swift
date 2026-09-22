import SwiftUI

/// A grid of tappable color swatches used to assign a child's identity color in
/// ChildFormView (create) and ChildSettingsView (edit).
struct ColorSwatchPicker: View {
    @Binding var selection: ChildColor

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ChildColor.allCases) { option in
                Button {
                    selection = option
                } label: {
                    ZStack {
                        Circle()
                            .fill(option.color)
                        if selection == option {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .overlay {
                        Circle()
                            .stroke(AppTheme.cardBorder, lineWidth: selection == option ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.displayName)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
    }
}

#Preview {
    ColorSwatchPicker(selection: .constant(.teal))
        .padding()
}
