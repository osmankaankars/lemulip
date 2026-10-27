#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LemulipCore

struct ActivityItem: Identifiable {
    typealias State = ConversionJobState
    let id = UUID()
    let operation: FileOperation
    let inputs: [URL]
    let createdAt = Date()
    var state: State = .waiting
    var outputs: [URL] = []
    var message: String = ""
    var progress: ConversionProgress?
    var retryRequest: ConversionRequest?
}

@MainActor
final class AppController: NSObject, ObservableObject, NSApplicationDelegate {
    @Published var files: [URL] = []
    @Published var mode: WheelMode = .convert
    @Published var section = "workspace"
    @Published var activity: [ActivityItem] = []
    @Published var pendingOperation: FileOperation?
    @Published var alertMessage: String?
    @Published var language = UserDefaults.standard.string(forKey: "language") ?? (Locale.preferredLanguages.first?.hasPrefix("tr") == true ? "tr" : "en") {
        didSet {
            UserDefaults.standard.set(language, forKey: "language")
            rebuildStatusMenu()
            wheel.refreshAppearance()
        }
    }
    @Published var theme = AppTheme.saved {
        didSet {
            guard theme != oldValue else { return }
            UserDefaults.standard.set(theme.rawValue, forKey: AppTheme.preferenceKey)
            applyThemeAppearance()
        }
    }
    @Published var wheelEnabled = UserDefaults.standard.object(forKey: "wheelEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(wheelEnabled, forKey: "wheelEnabled"); wheel.enabled = wheelEnabled; rebuildStatusMenu() }
    }
    @Published var revealWhenFinished = UserDefaults.standard.object(forKey: "revealWhenFinished") as? Bool ?? false {
        didSet { UserDefaults.standard.set(revealWhenFinished, forKey: "revealWhenFinished") }
    }
    @Published var outputAlongsideOriginal = UserDefaults.standard.object(forKey: "outputAlongsideOriginal") as? Bool ?? true {
        didSet { UserDefaults.standard.set(outputAlongsideOriginal, forKey: "outputAlongsideOriginal") }
    }
    @Published var engineRefresh = 0

    private var mainWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var shelfWindows: [NSWindow] = []
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var queue: [(UUID, [URL], FileOperation, ConversionOptions)] = []
    private var activeJob: UUID?
    private var quittingAfterCancellation = false
    private var pendingInputs: [URL] = []
    private let wheel = DragWheelController()
    private let engine = ConversionEngine()

    func text(_ english: String, _ turkish: String) -> String { language == "tr" ? turkish : english }
    var operations: [FileOperation] { Catalog.operations(for: files, mode: mode) }
    var isBusy: Bool { activity.contains { $0.state == .running || $0.state == .waiting } }
    var completedCount: Int { activity.filter { $0.state == .succeeded }.count }
    var pendingInputURLs: [URL] { pendingInputs }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Normalize missing or unknown preferences to the default theme.
        UserDefaults.standard.set(theme.rawValue, forKey: AppTheme.preferenceKey)
        applyThemeAppearance()
        buildWindow()
        NotificationCenter.default.addObserver(self, selector: #selector(displayConfigurationChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "Lemulip")
        statusItem?.button?.toolTip = "Lemulip"
        rebuildStatusMenu()
        wheel.enabled = wheelEnabled
        wheel.onDrop = { [weak self] urls, operation in self?.begin(operation, inputs: urls) }
        wheel.onShowMain = { [weak self] in self?.showMainWindow() }
        wheel.start()
        showMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quittingAfterCancellation { return .terminateLater }
        guard isBusy else { return .terminateNow }
        if activity.contains(where: { $0.state == .running && ["action.copy", "action.move"].contains($0.operation.id) }) {
            let alert = NSAlert()
            alert.messageText = text("A File Transfer Is Still Running", "Dosya aktarımı devam ediyor")
            alert.informativeText = text("Wait for the copy or move to finish before quitting Lemulip.", "Lemulip'ten çıkmadan önce kopyalama veya taşıma işleminin bitmesini bekle.")
            alert.addButton(withTitle: text("Keep Working", "Devam et"))
            alert.runModal()
            return .terminateCancel
        }
        let alert = NSAlert()
        alert.messageText = text("Conversions Are Still Running", "Dönüşümler devam ediyor")
        alert.informativeText = text("Quit and cancel unfinished jobs? Your original files will be kept.", "Çıkıp tamamlanmamış işlemler iptal edilsin mi? Orijinal dosyaların korunur.")
        alert.addButton(withTitle: text("Keep Working", "Devam et"))
        alert.addButton(withTitle: text("Quit", "Çık"))
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        quittingAfterCancellation = true
        tasks.values.forEach { $0.cancel() }
        for (id, _, _, _) in queue { update(id) { $0.state = .cancelled } }
        queue.removeAll()
        // Let active converters terminate and remove their private staging
        // folders before AppKit exits the process.
        return tasks.isEmpty && activeJob == nil ? .terminateNow : .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        wheel.stop(); tasks.values.forEach { $0.cancel() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMainWindow(); return true }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        addFiles(filenames.map { URL(fileURLWithPath: $0) }); showMainWindow(); sender.reply(toOpenOrPrint: .success)
    }

