//
//  RoomScanCaptureView.swift
//
//  A RoomPlan capture screen that saves everything to the app's local
//  Documents folder. There is no networking code in this file — nothing
//  is sent anywhere automatically. Getting the files off the device (to
//  your Mac, to run the converter) is a manual step you control: Finder
//  file sharing over USB, or AirDrop. See the README for both.
//
//  RoomCaptureView (Apple's own class, used below) already shows the
//  live camera feed with a real-time wireframe overlay of detected
//  walls/doors/windows/objects — that's the built-in RoomPlan scanning
//  UI. This file adds an explicit "● SCANNING" indicator plus live
//  wall/opening/object counts on top of it, so it's unambiguous that
//  it's actively working, not just showing a static camera preview.
//
//  Requires: iOS 16+, a LiDAR-equipped device (iPhone 12 Pro+/iPad Pro),
//  the RoomPlan framework, and camera usage permission.
//
//  Info.plist additions needed:
//   - NSCameraUsageDescription  (e.g. "Used to scan your room in 3D.")
//   - "Application supports iTunes file sharing" -> YES
//   - "Supports opening documents in place"       -> YES
//  Those two "file sharing" keys are what let you drag the saved .usdz/.json
//  off the device locally via Finder, with no server involved.
//

import SwiftUI
import RoomPlan
import WebKit

// MARK: - SwiftUI wrapper

struct RoomScanCaptureView: UIViewControllerRepresentable {
    @Binding var lastSavedFiles: (usdz: URL, json: URL)?
    @Binding var statusMessage: String
    @Binding var lastRoomJSONBase64: String?

    func makeUIViewController(context: Context) -> RoomCaptureViewController {
        let vc = RoomCaptureViewController()
        vc.onSaved = { usdz, json, base64 in
            self.lastSavedFiles = (usdz, json)
            self.lastRoomJSONBase64 = base64
            self.statusMessage = "Saved locally — nothing was uploaded."
        }
        vc.onStatus = { self.statusMessage = $0 }
        return vc
    }

    func updateUIViewController(_ uiViewController: RoomCaptureViewController, context: Context) {}
}

// MARK: - Capture controller

final class RoomCaptureViewController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {

    private var roomCaptureView: RoomCaptureView!
    private let sessionConfig = RoomCaptureSession.Configuration()

    private var isScanning = false
    private var recDot: UIView!
    private var recLabel: UILabel!
    private var liveCountsLabel: UILabel!
    private var startBtn: UIButton!
    private var stopBtn: UIButton!

    /// Called after a successful local save with (usdzURL, jsonURL, base64-encoded room JSON).
    var onSaved: ((URL, URL, String) -> Void)?
    /// Called with human-readable status updates for the UI.
    var onStatus: ((String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Check LiDAR/RoomPlan support up front rather than showing a
        // blank camera view with no explanation on unsupported hardware.
        guard RoomCaptureSession.isSupported else {
            onStatus?("This device doesn't support RoomPlan (LiDAR required — iPhone 12 Pro or later Pro model, or iPad Pro).")
            let label = UILabel()
            label.text = "RoomPlan isn't supported on this device.\nLiDAR (iPhone/iPad Pro) is required."
            label.textColor = .white
            label.numberOfLines = 0
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            ])
            return
        }

