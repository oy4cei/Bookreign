import Foundation
import XCTest
@testable import BookCatalog

final class CatalogTransportTests: XCTestCase, @unchecked Sendable {
    // Removing pacing, or failing to recheck after an actor suspension, lets these
    // independent clients start their requests together instead of a second apart.
    func testConcurrentClientsShareOneOpenLibraryRequestBudget() async throws {
        let recorder = RequestRecorder()
        let transport = CatalogTransport(fetch: { request in
            await recorder.record(request)
            return Self.searchResponse(for: request)
        })
        let clients = (0..<3).map { _ in CatalogClient(fetch: { try await transport.data(for: $0) }) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for client in clients {
                group.addTask { _ = try await client.search("books") }
            }
            try await group.waitForAll()
        }
        let starts = await recorder.starts
        XCTAssertEqual(starts.count, 3)
        for pair in zip(starts, starts.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.0.duration(to: pair.1), .milliseconds(950))
        }
    }

    // Removing cancellation checks/sleep cancellation would dispatch a request
    // after its user has dismissed search and keep cancellation waiting a second.
    func testCancelledWaitingRequestNeverReachesTheNetwork() async throws {
        let recorder = RequestRecorder()
        let transport = CatalogTransport(fetch: { request in
            await recorder.record(request)
            return Self.searchResponse(for: request)
        })
        let request = URLRequest(url: URL(string: "https://openlibrary.org/search.json?q=books")!)
        _ = try await transport.data(for: request)
        let pending = Task { try await transport.data(for: request) }
        try await Task.sleep(for: .milliseconds(50))
        let cancelledAt = ContinuousClock.now
        pending.cancel()
        do {
            _ = try await pending.value
            XCTFail("A queued request must throw on cancellation")
        } catch is CancellationError {
            XCTAssertLessThan(cancelledAt.duration(to: .now), .milliseconds(500))
        }
        let requests = await recorder.starts
        XCTAssertEqual(requests.count, 1, "Cancelled requests must not be sent")
    }

    // A shared limiter must not accidentally delay the separate fallback host.
    func testOtherHostsDoNotWaitForOpenLibraryBudget() async throws {
        let recorder = RequestRecorder()
        let transport = CatalogTransport(fetch: { request in
            await recorder.record(request)
            return Self.searchResponse(for: request)
        })
        _ = try await transport.data(for: URLRequest(url: URL(string: "https://openlibrary.org/search.json")!))
        _ = try await transport.data(for: URLRequest(url: URL(string: "https://api.mbooks.com.ua/api/v1/search/main/")!))
        let starts = await recorder.starts
        XCTAssertEqual(starts.count, 2)
        XCTAssertLessThan(starts[0].duration(to: starts[1]), .milliseconds(500))
    }

    private static func searchResponse(for request: URLRequest) -> (Data, URLResponse) {
        (Data(#"{"docs":[]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private actor RequestRecorder {
    private(set) var starts: [ContinuousClock.Instant] = []
    func record(_ request: URLRequest) { starts.append(.now) }
}
