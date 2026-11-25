import Foundation

final class AgentRemoteImageTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  struct Response { var status: Int; var location: String?; var data: Data }
  private let url: URL
  private let timeout: TimeInterval
  private let followsRedirects: Bool
  private let lock = NSLock()
  private var session: URLSession?
  private var task: URLSessionDataTask?
  private var waiter: CheckedContinuation<Response, Error>?
  private var outcome: Result<Response, Error>?
  private var body = Data()
  private var status = 0

  init(url: URL, timeout: TimeInterval, followsRedirects: Bool = false) {
    self.url = url
    self.timeout = timeout
    self.followsRedirects = followsRedirects
    super.init()
  }

  func run() async throws -> Response {
    try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { continuation in
        lock.lock()
        if let outcome { lock.unlock(); continuation.resume(with: outcome); return }
        waiter = continuation
        let config = followsRedirects ? URLSessionConfiguration.default : .ephemeral
        if !followsRedirects {
          config.httpShouldSetCookies = false
          config.httpCookieAcceptPolicy = .never
          config.httpCookieStorage = nil
          config.urlCredentialStorage = nil
          config.urlCache = nil
          config.requestCachePolicy = .reloadIgnoringLocalCacheData
        }
        config.timeoutIntervalForRequest = min(20, max(0.1, timeout))
        config.timeoutIntervalForResource = max(0.1, timeout)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        var request = URLRequest(url: url)
        request.timeoutInterval = min(20, max(0.1, timeout))
        request.cachePolicy = followsRedirects ? .returnCacheDataElseLoad : .reloadIgnoringLocalCacheData
        request.setValue("GalaxySSI-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let task = session.dataTask(with: request)
        self.session = session
        self.task = task
        lock.unlock()
        task.resume()
      }
    }, onCancel: { self.finish(.failure(CancellationError())) })
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    if followsRedirects { completionHandler(request) }
    else {
      completionHandler(nil)
      finish(.success(Response(status: response.statusCode, location: response.value(forHTTPHeaderField: "Location"), data: Data())))
    }
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                  completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      completionHandler(.cancel); finish(.failure(AgentMarkdownImageFailure.invalidResponse)); return
    }
    guard http.expectedContentLength < 0 || http.expectedContentLength <= Int64(AgentMarkdownImageStore.maximumBytes) else {
      completionHandler(.cancel); finish(.failure(AgentMarkdownImageFailure.tooLarge)); return
    }
    lock.lock()
    let closed = outcome != nil
    status = http.statusCode
    lock.unlock()
    completionHandler(closed ? .cancel : .allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    lock.lock()
    guard outcome == nil else { lock.unlock(); return }
    guard data.count <= AgentMarkdownImageStore.maximumBytes - body.count else {
      lock.unlock(); finish(.failure(AgentMarkdownImageFailure.tooLarge)); return
    }
    body.append(data)
    lock.unlock()
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error { finish(.failure(error)); return }
    lock.lock()
    let response = Response(status: status, location: nil, data: body)
    lock.unlock()
    if (200..<300).contains(response.status) { finish(.success(response)) }
    else { finish(.failure(AgentMarkdownImageFailure.invalidResponse)) }
  }

  private func finish(_ result: Result<Response, Error>) {
    lock.lock()
    guard outcome == nil else { lock.unlock(); return }
    outcome = result
    let waiter = self.waiter
    self.waiter = nil
    let task = self.task
    let session = self.session
    self.task = nil
    self.session = nil
    body = Data()
    lock.unlock()
    task?.cancel()
    session?.invalidateAndCancel()
    waiter?.resume(with: result)
  }
}