        // IMPORTANT: pin with Auto Layout constraints rather than setting
        // `.frame = view.bounds` here in viewDidLoad(). At this point
        // view.bounds can still be the pre-layout default size (sometimes
        // zero), which would silently size the camera view to nothing —
        // a common reason the live feed appears to not show up at all.
        roomCaptureView = RoomCaptureView(frame: .zero)
        roomCaptureView.translatesAutoresizingMaskIntoConstraints = false
        roomCaptureView.captureSession.delegate = self
        roomCaptureView.delegate = self
        view.addSubview(roomCaptureView)
        NSLayoutConstraint.activate([
            roomCaptureView.topAnchor.constraint(equalTo: view.topAnchor),
            roomCaptureView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            roomCaptureView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            roomCaptureView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        addScanningIndicator()
        addControls()
    }

    // MARK: Live "yes, this is actually scanning" feedback

    private func addScanningIndicator() {
        recDot = UIView()
        recDot.backgroundColor = .systemRed
        recDot.layer.cornerRadius = 5
        recDot.translatesAutoresizingMaskIntoConstraints = false
        recDot.isHidden = true

        recLabel = UILabel()
        recLabel.text = "SCANNING"
        recLabel.font = .boldSystemFont(ofSize: 13)
        recLabel.textColor = .white
        recLabel.isHidden = true

        liveCountsLabel = UILabel()
        liveCountsLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        liveCountsLabel.textColor = .white
        liveCountsLabel.text = "Walls: 0 · Openings: 0 · Objects: 0"
        liveCountsLabel.isHidden = true

        let dotStack = UIStackView(arrangedSubviews: [recDot, recLabel])
        dotStack.axis = .horizontal
        dotStack.spacing = 6
        dotStack.alignment = .center

        let stack = UIStackView(arrangedSubviews: [dotStack, liveCountsLabel])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        let bg = UIView()
        bg.backgroundColor = .black.withAlphaComponent(0.55)
        bg.layer.cornerRadius = 10
        bg.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stack)
        view.addSubview(bg)

        NSLayoutConstraint.activate([
            recDot.widthAnchor.constraint(equalToConstant: 10),
            recDot.heightAnchor.constraint(equalToConstant: 10),

            bg.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            bg.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.topAnchor.constraint(equalTo: bg.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -10),
        ])
    }

    private func setScanningIndicatorVisible(_ visible: Bool) {
        recDot.isHidden = !visible
        recLabel.isHidden = !visible
        liveCountsLabel.isHidden = !visible
        if visible { pulseRecDot() }
    }

