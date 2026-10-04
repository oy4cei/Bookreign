import Foundation
import Vision

struct CoverRecognition {
    /// Raw lines in Vision's reading order; the caller can suggest a title and author.
    let text: String

    /// Language codes among en/ru/uk that this device's active Vision revision supports.
    let supportedBookLanguages: [String]
}

enum CoverTextRecognizer {
    /// Runs fully on device and outside the main thread. Image data is never uploaded.
    static func recognize(_ data: Data) async throws -> CoverRecognition {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true

                    // Language availability changes by OS and request revision. Only
                    // advertise and request languages reported by this device.
                    let available = try request.supportedRecognitionLanguages()
                    let preferred = ["en", "ru", "uk"]
                    let selected: [(String, String)] = preferred.compactMap { code in
                        guard let identifier = available.first(where: {
                            $0.lowercased() == code || $0.lowercased().hasPrefix(code + "-")
                        }) else { return nil }
                        return (code, identifier)
                    }
                    if !selected.isEmpty {
                        request.recognitionLanguages = selected.map(\.1)
                    }

                    let handler = VNImageRequestHandler(data: data, options: [:])
                    try handler.perform([request])
                    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: CoverRecognition(
                        text: lines.joined(separator: "\n"),
                        supportedBookLanguages: selected.map(\.0)
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
