import SwiftUI
import BookCatalog

/// A single ISBN goes straight to review; batch scanning is an explicit choice.
struct SingleBookScannerView: View {
    let locationName: String
    let onISBN: (String) -> Void
    let onOtherMethods: () -> Void
    let onBatch: () -> Void
    @State private var manualISBN = ""
    @State private var feedback: LocalizedMessage?
    @State private var submitted = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                BarcodeScannerView { submit($0) }
                    .frame(height: min(310, max(160, geometry.size.height * 0.43)))
                    .clipped()
                Form {
                    Section {
                        HStack {
                            ISBNInputField(text: $manualISBN, accessibilityLabel: L("Ввести ISBN"),
                                           accessibilityIdentifier: "scannerISBN", onSubmit: { submit(manualISBN) })
                            Button { submit(manualISBN) } label: {
                                Image(systemName: "arrow.right")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(Color.archiveActionText)
                                    .background(Color.forestFill, in: RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(L("Найти книгу"))
                            .accessibilityIdentifier("scannerFindBook")
                            .disabled(manualISBN.isEmpty || submitted)
                            .opacity(manualISBN.isEmpty || submitted ? 0.45 : 1)
                        }
                        if let feedback { Text(L(feedback)).font(.caption).foregroundStyle(.red) }
                    } footer: {
                        Text(L("Наведите камеру на штрихкод. После поиска проверьте обложку и подтвердите добавление."))
                    }.archiveRow()
                    Section {
                        Label(locationName, systemImage: "mappin.and.ellipse")
                            .foregroundStyle(Color.forest)
                        Button(L("Другие способы"), systemImage: "square.and.pencil", action: onOtherMethods)
                            .accessibilityIdentifier("otherAddMethods")
                        Button(L("Сканировать несколько"), systemImage: "barcode.viewfinder", action: onBatch)
                            .accessibilityIdentifier("batchScan")
                    }.archiveRow()
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollContentBackground(.hidden)
                .background(Color.paper)
            }
        }.background(Color.paper)
    }

    private func submit(_ raw: String) {
        guard !submitted else { return }
        guard let isbn = ISBN.normalize(raw) else {
            feedback = "Это не ISBN книги. Нужен код ISBN-10 или ISBN-13 с верной контрольной цифрой."
            return
        }
        submitted = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onISBN(isbn)
    }
}
