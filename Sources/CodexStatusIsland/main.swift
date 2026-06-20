import AppKit
import Foundation

enum CodexStatus: Equatable {
    case working(reason: String)
    case complete(reason: String)
    case needsApproval(reason: String)

    var title: String {
        switch self {
        case .working:
            return "Codex 正在工作"
        case .complete:
            return "Codex 工作完成"
        case .needsApproval:
            return "Codex 等待批准"
        }
    }

    var detail: String {
        switch self {
        case .working(let reason), .complete(let reason), .needsApproval(let reason):
            return reason
        }
    }

    var color: NSColor {
        switch self {
        case .working:
            return NSColor.systemRed
        case .complete:
            return NSColor.systemGreen
        case .needsApproval:
            return NSColor.systemYellow
        }
    }

    var menuIcon: String {
        switch self {
        case .working:
            return "🔴"
        case .complete:
            return "🟢"
        case .needsApproval:
            return "🟡"
        }
    }
}

final class CodexStatusMonitor {
    private let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    private let activeTurnWindow: TimeInterval = 60 * 60
    private let recentlyCompletedWindow: TimeInterval = 45
    private let approvalWindow: TimeInterval = 15 * 60

    func currentStatus() -> CodexStatus? {
        latestSessionStatus()
    }

    private func latestSessionStatus() -> CodexStatus? {
        for event in recentSessionEvents(limit: 120_000).reversed() {
            if event.isCompletionSignal {
                if event.age < recentlyCompletedWindow {
                    return .complete(reason: "刚刚完成")
                }
                return nil
            }

            if event.isApprovalRequest, event.age < approvalWindow {
                return .needsApproval(reason: "需要你批准权限")
            }

            if event.isWorkingSignal, event.age < activeTurnWindow {
                return .working(reason: "会话正在运行")
            }

            if event.kind == "user_message", event.age < activeTurnWindow {
                return .working(reason: "会话正在运行")
            }

            if event.kind == "turn_context", event.age < activeTurnWindow {
                return .working(reason: "会话正在运行")
            }

            if event.kind == "response_item", event.age < activeTurnWindow {
                return .working(reason: "会话正在运行")
            }

            if event.kind == "event_msg", event.age < activeTurnWindow {
                continue
            }

            return nil
        }

        return nil
    }

    private func recentSessionEvents(limit: Int) -> [SessionEvent] {
        guard let latest = latestSessionFile() else {
            return []
        }

        guard let handle = try? FileHandle(forReadingFrom: latest) else {
            return []
        }

        defer {
            try? handle.close()
        }

        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(limit) ? size - UInt64(limit) : 0
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""

        return text
            .split(separator: "\n")
            .compactMap { SessionEvent(jsonLine: String($0)) }
    }

    private func latestSessionFile() -> URL? {
        let sessionsDirectory = homeDirectory.appendingPathComponent(".codex/sessions")
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var candidate: (url: URL, date: Date)?
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate else {
                continue
            }

            if candidate == nil || modified > candidate!.date {
                candidate = (url, modified)
            }
        }

        return candidate?.url
    }

}

struct SessionEvent {
    let kind: String
    let age: TimeInterval
    let payload: [String: Any]?

    var payloadType: String? {
        payload?["type"] as? String
    }

    var phase: String? {
        payload?["phase"] as? String
    }

    var isCompletionSignal: Bool {
        if kind == "event_msg", payloadType == "task_complete" {
            return true
        }

        if kind == "response_item",
           payloadType == "message",
           phase == "final_answer" {
            return true
        }

        if kind == "event_msg",
           payloadType == "agent_message",
           phase == "final_answer" {
            return true
        }

        return false
    }

    var isWorkingSignal: Bool {
        if kind == "event_msg", payloadType == "task_started" {
            return true
        }

        guard kind == "response_item" else {
            return false
        }

        let workingPayloadTypes = [
            "reasoning",
            "function_call",
            "function_call_output",
            "custom_tool_call",
            "custom_tool_call_output"
        ]

        if let payloadType, workingPayloadTypes.contains(payloadType) {
            return true
        }

        if payloadType == "message", phase == "commentary" {
            return true
        }

        return false
    }

    var isApprovalRequest: Bool {
        guard kind == "response_item",
              payloadType == "function_call",
              let arguments = payload?["arguments"] as? String else {
            return false
        }

        let normalized = arguments.lowercased()
        return normalized.contains("\"sandbox_permissions\"")
            || normalized.contains("require_escalated")
            || normalized.contains("\"approval_policy\"")
    }

    init?(jsonLine: String) {
        guard let data = jsonLine.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestampText = object["timestamp"] as? String,
              let date = ISO8601DateFormatter.codex.date(from: timestampText),
              let kind = object["type"] as? String else {
            return nil
        }

        self.kind = kind
        self.age = Date().timeIntervalSince(date)
        self.payload = object["payload"] as? [String: Any]
    }
}

extension ISO8601DateFormatter {
    static let codex: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

final class LaunchAgentInstaller {
    private let label = "local.codex.status-island"

    func installIfRunningFromAppBundle() {
        _ = install()
    }

