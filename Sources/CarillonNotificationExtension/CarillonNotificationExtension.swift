import Foundation
import UserNotifications

/// Retain the returned helper in your UNNotificationServiceExtension instance.
public final class CarillonNotificationExtension: NSObject, URLSessionDataDelegate {
  private let lock = NSLock()
  private let original: UNNotificationContent
  private var completion: ((UNNotificationContent) -> Void)?
  private var session: URLSession?
  private var timeout: DispatchWorkItem?
  private var bytes = Data()
  private var mime: String?
  private var sourceURL: URL?
  private static let maximumBytes = 10 * 1024 * 1024

  public static func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler completion: @escaping (UNNotificationContent) -> Void
  ) -> CarillonNotificationExtension {
    let helper = CarillonNotificationExtension(content: request.content, completion: completion)
    helper.start(configuration: .ephemeral)
    return helper
  }

  public static func serviceExtensionTimeWillExpire(_ helper: CarillonNotificationExtension?) {
    helper?.finish()
  }

  init(content: UNNotificationContent, completion: @escaping (UNNotificationContent) -> Void) {
    self.original = content
    self.completion = completion
  }

  func start(configuration: URLSessionConfiguration) {
    guard let stamp = original.userInfo["carillon"] as? [String: Any],
      let image = stamp["image"] as? String,
      let url = URL(string: image), url.scheme?.lowercased() == "https"
    else { finish(); return }
    sourceURL = url
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 20
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    self.session = session
    let timeout = DispatchWorkItem { [weak self] in self?.finish() }
    self.timeout = timeout
    DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)
    session.dataTask(with: url).resume()
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(request.url?.scheme?.lowercased() == "https" ? request : nil)
  }

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
      response.expectedContentLength <= Int64(Self.maximumBytes),
      response.mimeType == nil || response.mimeType!.lowercased().hasPrefix("image/")
    else { completionHandler(.cancel); finish(); return }
    mime = response.mimeType
    completionHandler(.allow)
  }

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    lock.lock()
    let tooLarge = bytes.count + data.count > Self.maximumBytes
    if !tooLarge && completion != nil { bytes.append(data) }
    lock.unlock()
    if tooLarge { finish() }
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard error == nil else { finish(); return }
    lock.lock()
    let data = bytes
    let active = completion != nil
    lock.unlock()
    guard active, !data.isEmpty,
      let content = original.mutableCopy() as? UNMutableNotificationContent
    else { finish(); return }
    do {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let file = directory.appendingPathComponent("image").appendingPathExtension(Self.fileExtension(mime: mime, url: sourceURL))
      try data.write(to: file)
      let attachment = try UNNotificationAttachment(identifier: "carillon-image", url: file)
      content.attachments = [attachment]
      finish(content)
    } catch { finish() }
  }

  static func fileExtension(mime: String?, url: URL?) -> String {
    switch mime?.lowercased() {
    case "image/jpeg": return "jpg"
    case "image/png": return "png"
    case "image/gif": return "gif"
    default:
      let suffix = url?.pathExtension.lowercased() ?? ""
      return ["jpg", "jpeg", "png", "gif"].contains(suffix) ? suffix : "jpg"
    }
  }

  func finish(_ content: UNNotificationContent? = nil) {
    lock.lock()
    let handler = completion
    completion = nil
    let session = self.session
    self.session = nil
    timeout?.cancel()
    timeout = nil
    bytes.removeAll()
    lock.unlock()
    session?.invalidateAndCancel()
    handler?(content ?? original)
  }
}
