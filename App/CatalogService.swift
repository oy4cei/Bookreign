import Foundation
import BookCatalog

enum CatalogService {
    static func client() -> CatalogClient {
        #if DEBUG
        // This transport is restricted to the isolated UI-test launch. Production
        // lookups always use the real catalog client and never a bundled book list.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing") && arguments.contains("--catalog-test-fixture") {
            return CatalogClient(fetch: { request in
                guard let url = request.url else { throw URLError(.badURL) }
                if url.host == "openlibrary.org", url.path == "/isbn/9789664481974.json" {
                    let data = Data(#"{"key":"/books/OL4299M","title":"Малюк чує звук","authors":[{"name":"Саша Кольцова"}],"publishers":["Видавництво Старого Лева"],"publish_date":"2023","languages":[{"key":"/languages/ukr"}]}"#.utf8)
                    return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
                let body: String?
                switch (url.host, url.path) {
                case ("openlibrary.org", "/isbn/9780306406157.json"):
                    body = #"{"key":"/books/OL4300M","title":"Русское издание","isbn_13":["9780306406157"],"authors":[{"name":"Автор"}],"languages":[{"key":"/languages/rus"}]}"#
                case ("api.mbooks.com.ua", "/api/v1/search/main"):
                    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "query" }?.value
                    body = query == "9780306406157" ? #"{"status":"success","code":200,"data":{"items":{"books":{"items":[{"slug":"ui-ukrainian-edition"}],"total":1}}}}"# : nil
                case ("api.mbooks.com.ua", "/api/v1/books/ui-ukrainian-edition"):
                    body = #"{"status":"success","code":200,"data":{"item":{"slug":"ui-ukrainian-edition","title":"Українське видання","isbn":"9780306406157","languages":["Українська"],"authors":[{"first_name":"Автор"}]}}}"#
                default: body = nil
                }
                if let body {
                    return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
                return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            })
        }
        #endif
        return CatalogClient()
    }
}