    private func applyThemeAppearance() {
        // AppKit derives the high-contrast appearance from Aqua or Dark Aqua.
        NSApp.appearance = NSAppearance(named: theme.appearanceName)
        for window in [mainWindow].compactMap({ $0 }) + shelfWindows {
            window.backgroundColor = Palette.canvasColor
            window.contentView?.needsDisplay = true
        }
        // The light themes share Aqua, so redraw the wheel explicitly as well.
        wheel.refreshAppearance()
    }

    private func buildWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1050, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Lemulip"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Palette.canvasColor
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 850, height: 620)
        window.contentView = NSHostingView(rootView: DashboardView(model: self))
        // Preserve the saved window position from the original application name.
        let restoredFrame = window.setFrameUsingName("FreewheelMainWindow")
        window.setFrameAutosaveName("FreewheelMainWindow")
        if !restoredFrame { window.center() }
        mainWindow = window
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "About Lemulip", action: #selector(showAbout), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Hide Lemulip", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        applicationMenu.addItem(withTitle: "Quit Lemulip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let chooseItem = NSMenuItem(title: "Add Files…", action: #selector(chooseFiles), keyEquivalent: "o")
        chooseItem.target = self; fileMenu.addItem(chooseItem)
        let closeItem = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(closeItem); fileItem.submenu = fileMenu; menu.addItem(fileItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, selector, key) in [("Cut", Selector(("cut:")), "x"), ("Copy", Selector(("copy:")), "c"), ("Paste", Selector(("paste:")), "v"), ("Select All", Selector(("selectAll:")), "a")] {
            editMenu.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        editItem.submenu = editMenu; menu.addItem(editItem)
        applicationMenu.items.filter { $0.action == #selector(showSettings) || $0.action == #selector(showAbout) }.forEach { $0.target = self }
        NSApp.mainMenu = menu
    }

    private func rebuildStatusMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        let open = NSMenuItem(title: text("Open Lemulip", "Lemulip'i aç"), action: #selector(showMainWindow), keyEquivalent: "")
        open.target = self; menu.addItem(open)
        let add = NSMenuItem(title: text("Choose Files…", "Dosya seç…"), action: #selector(chooseFiles), keyEquivalent: "")
        add.target = self; menu.addItem(add)
        menu.addItem(.separator())
        let pause = NSMenuItem(title: text("Drag Wheel Enabled", "Sürükleme çarkı etkin"), action: #selector(toggleWheel), keyEquivalent: "")
        pause.target = self; pause.state = wheelEnabled ? .on : .off; menu.addItem(pause)
        let settings = NSMenuItem(title: text("Settings…", "Ayarlar…"), action: #selector(showSettings), keyEquivalent: "")
        settings.target = self; menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(withTitle: text("Quit Lemulip", "Lemulip'ten çık"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc func showMainWindow() {
        guard let mainWindow else { return }
        recoverWorkspaceWindow()
        if mainWindow.isMiniaturized { mainWindow.deminiaturize(nil) }
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func displayConfigurationChanged(_ notification: Notification) { recoverWorkspaceWindow() }

    private func recoverWorkspaceWindow() {
        guard let mainWindow, !mainWindow.styleMask.contains(.fullScreen) else { return }
        let frame = WorkspaceWindowPlacement.recoveredFrame(mainWindow.frame,
            visibleScreens: NSScreen.screens.map(\.visibleFrame),
            preferredScreen: NSScreen.main?.visibleFrame, minimumSize: mainWindow.minSize)
        if frame != mainWindow.frame { mainWindow.setFrame(frame, display: mainWindow.isVisible) }
    }
    @objc func showSettings() { section = "settings"; engineRefresh += 1; showMainWindow() }
    @objc private func toggleWheel() { wheelEnabled.toggle() }
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Lemulip", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Source Preview", .credits: NSAttributedString(string: "Free, open-source file conversion.\nCreated by Kaan Kars · MIT licensed\nAll processing happens on this Mac.")])
    }

    @objc func chooseFiles() {
        showMainWindow()
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.prompt = text("Add Files", "Dosya ekle")
        if panel.runModal() == .OK { addFiles(panel.urls) }
    }

    func addFiles(_ urls: [URL]) {
        let local = urls.filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
        for url in local where !files.contains(url) { files.append(url) }
        section = "workspace"
        if operations.isEmpty && !files.isEmpty { mode = .actions }
    }

    func moveFile(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard files.indices.contains(index), files.indices.contains(destination) else { return }
        files.swapAt(index, destination)
    }

    func showWheel() { guard !files.isEmpty else { chooseFiles(); return }; wheel.show(files: files, mode: mode) }

    func begin(_ operation: FileOperation, inputs: [URL]? = nil) {
        let selection = inputs ?? files
        guard !selection.isEmpty else { return }
        if let dependency = operation.dependency, !EngineLocator.isAvailable(dependency) {
            alertMessage = text("This operation needs \(dependency). Open Settings → Engines for free installation instructions.", "Bu işlem için \(dependency) gerekiyor. Ücretsiz kurulum yönergelerini Ayarlar → Motorlar bölümünde bulabilirsin.")
            showMainWindow(); return
        }
        if operation.id.hasPrefix("action.") { performFileAction(operation, inputs: selection); return }
        let withOptions: Set<String> = ["image.compress", "image.resize", "image.crop", "image.rotate", "pdf.organize", "pdf.merge", "pdf.extract", "pdf.rotate", "pdf.compress", "media.compress", "media.trim", "media.crop", "media.resize", "media.speed", "media.volume"]
        if withOptions.contains(operation.id) {
            // A second global-wheel drop must not replace the input shown by
            // an open editor, including another crop with the same operation ID.
            guard pendingOperation == nil else { showMainWindow(); return }
            pendingInputs = selection; pendingOperation = operation; showMainWindow()
        } else { submit(operation, inputs: selection, options: ConversionOptions()) }
    }

    func submitPending(_ options: ConversionOptions, outputExtension: String? = nil) {
        guard var operation = pendingOperation else { return }
        if let outputExtension { operation.outputExtension = outputExtension }
        let selection = pendingInputs
        pendingOperation = nil; pendingInputs = []
        submit(operation, inputs: selection, options: options)
    }

    func cancelPending() { pendingOperation = nil; pendingInputs = [] }

    func submit(_ operation: FileOperation, inputs: [URL], options: ConversionOptions) {
        var chosenOptions = options
        if !outputAlongsideOriginal && chosenOptions.destinationDirectory == nil {
            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
            panel.prompt = text("Save Here", "Buraya kaydet")
            guard panel.runModal() == .OK, let directory = panel.url else { return }
            chosenOptions.destinationDirectory = directory
        }
        let activityInputs: [URL]
        if let merge = chosenOptions.pdfMerge,
           (try? merge.validate(sourceInputCount: inputs.count)) != nil {
            activityInputs = merge.sources.map { inputs[$0.inputIndex] }
        } else {
            activityInputs = inputs
        }
        // Freeze the chosen destination so a later settings change cannot redirect a retry.
        if chosenOptions.destinationDirectory == nil, let first = activityInputs.first {
            chosenOptions.destinationDirectory = first.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent()
        }
        var item = ActivityItem(operation: operation, inputs: activityInputs)
        item.retryRequest = ConversionRequest(inputs: inputs, operation: operation, options: chosenOptions)
        activity.insert(item, at: 0)
        queue.append((item.id, inputs, operation, chosenOptions))
        startNextJob()
    }

    private func startNextJob() {
        if quittingAfterCancellation {
            if tasks.isEmpty && activeJob == nil { NSApp.reply(toApplicationShouldTerminate: true) }
            return
        }
        guard activeJob == nil, !queue.isEmpty else { return }
        let (id, inputs, operation, options) = queue.removeFirst()
        activeJob = id
        update(id) { $0.state = .running }
        let engine = self.engine
        tasks[id] = Task { [weak self] in
            do {
                let result = try await engine.run(inputs: inputs, operation: operation, options: options) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.activity.first(where: { $0.id == id })?.state == .running else { return }
                        self.update(id) { $0.progress = progress }
                    }
                }
                guard let self else { return }
                self.update(id) { $0.state = .succeeded; $0.retryRequest = nil; $0.outputs = result.outputs; $0.message = result.note ?? "" }
                if self.revealWhenFinished { NSWorkspace.shared.activateFileViewerSelecting(result.outputs) }
            } catch {
                guard let self else { return }
                let cancelled = Task.isCancelled || error is CancellationError || (error as? LemulipError).map { if case .cancelled = $0 { return true }; return false } == true
                self.update(id) { $0.state = cancelled ? .cancelled : .failed; $0.message = cancelled ? self.text("Cancelled", "İptal edildi") : error.localizedDescription }
            }
            guard let self else { return }
            self.tasks[id] = nil; self.activeJob = nil; self.startNextJob()
        }
    }

    private func update(_ id: UUID, _ edit: (inout ActivityItem) -> Void) {
        guard let index = activity.firstIndex(where: { $0.id == id }) else { return }
        edit(&activity[index])
    }

    func cancelJob(_ id: UUID) {
        if let task = tasks[id] { task.cancel() }
        else { queue.removeAll { $0.0 == id }; update(id) { $0.state = .cancelled } }
    }

    func canRetry(_ item: ActivityItem) -> Bool {
        item.retryRequest?.canRetry(after: item.state) == true
    }

    func retryJob(_ id: UUID) {
        guard !quittingAfterCancellation,
              let old = activity.first(where: { $0.id == id }),
              let request = old.retryRequest, request.canRetry(after: old.state) else { return }
        // Consume this retry before enqueuing; repeated clicks cannot submit twice.
        update(id) { $0.retryRequest = nil }
        var item = ActivityItem(operation: request.operation, inputs: old.inputs)
        item.retryRequest = request
        activity.insert(item, at: 0)
        queue.append((item.id, request.inputs, request.operation, request.options))
        startNextJob()
    }

    func clearActivity() { activity.removeAll { $0.state != .running && $0.state != .waiting } }
    func reveal(_ urls: [URL]) { NSWorkspace.shared.activateFileViewerSelecting(urls) }

    private func performFileAction(_ operation: FileOperation, inputs: [URL]) {
        switch operation.id {
        case "action.copyPath":
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(inputs.map(\.path).joined(separator: "\n"), forType: .string)
        case "action.airdrop":
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: inputs) else {
                alertMessage = text("AirDrop is unavailable on this Mac.", "Bu Mac'te AirDrop kullanılamıyor."); showMainWindow(); return
            }
            service.perform(withItems: inputs)
        case "action.float": showShelf(inputs)
        case "action.terminal":
            let first = inputs[0]
            let folder = FileFamily.detect(first) == .folder ? first : first.deletingLastPathComponent()
            let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                if let error { Task { @MainActor in self?.alertMessage = error.localizedDescription; self?.showMainWindow() } }
            }
        case "action.copy", "action.move":
            showMainWindow()
            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
            panel.prompt = operation.id == "action.move" ? text("Move Here", "Buraya taşı") : text("Copy Here", "Buraya kopyala")
            guard panel.runModal() == .OK, let directory = panel.url else { return }
            let move = operation.id == "action.move"
            let item = ActivityItem(operation: operation, inputs: inputs)
            activity.insert(item, at: 0)
            update(item.id) { $0.state = .running }
            tasks[item.id] = Task { [weak self] in
                do {
                    let result = await Task.detached(priority: .userInitiated) { () -> (outputs: [URL], failure: String?) in
                        var outputs: [URL] = []
                        for input in inputs {
                            do {
                                let source = input.standardizedFileURL.resolvingSymlinksInPath()
                                let destinationParent = directory.standardizedFileURL.resolvingSymlinksInPath()
                                if destinationParent.path == source.path || destinationParent.path.hasPrefix(source.path + "/") {
                                    throw LemulipError.invalidInput("A folder cannot be copied or moved inside itself.")
                                }
                                let stem = FileFamily.detect(input) == .folder ? input.lastPathComponent : input.deletingPathExtension().lastPathComponent
                                let ext = FileFamily.detect(input) == .folder ? "" : input.pathExtension
                                let target = OutputStore.uniqueURL(in: directory, stem: stem, extension: ext)
                                if move { try FileManager.default.moveItem(at: input, to: target) }
                                else { try FileManager.default.copyItem(at: input, to: target) }
                                outputs.append(target)
                            } catch {
                                return (outputs, error.localizedDescription)
                            }
                        }
                        return (outputs, nil)
                    }.value
                    if move, let self {
                        var movedFiles: [URL: URL] = [:]
                        for (source, target) in zip(inputs, result.outputs) { movedFiles[source.standardizedFileURL] = target }
                        self.files = self.files.map { movedFiles[$0.standardizedFileURL] ?? $0 }
                    }
                    self?.update(item.id) {
                        $0.state = result.failure == nil ? .succeeded : .failed
                        $0.outputs = result.outputs
                        if let failure = result.failure { $0.message = failure + " " + (self?.text("Completed transfers are listed below; they are not undone.", "Tamamlanan aktarımlar aşağıda listelenir; geri alınmazlar.") ?? "") }
                    }
                }
                self?.tasks[item.id] = nil
            }
        default: break
        }
    }

    private func showShelf(_ urls: [URL]) {
        shelfWindows.removeAll { !$0.isVisible }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 330, height: min(400, 110 + urls.count * 58)), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = text("File Shelf", "Dosya rafı")
        panel.backgroundColor = Palette.canvasColor
        panel.level = .floating; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: FileShelfView(urls: urls, model: self))
        panel.center(); panel.makeKeyAndOrderFront(nil)
        shelfWindows.append(panel)
    }
}
#endif
