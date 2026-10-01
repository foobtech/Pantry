import Foundation

/// One-line, human-readable text for errors shown in the UI.
public func describe(_ error: Error) -> String {
    if let e = error as? FetchError {
        switch e {
        case .notFound: return "no package index found"
        case .http(let code): return "HTTP \(code)"
        }
    }
    if let e = error as? DownloadError { return e.description }
    if let e = error as? DecompressError {
        switch e {
        case .unsupported: return "unsupported compression"
        case .badHeader, .failed: return "corrupt download"
        }
    }
    return (error as NSError).localizedDescription
}