    private func pulseRecDot() {
        guard isScanning else { return }
        UIView.animate(withDuration: 0.6, delay: 0, options: [.autoreverse], animations: {
            self.recDot.alpha = 0.15
        }, completion: { _ in
            self.recDot.alpha = 1.0
            if self.isScanning {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.pulseRecDot() }
            }
        })
    }

    // MARK: Start/stop controls

    private func addControls() {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        startBtn = UIButton(type: .system)
        startBtn.setTitle("Start Scan", for: .normal)
        startBtn.addTarget(self, action: #selector(startTapped), for: .touchUpInside)

        stopBtn = UIButton(type: .system)
        stopBtn.setTitle("Finish Scan", for: .normal)
        stopBtn.isEnabled = false
        stopBtn.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)

        [startBtn, stopBtn].forEach { $0.backgroundColor = .black.withAlphaComponent(0.6) }
        [startBtn, stopBtn].forEach { $0.setTitleColor(.white, for: .normal) }
        [startBtn, stopBtn].forEach { $0.layer.cornerRadius = 10 }
        [startBtn, stopBtn].forEach { $0.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16) }

        stack.addArrangedSubview(startBtn)
        stack.addArrangedSubview(stopBtn)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    @objc private func startTapped() {
        onStatus?("Scanning… walk the room slowly, keep it in frame.")
        isScanning = true
        setScanningIndicatorVisible(true)
        startBtn.isEnabled = false
        stopBtn.isEnabled = true
        roomCaptureView.captureSession.run(configuration: sessionConfig)
    }

    @objc private func stopTapped() {
        onStatus?("Processing scan…")
        isScanning = false
        setScanningIndicatorVisible(false)
        startBtn.isEnabled = true
        stopBtn.isEnabled = false
        roomCaptureView.captureSession.stop()
    }

    // MARK: RoomCaptureSessionDelegate — live progress while scanning

    /// Fires repeatedly *during* an active scan with the in-progress room
    /// estimate. This is the actual proof-of-life: if these numbers climb
    /// as you move the phone, it's genuinely detecting your room, not just
    /// showing an idle camera preview.
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        DispatchQueue.main.async {
            let openings = room.doors.count + room.windows.count
            self.liveCountsLabel.text = "Walls: \(room.walls.count) · Openings: \(openings) · Objects: \(room.objects.count)"
        }
    }

    func captureSession(_ session: RoomCaptureSession, didFailWith error: Error) {
        onStatus?("Scan session error: \(error.localizedDescription)")
        isScanning = false
        setScanningIndicatorVisible(false)
    }

    // MARK: RoomCaptureViewDelegate

    /// Called once RoomPlan has finished post-processing the raw capture
    /// into a clean CapturedRoom (walls, doors, windows, objects, dimensions).
    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error = error {
            onStatus?("Scan failed: \(error.localizedDescription)")
            return
        }
        saveLocally(room: processedResult)
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        return true // let RoomPlan run its normal on-device post-processing
    }

    // MARK: Local-only save

    private func saveLocally(room: CapturedRoom) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = Int(Date().timeIntervalSince1970)
        let usdzURL = docs.appendingPathComponent("RoomScan-\(stamp).usdz")
        let jsonURL = docs.appendingPathComponent("RoomScan-\(stamp).json")

        do {
            // 3D model export (walls/openings/objects as geometry), stays on-device.
            try room.export(to: usdzURL, exportOptions: .model)

            // Structured metadata export (positions, dimensions, categories for
            // every wall/door/window/object) — this is what the site's Scan
            // tab parses to auto-populate real furniture/wall placement.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(room)
            try data.write(to: jsonURL, options: .atomic)

            // Base64 of the same JSON, for handing straight to the embedded
            // site's window.importScanJSONBase64() — no file round-trip needed.
            let base64 = data.base64EncodedString()

            onSaved?(usdzURL, jsonURL, base64)
            onStatus?("Saved to Documents:\n\(usdzURL.lastPathComponent)\n\(jsonURL.lastPathComponent)")
        } catch {
            onStatus?("Local save failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Embedded rat-monitoring site (WKWebView) + native<->JS bridge

/// Coordinates page-load state, JS injection, and messages coming back
/// from the page (window.webkit.messageHandlers.nativeBridge.postMessage).
final class RatSiteCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    weak var webView: WKWebView?
    var onStatus: ((String) -> Void)?
    var onLoadError: ((String) -> Void)?
    private var isLoaded = false
    private var pendingBase64: String?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        onStatus?("Site loaded.")
        flushPending()
    }

    // Covers failures once content started streaming in.
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onLoadError?("Page failed to load: \(error.localizedDescription)")
    }

    // Covers failures *before* content started arriving — e.g. can't reach
    // the CDN Three.js loads from, or the local file couldn't be opened.
    // This is the callback most likely to fire for a "blank page" symptom.
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onLoadError?("Couldn't start loading the page: \(error.localizedDescription)\n\nIf this mentions the network, the device needs an internet connection at least once — the site loads Three.js from a CDN.")
    }

    /// Queues (or immediately sends, if the page has already finished
    /// loading) a base64-encoded RoomPlan JSON blob to hand to the site.
    func inject(base64: String) {
        pendingBase64 = base64
        if isLoaded { flushPending() }
    }

    private func flushPending() {
        guard let b64 = pendingBase64, let webView = webView else { return }
        pendingBase64 = nil
        // Base64 only ever contains [A-Za-z0-9+/=], so it's always safe to
        // drop straight into a single-quoted JS string literal — no escaping
        // concerns even for a very large scan.
        let js = "window.importScanJSONBase64 ? window.importScanJSONBase64('\(b64)') : 'no-bridge-fn';"
        webView.evaluateJavaScript(js) { [weak self] result, error in
            if let error = error {
                self?.onLoadError?("Import into site failed: \(error.localizedDescription)")
            } else if let result = result as? String, result == "no-bridge-fn" {
                self?.onLoadError?("Page loaded, but importScanJSONBase64 isn't defined — the site's JavaScript likely failed to fully initialize (check Safari Web Inspector).")
            }
        }
    }

    // Messages posted from the page via:
    //   window.webkit.messageHandlers.nativeBridge.postMessage({...})
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "scanImported" {
            let walls = body["walls"] as? Int ?? 0
            let objects = body["objects"] as? Int ?? 0
            onStatus?("Loaded into Rat Monitor — \(walls) walls, \(objects) objects placed.")
        }
    }
}

