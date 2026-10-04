import Foundation

public enum LibraryBackup {
    private struct Envelope: Codable {
        let version: Int
        let snapshot: LibrarySnapshot
    }

    public static func encode(_ snapshot: LibrarySnapshot) throws -> Data {
        try snapshot.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(Envelope(version: 1, snapshot: snapshot))
    }

    public static func decode(_ data: Data) throws -> LibrarySnapshot {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == 1 else { throw LibraryDataError.unsupportedVersion(envelope.version) }
        try envelope.snapshot.validate()
        return envelope.snapshot
    }

    public static func csv(_ snapshot: LibrarySnapshot) -> String {
        let header = "edition_id,copy_id,title,author,isbn,language,publisher,year,location,shelf,borrower,loaned_at,due_at,returned_at,notes,genres"
        let locations = Dictionary(uniqueKeysWithValues: snapshot.locations.map { ($0.id, $0.name) })
        var rows = [header]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for edition in snapshot.editions {
            let editionCopies = snapshot.copies.filter { $0.editionID == edition.id }
            if editionCopies.isEmpty {
                rows.append(row(edition: edition, copy: nil, location: "", loan: nil, formatter: formatter))
            }
            for copy in editionCopies {
                let copyLoans = snapshot.loans.filter { $0.copyID == copy.id }
                if copyLoans.isEmpty {
                    rows.append(row(edition: edition, copy: copy, location: locations[copy.locationID] ?? "", loan: nil, formatter: formatter))
                }
                for loan in copyLoans {
                    rows.append(row(edition: edition, copy: copy, location: locations[copy.locationID] ?? "", loan: loan, formatter: formatter))
                }
            }
        }
        return "\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n"
    }

    private static func row(
        edition: BookEdition, copy: BookCopy?, location: String, loan: BookLoan?, formatter: ISO8601DateFormatter
    ) -> String {
        [
            edition.id.uuidString, copy?.id.uuidString ?? "", edition.title, edition.author,
            edition.isbn, edition.language, edition.publisher, edition.year, location,
            copy?.shelf ?? "", loan?.borrower ?? "",
            loan.map { formatter.string(from: $0.loanedAt) } ?? "",
            loan?.dueAt.map { formatter.string(from: $0) } ?? "",
            loan?.returnedAt.map { formatter.string(from: $0) } ?? "", edition.notes,
            edition.genres.joined(separator: "; ")
        ].map(csvCell).joined(separator: ",")
    }

    private static func csvCell(_ value: String) -> String {
        let firstNonSpace = value.drop(while: { $0.isWhitespace }).first
        let safeValue = firstNonSpace.map({ "=+-@".contains($0) }) == true ? "'" + value : value
        return "\"" + safeValue.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
