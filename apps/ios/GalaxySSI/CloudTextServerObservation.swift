import Foundation

struct CloudTextServerAdvertisement: Equatable, Sendable {
  let responseURL: String
  let server: String?
}

final class CloudTextServerObservation: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var redirected = false
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    lock.lock(); redirected = true; lock.unlock()
    completionHandler(request)
  }
  func advertisement(response: HTTPURLResponse) -> CloudTextServerAdvertisement? {
    lock.lock(); defer { lock.unlock() }
    guard !redirected, (200...299).contains(response.statusCode), let url = response.url else { return nil }
    return .init(responseURL: url.absoluteString, server: response.value(forHTTPHeaderField: "Server"))
  }
}