/// The raw WKWebView wrapper. Prefer using `RatSiteWebView` (below) instead
/// of this directly — it adds a visible error banner, since failures here
/// otherwise show up as nothing but a blank screen with no explanation.
private struct RatSiteWebViewRepresentable: UIViewRepresentable {
    @Binding var pendingBase64: String?
    @Binding var statusMessage: String
    @Binding var loadError: String?
    let reloadToken: Int

    func makeCoordinator() -> RatSiteCoordinator {
        let c = RatSiteCoordinator()
        c.onStatus = { msg in DispatchQueue.main.async { self.statusMessage = msg } }
        c.onLoadError = { msg in DispatchQueue.main.async { self.loadError = msg } }
        return c
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "nativeBridge")
        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        // Lets Safari's Develop menu (Mac, device plugged in) attach to this
        // specific WKWebView for real console errors. iOS 16.4+ only.
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }

        loadSite(webView, context: context)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.webView !== webView { context.coordinator.webView = webView }
        if let b64 = pendingBase64 {
            context.coordinator.inject(base64: b64)
            DispatchQueue.main.async { self.pendingBase64 = nil }
        }
    }

    private func loadSite(_ webView: WKWebView, context: Context) {
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            DispatchQueue.main.async {
                self.loadError = "index.html isn't in the app bundle. In Xcode: select index.html → File Inspector (right sidebar) → Target Membership → check your app target. Then check Build Phases → Copy Bundle Resources includes it."
            }
        }
    }
}

/// Public entry point — the WKWebView plus a visible error banner and a
/// reload button, so a failure is something you can actually see and act
/// on instead of just a blank screen.
struct RatSiteWebView: View {
    @Binding var pendingBase64: String?
    @Binding var statusMessage: String
    @State private var loadError: String?
    @State private var reloadToken = 0

    var body: some View {
        ZStack(alignment: .top) {
            RatSiteWebViewRepresentable(
                pendingBase64: $pendingBase64,
                statusMessage: $statusMessage,
                loadError: $loadError,
                reloadToken: reloadToken
            )
            .id(reloadToken) // bumping this forces the WKWebView to be recreated on Reload

            if let error = loadError {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rat Monitor didn't load").font(.headline)
                    Text(error).font(.footnote)
                    Button("Reload") {
                        loadError = nil
                        reloadToken += 1
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.regularMaterial)
                .cornerRadius(12)
                .padding()
            }
        }
    }
}

// MARK: - Example host screen

struct ContentView: View {
    @State private var lastSavedFiles: (usdz: URL, json: URL)?
    @State private var statusMessage = "Ready to scan."
    @State private var lastRoomJSONBase64: String?
    @State private var pendingInjectBase64: String?
    @State private var showRatSite = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RoomScanCaptureView(
                    lastSavedFiles: $lastSavedFiles,
                    statusMessage: $statusMessage,
                    lastRoomJSONBase64: $lastRoomJSONBase64
                )
                VStack(alignment: .leading, spacing: 10) {
                    Text(statusMessage).font(.footnote)
                    if let files = lastSavedFiles {
                        Button {
                            pendingInjectBase64 = lastRoomJSONBase64
                            showRatSite = true
                        } label: {
                            Label("🐀 View in Rat Monitor", systemImage: "cube.transparent")
                        }
                        .buttonStyle(.borderedProminent)

                        // Direct share sheet — the reliable way to get the files off
                        // the device if you also want them on your Mac. AirDrop or
                        // "Save to Files". Bypasses hunting through the Files app.
                        ShareLink(items: [files.usdz, files.json]) {
                            Label("Share Scan Files (.usdz + .json)", systemImage: "square.and.arrow.up")
                        }

                        Text("Files also live in this app's local Documents folder — Files app → Browse → On My iPhone/iPad → [this app] — if file sharing is enabled in Info.plist and you've rebuilt since adding those keys.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationDestination(isPresented: $showRatSite) {
                RatSiteWebView(pendingBase64: $pendingInjectBase64, statusMessage: $statusMessage)
                    .navigationTitle("Rat Monitor")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

