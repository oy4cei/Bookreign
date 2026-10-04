import Foundation

/// All production clients share Open Library's default one-request-per-second
/// budget. The injected CatalogClient transport remains unpaced for fixtures.
actor CatalogTransport {
    static let shared = CatalogTransport()

    private let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let clock = ContinuousClock()
    private var nextOpenLibraryRequest: ContinuousClock.Instant?

    init(fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
        try await URLSession.shared.data(for: $0)
    }) {
        self.fetch = fetch
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        if request.url?.host?.lowercased() == "openlibrary.org" {
            // Actor methods are reentrant while sleeping: every resumed waiter
            // must check the current deadline before claiming the next slot.
            while let next = nextOpenLibraryRequest, clock.now < next {
                try await clock.sleep(until: next)
                try Task.checkCancellation()
            }
            try Task.checkCancellation()
            nextOpenLibraryRequest = clock.now.advanced(by: .seconds(1))
        }
        return try await fetch(request)
    }
}