    func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    @discardableResult
    func install() -> Bool {
        guard Bundle.main.bundlePath.hasSuffix(".app"),
              let executablePath = Bundle.main.executablePath else {
            return false
        }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(xmlEscaped(executablePath))</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """

        do {
            try FileManager.default.createDirectory(
                at: launchAgentsDirectory,
                withIntermediateDirectories: true
            )

            let existing = try? String(contentsOf: plistURL, encoding: .utf8)
            if existing != plist {
                try plist.write(to: plistURL, atomically: true, encoding: .utf8)
            }

            _ = run("/bin/launchctl", arguments: ["enable", "gui/\(getuid())/\(label)"])
            return true
        } catch {
            NSLog("Red Light could not install LaunchAgent: \(error)")
            return false
        }
    }

    @discardableResult
    func uninstall() -> Bool {
        _ = run("/bin/launchctl", arguments: ["disable", "gui/\(getuid())/\(label)"])

        do {
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
            return true
        } catch {
            NSLog("Red Light could not remove LaunchAgent: \(error)")
            return false
        }
    }

    private var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    private var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(label).plist")
    }

    private func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func run(_ launchPath: String, arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return false
        }

        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}

final class IslandView: NSView {
    private let dot = NSView(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "Codex 工作完成")
    private let detailLabel = NSTextField(labelWithString: "正在检测")
    private let pulseLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        layer?.cornerRadius = 28
        layer?.cornerCurve = .continuous
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.28
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -4)

        setupDot()
        setupLabels()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        dot.frame = CGRect(x: 22, y: bounds.midY - 7, width: 14, height: 14)
        dot.layer?.cornerRadius = 7

        titleLabel.frame = CGRect(x: 48, y: 27, width: bounds.width - 70, height: 18)
        detailLabel.frame = CGRect(x: 48, y: 10, width: bounds.width - 70, height: 16)
    }

    func apply(_ status: CodexStatus) {
        titleLabel.stringValue = status.title
        detailLabel.stringValue = status.detail
        dot.layer?.backgroundColor = status.color.cgColor
        pulseLayer.fillColor = status.color.withAlphaComponent(0.22).cgColor

        if case .working = status {
            startPulse()
        } else if case .needsApproval = status {
            startPulse(duration: 0.85)
        } else {
            stopPulse()
        }
    }

    private func setupDot() {
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        dot.layer?.cornerRadius = 7
        addSubview(dot)

        pulseLayer.path = CGPath(ellipseIn: CGRect(x: -5, y: -5, width: 24, height: 24), transform: nil)
        dot.layer?.addSublayer(pulseLayer)
    }

    private func setupLabels() {
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        detailLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1

        addSubview(titleLabel)
        addSubview(detailLabel)
    }

    private func startPulse(duration: CFTimeInterval = 1.25) {
        guard pulseLayer.animation(forKey: "pulse") == nil else {
            return
        }

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.78
        scale.toValue = 1.75

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.85
        opacity.toValue = 0

        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.duration = duration
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)

        pulseLayer.add(group, forKey: "pulse")
    }

    private func stopPulse() {
        pulseLayer.removeAnimation(forKey: "pulse")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = CodexStatusMonitor()
    private let launchAgentInstaller = LaunchAgentInstaller()
    private let islandView = IslandView(frame: CGRect(x: 0, y: 0, width: 250, height: 58))
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "正在检测 Codex", action: nil, keyEquivalent: "")
    private lazy var launchAtLoginMenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "开机启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        item.target = self
        return item
    }()
    private var timer: Timer?
    private var lastStatus: CodexStatus?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        launchAgentInstaller.installIfRunningFromAppBundle()
        createStatusItem()
        createPanel()
        updateStatus()

        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⚪️"
        item.button?.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        statusMenu.addItem(statusMenuItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(launchAtLoginMenuItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(
            title: "退出红绿灯",
            action: #selector(quit),
            keyEquivalent: "q"
        ))
        statusMenu.items.last?.target = self
        item.menu = statusMenu

        statusItem = item
        updateLaunchAtLoginMenuItem()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        if launchAgentInstaller.isInstalled() {
            _ = launchAgentInstaller.uninstall()
        } else {
            _ = launchAgentInstaller.install()
        }

        updateLaunchAtLoginMenuItem()
    }

    private func updateLaunchAtLoginMenuItem() {
        launchAtLoginMenuItem.state = launchAgentInstaller.isInstalled() ? .on : .off
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 250, height: 58),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.contentView = islandView

        self.panel = panel
        positionPanel()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged() {
        positionPanel()
    }

    private func positionPanel() {
        guard let panel,
              let screen = screenForIsland() else {
            return
        }

        let frame = screen.frame
        let x = frame.midX - panel.frame.width / 2
        let y = frame.maxY - panel.frame.height - 2
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func screenForIsland() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    private func updateStatus() {
        guard let status = monitor.currentStatus() else {
            if lastStatus != nil {
                panel?.orderOut(nil)
                lastStatus = nil
            }
            updateStatusItem(nil)
            return
        }

        if status != lastStatus {
            islandView.apply(status)
            lastStatus = status
        }
        updateStatusItem(status)
        positionPanel()
        panel?.orderFrontRegardless()
    }

    private func updateStatusItem(_ status: CodexStatus?) {
        guard let button = statusItem?.button else {
            return
        }

        guard let status else {
            button.title = "⚪️"
            statusMenuItem.title = "Codex 没有会话活动"
            updateLaunchAtLoginMenuItem()
            return
        }

        button.title = status.menuIcon
        statusMenuItem.title = "\(status.title)：\(status.detail)"
        updateLaunchAtLoginMenuItem()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
