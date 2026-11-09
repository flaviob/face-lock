// FaceLock: locks the Mac when no face is seen by the webcam for N seconds.
// Unlock with Touch ID / password as usual.
import AppKit
import AVFoundation
import Vision
import ServiceManagement

// MARK: - Lock screen (private login.framework call, same as Ctrl+Cmd+Q)
func lockScreen() {
    let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
    if let h = dlopen(path, RTLD_NOW), let sym = dlsym(h, "SACLockScreenImmediate") {
        typealias Fn = @convention(c) () -> Int32
        _ = unsafeBitCast(sym, to: Fn.self)()
    } else {
        // Fallback: sleep the display (locks if "require password immediately" is on)
        let p = Process(); p.launchPath = "/usr/bin/pmset"; p.arguments = ["displaysleepnow"]; try? p.run()
    }
}

/// Seconds since last keyboard/mouse/trackpad input.
func secondsSinceInput() -> Double {
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
}

// MARK: - Camera face watcher
final class FaceWatcher: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "facelock.camera")
    private var lastCheck = Date.distantPast
    var lastFaceSeen = Date()
    var cameraError: String?

    func configure() {
        session.sessionPreset = .low
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { cameraError = "No camera"; return }
        session.addInput(input)
        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(out) { session.addOutput(out) }
    }

    func start() { lastFaceSeen = Date(); queue.async { if !self.session.isRunning { self.session.startRunning() } } }
    func stop()  { queue.async { if self.session.isRunning { self.session.stopRunning() } } }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard Date().timeIntervalSince(lastCheck) >= 1 else { return }   // 1 check per second
        lastCheck = Date()
        guard let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
        let req = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pixels, options: [:]).perform([req])
        if let faces = req.results, !faces.isEmpty {
            DispatchQueue.main.async { self.lastFaceSeen = Date() }
        }
    }
}

// MARK: - App / menu bar
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let watcher = FaceWatcher()
    var statusItem: NSStatusItem!
    var timer: Timer?
    var screenLocked = false
    let delays = [10, 20, 30, 60, 120, 300]

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enabled") }
    }
    var delay: Int {
        get { let d = UserDefaults.standard.integer(forKey: "delay"); return d == 0 ? 30 : d }
        set { UserDefaults.standard.set(newValue, forKey: "delay") }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu

        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async {
                if ok { self.watcher.configure() } else { self.watcher.cameraError = "Camera access denied" }
                self.applyState()
            }
        }

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            self.screenLocked = true; self.applyState()
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            self.screenLocked = false; self.applyState()
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in self.watcher.stop() }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in self.applyState() }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in self.tick() }
        applyState()
    }

    /// Camera runs only when enabled and the screen is unlocked.
    func applyState() {
        if enabled && !screenLocked && watcher.cameraError == nil { watcher.start() } else { watcher.stop() }
        updateIcon()
    }

    func tick() {
        guard enabled, !screenLocked, watcher.cameraError == nil else { return }
        let noFace = Date().timeIntervalSince(watcher.lastFaceSeen)
        // Typing/mousing counts as "present", so a bad camera angle never locks you out mid-work.
        if noFace >= Double(delay) && secondsSinceInput() >= Double(delay) {
            screenLocked = true
            watcher.stop()
            lockScreen()
        }
        updateIcon()
    }

    func updateIcon() {
        let name: String
        if watcher.cameraError != nil { name = "exclamationmark.triangle" }
        else if !enabled { name = "eye.slash" }
        else { name = Date().timeIntervalSince(watcher.lastFaceSeen) < 3 ? "eye" : "eye.trianglebadge.exclamationmark" }
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "FaceLock")
    }

    // Rebuild menu each time it opens
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status: String
        if let err = watcher.cameraError { status = err }
        else if !enabled { status = "Paused" }
        else { status = "Face seen \(Int(Date().timeIntervalSince(watcher.lastFaceSeen)))s ago" }
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())

        let toggle = menu.addItem(withTitle: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "e")
        toggle.target = self; toggle.state = enabled ? .on : .off

        let sub = NSMenu()
        for d in delays {
            let label = d < 60 ? "\(d) seconds" : "\(d / 60) min"
            let it = sub.addItem(withTitle: label, action: #selector(setDelay(_:)), keyEquivalent: "")
            it.target = self; it.tag = d; it.state = d == delay ? .on : .off
        }
        let delayItem = menu.addItem(withTitle: "Lock after", action: nil, keyEquivalent: "")
        menu.setSubmenu(sub, for: delayItem)

        let login = menu.addItem(withTitle: "Start at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self; login.state = SMAppService.mainApp.status == .enabled ? .on : .off

        menu.addItem(withTitle: "Lock now", action: #selector(lockNow), keyEquivalent: "l").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit FaceLock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc func toggleEnabled() { enabled.toggle(); applyState() }
    @objc func setDelay(_ s: NSMenuItem) { delay = s.tag; watcher.lastFaceSeen = Date() }
    @objc func lockNow() { lockScreen() }
    @objc func toggleLogin() {
        let svc = SMAppService.mainApp
        if svc.status == .enabled { try? svc.unregister() } else { try? svc.register() }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
