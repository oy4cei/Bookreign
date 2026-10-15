import SwiftUI
import LibraryCore

/// Limits network bytes and decoded pixels for covers supplied by catalogs or shared backups.
struct SafeRemoteCover: View {
    let url: URL
    var fit = false
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: fit ? .fit : .fill)
            } else { Color.clear }
        }.task(id: url) {
            image = nil
            do {
                let data = try await CoverImageLoader.load(url)
                let thumbnail = await Task.detached(priority: .utility) {
                    LibraryImageSafety.thumbnail(data, maximumDimension: 1_000)
                }.value
                try Task.checkCancellation()
                if let thumbnail { image = UIImage(cgImage: thumbnail) }
            } catch { /* The generated cover remains visible when a remote cover fails. */ }
        }
    }
}
