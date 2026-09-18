import Carillon
import Combine
import SwiftUI

/// The test bench.
///
/// A tool, not a product: every control here exists to exercise one call of the
/// SDK against a real server and show what came back. It is deliberately plain —
/// anything that looked designed would be a claim about how the SDK should be
/// presented, which is the customer's decision and not ours.

enum Defaults {
  static let endpointKey = "bench.endpoint"
  static let keyKey = "bench.key"
  static let endpoint = "https://api-staging.carillon.dev"
}

/// Holds what the bench shows, and nothing the SDK needs.
final class Bench: ObservableObject {
  static let shared = Bench()

  @Published private(set) var lines: [String] = []
  @Published var info: DebugInfo?
  @Published var lastPermission: String?

  private init() {}

  /// Configures from whatever the fields currently hold.
  ///
  /// Called at launch and again from the Apply button, so switching endpoint or
  /// key is a thing that can be done on the device rather than by rebuilding.
  func configureSdk() {
    let defaults = UserDefaults.standard
    let endpoint = defaults.string(forKey: Defaults.endpointKey) ?? Defaults.endpoint
    let key = defaults.string(forKey: Defaults.keyKey) ?? ""

    #if DEBUG
      // Every line the SDK writes, mirrored into the pane below. It already goes
      // to the platform logger; this is the copy a device in someone's hand can
      // show without Console attached.
      Carillon.onDebugLine = { [weak self] line in
        self?.log(line)
      }
    #endif

    Carillon.onOpened = { [weak self] notification in
      self?.log("opened \(notification.deliveryId)")
      self?.refresh()
    }

    Carillon.configure(key: key, endpoint: endpoint, debug: true)
    log("configured for \(endpoint) with \(key.isEmpty ? "no key" : key)")
    log("registering silently — no prompt is shown; watch device_id appear below")

    // The token arrives on the delegate a moment later, and the registration
    // that follows it a moment after that. Re-read on a delay so that the panel
    // shows the device the server named rather than the emptiness before it.
    refresh()
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.refresh() }
  }

  func log(_ line: String) {
    DispatchQueue.main.async {
      self.lines.append(line)
      // A bench that grows without bound eventually janks on its own history.
      if self.lines.count > 500 { self.lines.removeFirst(self.lines.count - 500) }
    }
  }

  func refresh() {
    DispatchQueue.main.async {
      self.info = Carillon.debugInfo()
    }
  }

  func requestPermission() {
    Task {
      let permission = await Carillon.requestPermission()
      await MainActor.run { self.lastPermission = permission.rawValue }
      log("requestPermission() → \(permission.rawValue)")
      refresh()
    }
  }
}

struct ContentView: View {
  @AppStorage(Defaults.endpointKey) private var endpoint = Defaults.endpoint
  @AppStorage(Defaults.keyKey) private var key = ""

  @StateObject private var bench = Bench.shared

  @State private var externalId = ""
  @State private var tagName = ""
  @State private var tagValue = ""

  var body: some View {
    NavigationView {
      Form {
        connection
        registration
        identity
        tags
        optIn
        debugInfo
        log
      }
      .navigationTitle("Carillon bench")
    }
    .navigationViewStyle(.stack)
    .onAppear { bench.refresh() }
  }

  private var connection: some View {
    Section("Connection") {
      TextField("Endpoint", text: $endpoint)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)
        .keyboardType(.URL)

      TextField("Mobile key", text: $key)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)
        .font(.system(.body, design: .monospaced))

      Button("Apply") { bench.configureSdk() }
    }
  }

  private var registration: some View {
    Section("Permission") {
      // Registration is not here on purpose: Apply did it, without prompting.
      // What this section asks for is display, which is a different question.
      Text("Configure registers this device on its own. This asks whether iOS may show anything.")
        .font(.footnote)
        .foregroundColor(.secondary)

      Button("requestPermission()") { bench.requestPermission() }

      if let permission = bench.lastPermission {
        LabeledLine(name: "permission", value: permission)
      }
    }
  }

  private var identity: some View {
    Section("Identity") {
      TextField("external_id", text: $externalId)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)

      Button("identify()") {
        Carillon.identify(externalId)
        bench.log("identify(\(externalId))")
        bench.refresh()
      }
      .disabled(externalId.isEmpty)

      Button("clearIdentity()") {
        Carillon.clearIdentity()
        bench.log("clearIdentity()")
        bench.refresh()
      }
    }
  }

  private var tags: some View {
    Section("Tags") {
      HStack {
        TextField("name", text: $tagName)
          .textInputAutocapitalization(.never)
          .disableAutocorrection(true)
        Text(":")
        TextField("value", text: $tagValue)
          .textInputAutocapitalization(.never)
          .disableAutocorrection(true)
      }

      Button("setTags()") {
        Carillon.setTags([tagName: .string(tagValue)])
        bench.log("setTags([\(tagName): \(tagValue)])")
        bench.refresh()
      }
      .disabled(tagName.isEmpty)

      Button("removeTag()") {
        Carillon.removeTag(tagName)
        bench.log("removeTag(\(tagName))")
        bench.refresh()
      }
    }
  }

  private var optIn: some View {
    Section("Opt in") {
      Button("optIn()") {
        Carillon.optIn()
        bench.log("optIn()")
        bench.refresh()
      }

      Button("optOut()") {
        Carillon.optOut()
        bench.log("optOut()")
        bench.refresh()
      }
    }
  }

  private var debugInfo: some View {
    Section("debugInfo()") {
      Button("refresh") { bench.refresh() }

      if let info = bench.info {
        Text(info.description)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
      }
    }
  }

  private var log: some View {
    Section("Log") {
      // Newest first: on a bench the interesting line is always the last thing
      // that happened, and scrolling to find it is the one thing a tool must not
      // ask for.
      ForEach(Array(bench.lines.reversed().enumerated()), id: \.offset) { _, line in
        Text(line)
          .font(.system(.caption2, design: .monospaced))
          .textSelection(.enabled)
      }
    }
  }
}

private struct LabeledLine: View {
  let name: String
  let value: String

  var body: some View {
    // Bold label, value on its own line: tokens and keys are long, and a
    // side-by-side layout wraps them into an unreadable interleave.
    VStack(alignment: .leading, spacing: 2) {
      Text(name)
        .font(.subheadline.bold())
      Text(value)
        .font(.system(.footnote, design: .monospaced))
        .foregroundColor(.secondary)
        .textSelection(.enabled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 2)
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
