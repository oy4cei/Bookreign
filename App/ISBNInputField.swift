import SwiftUI
import UIKit
import BookCatalog

/// The label stays visible; only the number participates in editing and selection.
struct ISBNInputField: View {
    @Binding var text: String
    var accessibilityLabel = "ISBN"
    var accessibilityIdentifier = "bookISBN"
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text("ISBN").font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(Color.archiveSecondary).fixedSize()
            ISBNNumberField(text: $text, accessibilityLabel: accessibilityLabel,
                            accessibilityIdentifier: accessibilityIdentifier, onSubmit: onSubmit)
        }
    }
}

private struct ISBNNumberField: UIViewRepresentable {
    @Binding var text: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.backgroundColor = .clear
        field.keyboardType = .numbersAndPunctuation
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.autocapitalizationType = .none
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedDigitSystemFont(ofSize: 17, weight: .regular))
        field.adjustsFontForContentSizeCategory = true
        field.clearButtonMode = .whileEditing
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.accessibilityLabel = accessibilityLabel
        field.accessibilityIdentifier = accessibilityIdentifier
        field.returnKeyType = onSubmit == nil ? .done : .search
        field.textColor = UIColor(Color.archiveText)
        field.tintColor = UIColor(Color.forest)
        field.attributedPlaceholder = NSAttributedString(string: "978-617-8076-41-2", attributes: [
            .foregroundColor: UIColor(Color.archiveSecondary)
        ])
        let formatted = ISBNInputFormatting.format(text)
        if field.text != formatted { field.text = formatted }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width,
               height: max(30, uiView.intrinsicContentSize.height))
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ISBNNumberField
        init(_ parent: ISBNNumberField) { self.parent = parent }

        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            guard let edit = ISBNInputFormatting.applyingEdit(to: field.text ?? "", range: range, replacement: string) else { return false }
            field.text = edit.text
            if let position = field.position(from: field.beginningOfDocument, offset: edit.caretUTF16) {
                field.selectedTextRange = field.textRange(from: position, to: position)
            }
            parent.text = edit.text
            return false
        }

        func textFieldShouldClear(_ textField: UITextField) -> Bool {
            parent.text = ""
            return true
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            if let submit = parent.onSubmit { submit() }
            else { textField.resignFirstResponder() }
            return false
        }
    }
}
