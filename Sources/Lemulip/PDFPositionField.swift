#if os(macOS)
import SwiftUI

enum PDFEditorFocus: Hashable {
    case content
    case position(Int)
}

/// The displayed output number is editable without competing with the row's
/// selection button or drag gesture. Leaving the field cancels an unsubmitted edit.
@MainActor
struct PDFPositionField: View {
    let item: Int
    let position: Int
    let allowedPositions: ClosedRange<Int>
    let label: String
    let hint: String
    let invalidHint: String
    let focus: FocusState<PDFEditorFocus?>.Binding
    @Binding var editingPosition: Int?
    let beginEditing: () -> Void
    let move: (Int) -> Bool
    @State private var draft = ""
    @State private var isInvalid = false

    var body: some View {
        TextField("", text: Binding(get: { draft }, set: { value in
            // AppKit may write back the unchanged value when focus moves.
            // That is not a selection gesture or an uncommitted edit.
            draft = value
            isInvalid = false
            if value == String(position) {
                if editingPosition == item { editingPosition = nil }
            } else {
                if editingPosition != item { beginEditing() }
                editingPosition = item
            }
        }))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
            .frame(width: 46)
            .focused(focus, equals: .position(item))
            .accessibilityIdentifier("pdf.position.\(item)")
            .accessibilityLabel(label)
            .accessibilityHint(isInvalid ? invalidHint : hint)
            .help(isInvalid ? invalidHint : hint)
            .overlay {
                if isInvalid {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.accent, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .trailing) {
                if isInvalid {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 10))
                        .foregroundStyle(Palette.ink).offset(x: 13)
                        .accessibilityLabel(invalidHint)
                }
            }
            .onAppear { draft = String(position) }
            .onDisappear {
                if editingPosition == item { editingPosition = nil }
                if focus.wrappedValue == .position(item) { focus.wrappedValue = .content }
            }
            .onChange(of: position) { value in
                if editingPosition != item { draft = String(value) }
            }
            .onChange(of: focus.wrappedValue) { value in
                // Passive focus is not a new edit or a selection action.
                // Leaving a field still cancels its unsubmitted draft.
                if value != .position(item) {
                    if editingPosition == item { editingPosition = nil }
                    isInvalid = false
                    draft = String(position)
                }
            }
            .onSubmit {
                guard let value = Int(draft.trimmingCharacters(in: .whitespacesAndNewlines)),
                      allowedPositions.contains(value), move(value) else {
                    isInvalid = true
                    editingPosition = item
                    return
                }
                editingPosition = nil
                focus.wrappedValue = .content
            }
            .onExitCommand {
                draft = String(position)
                editingPosition = nil
                isInvalid = false
                focus.wrappedValue = .content
            }
    }
}
#endif
