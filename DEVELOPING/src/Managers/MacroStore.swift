import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

enum FocusedPane {
    case left, right
}

class MacroStore: ObservableObject {
    static let shared = MacroStore()

    let undoManager = UndoManager()

    func registerUndoState(for macro: MacroItem) {
        let oldActions = macro.actionItems
        let oldTriggers = macro.triggers
        let oldName = macro.fileName
        let oldEnabled = macro.isEnabled
        
        undoManager.registerUndo(withTarget: macro) { [weak self] target in
            guard let self = self else { return }
            self.registerUndoState(for: target)
            
            target.actionItems = oldActions
            target.triggers = oldTriggers
            target.fileName = oldName
            target.isEnabled = oldEnabled
            self.saveMacro(target)
            self.objectWillChange.send()
        }
    }

    @Published var treeNodes: [FileSystemNode] = []
    @Published var macros: [MacroItem] = []
    @Published var selectedFilePath: String?
    @Published var selectedFolderPath: String?
    @Published var editingFolderPath: String? = nil
    @Published var watchDirectoryURL: URL
    @Published var isSidebarVisible = true
    @Published var selectedActionIDs: Set<UUID> = []
    @Published var lastSelectedActionID: UUID? = nil
    // Key switch toggle state: maps trigger ID -> current state (false = primary, true = alternate)
    var keySwitchStates: [UUID: Bool] = [:]
    
    @Published var focusedPane: FocusedPane = .left
    @Published var isTriggerFocused: Bool = false
    @Published var isGridFocused: Bool = false
    @Published var gridSelectedIndex: Int = 0
    
    // Clipboard for copy-paste operations
    @Published var copiedMacroURL: URL? = nil
    @Published var copiedActions: [MacroActionItem] = []
    
    // Caching active application info for robust app-specific hotkey overrides
    var activeAppBundle: String = ""
    var activeAppName: String = ""
    
    var selectedActionID: UUID? {
        get { selectedActionIDs.first }
        set {
            if let val = newValue {
                selectedActionIDs = [val]
                lastSelectedActionID = val
            } else {
                selectedActionIDs.removeAll()
                lastSelectedActionID = nil
            }
        }
    }

    func handleActionSelect(_ itemID: UUID, items: [MacroActionItem], modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selectedActionIDs.contains(itemID) {
                selectedActionIDs.remove(itemID)
            } else {
                selectedActionIDs.insert(itemID)
            }
            lastSelectedActionID = itemID
        } else if modifiers.contains(.shift), let last = lastSelectedActionID,
                   let i1 = items.firstIndex(where: { $0.id == last }),
                   let i2 = items.firstIndex(where: { $0.id == itemID }) {
            let range = min(i1, i2)...max(i1, i2)
            for idx in range {
                selectedActionIDs.insert(items[idx].id)
            }
            lastSelectedActionID = itemID
        } else {
            selectedActionIDs = [itemID]
            lastSelectedActionID = itemID
        }
    }
    
    func deleteSelectedActions() {
        guard !selectedActionIDs.isEmpty else { return }
        guard let macro = selectedMacro,
              let idx = macros.firstIndex(where: { $0.id == macro.id }) else { return }
        
        registerUndoState(for: macros[idx])
        
        let targetIDs = selectedActionIDs
        func recursiveRemove(from list: inout [MacroActionItem]) {
            list.removeAll { targetIDs.contains($0.id) }
            for i in 0..<list.count {
                if case .group(let name, var sub) = list[i].action {
                    recursiveRemove(from: &sub)
                    list[i].action = .group(name: name, actions: sub)
                }
            }
        }
        
        recursiveRemove(from: &macros[idx].actionItems)
        for tIdx in 0..<macros[idx].triggers.count {
            recursiveRemove(from: &macros[idx].triggers[tIdx].alternateActionItems)
        }
        
        selectedActionIDs.removeAll()
        lastSelectedActionID = nil
        saveMacro(macros[idx])
        objectWillChange.send()
    }

    var selectedMacroID: UUID? {
        get { selectedMacro?.id }
        set {
            if let id = newValue {
                selectedFilePath = macros.first(where: { $0.id == id })?.fileURL.path
                selectedFolderPath = nil
            } else {
                selectedFilePath = nil
            }
        }
    }

    var selectedFileName: String? {
        get { selectedMacro?.fileName }
        set {
            if let name = newValue {
                selectedFilePath = macros.first(where: { $0.fileName == name })?.fileURL.path
                selectedFolderPath = nil
            }
        }
    }

    var selectedMacro: MacroItem? {
        get {
            guard let path = selectedFilePath else { return nil }
            return macros.first(where: { $0.fileURL.path == path })
        }
    }

    func loadFolderConfig(at folderURL: URL) -> FolderConfig {
        let configFile = folderURL.appendingPathComponent(".folder_config.json")
        guard let data = try? Data(contentsOf: configFile),
              let config = try? JSONDecoder().decode(FolderConfig.self, from: data) else {
            return FolderConfig()
        }
        return config
    }

    func saveFolderConfig(_ config: FolderConfig, for folderURL: URL) {
        let configFile = folderURL.appendingPathComponent(".folder_config.json")
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configFile, options: .atomic)
        }
        
        self.treeNodes = updateTreeNodeConfig(nodes: self.treeNodes, folderURL: folderURL, newConfig: config)
        self.objectWillChange.send()
        
        updateFinderFolderIcon(for: folderURL, config: config)
        loadMacros()
    }

    private func updateTreeNodeConfig(nodes: [FileSystemNode], folderURL: URL, newConfig: FolderConfig) -> [FileSystemNode] {
        return nodes.map { node in
            switch node {
            case .folder(let name, let url, let config, let children):
                let isMatch = url.standardizedFileURL.path == folderURL.standardizedFileURL.path
                let updatedChildren = updateTreeNodeConfig(nodes: children, folderURL: folderURL, newConfig: newConfig)
                return .folder(name: name, url: url, config: isMatch ? newConfig : config, children: updatedChildren)
            case .macro(let item):
                if item.fileURL.deletingLastPathComponent().standardizedFileURL.path == folderURL.standardizedFileURL.path {
                    item.parentFolderConfig = newConfig
                }
                return .macro(item: item)
            }
        }
    }

    private var watchStream: FSEventStreamRef?
    private var eventTap: CFMachPort?

    init() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let defaultPathURL = documentsURL.appendingPathComponent("ShortKing")
        let defaultPath = defaultPathURL.path

        if !fileManager.fileExists(atPath: defaultPath) {
            try? fileManager.createDirectory(at: defaultPathURL, withIntermediateDirectories: true, attributes: nil)
            if let bundleResourceURL = Bundle.main.resourceURL?.appendingPathComponent("DefaultDocuments") {
                if let items = try? fileManager.contentsOfDirectory(at: bundleResourceURL, includingPropertiesForKeys: nil, options: []) {
                    for item in items {
                        let destURL = defaultPathURL.appendingPathComponent(item.lastPathComponent)
                        try? fileManager.copyItem(at: item, to: destURL)
                    }
                }
            }
        }

        var savedPath = UserDefaults.standard.string(forKey: "watchDirectoryPath") ?? defaultPath
        if savedPath == "/Users/tonytoelle/Documents/PROJECTS/RedMunky - ShortKing/INPUT/ShortKing Documents" || !fileManager.fileExists(atPath: savedPath) {
            savedPath = defaultPath
            UserDefaults.standard.set(savedPath, forKey: "watchDirectoryPath")
            UserDefaults.standard.synchronize()
        }

        self.watchDirectoryURL = URL(fileURLWithPath: savedPath)
        
        // Cache initial active app information
        if let initialApp = NSWorkspace.shared.frontmostApplication {
            self.activeAppBundle = initialApp.bundleIdentifier ?? ""
            self.activeAppName = initialApp.localizedName ?? ""
        }

        loadMacros()
        startWatching()
        setupEventTap()
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
    
    @objc private func handleAppChange(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            let bundle = app.bundleIdentifier ?? ""
            let name = app.localizedName ?? ""
            print("📱 Active App Changed Notification: \(name) (\(bundle))")
            self.activeAppBundle = bundle
            self.activeAppName = name
            
            // Re-register hotkeys on the main thread for the newly focused app
            if Thread.isMainThread {
                self.registerAllCarbonHotKeys()
            } else {
                DispatchQueue.main.async {
                    self.registerAllCarbonHotKeys()
                }
            }
        }
    }

    func triggerMacroBySpecialKey(name: String) {
        for macro in macros {
            guard macro.isEffectivelyEnabled else { continue }
            let items = macro.actionItems
            for trigger in macro.triggers {
                let targetCode: CGKeyCode = (name == "brightness_down") ? 145 : 144
                if trigger.keyCode == targetCode {
                    print("🚀 Executing special hardware key macro: \(macro.fileName)")
                    let originPos: CGPoint = {
                        if let loc = CGEvent(source: nil)?.location, loc != .zero { return loc }
                        let cp = NSEvent.mouseLocation
                        let sh = NSScreen.screens.first?.frame.height ?? 1080
                        return CGPoint(x: cp.x, y: sh - cp.y)
                    }()
                    let windowRect = InputSimulator.getFrontmostWindowRect()
                    DispatchQueue.global(qos: .userInitiated).async {
                        InputSimulator.execute(items: items, preRecordedOrigin: originPos, preRecordedWindowRect: windowRect, macroID: macro.id)
                    }
                }
            }
        }
    }

    private func setupEventTap() {
        let eventMask = (1 << 14) // NX_SYSDEFINED is 14
        
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if type.rawValue == 14 {
                    if let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 {
                        let data1 = nsEvent.data1
                        let keyType = (data1 & 0xFFFF0000) >> 16
                        let keyState = (data1 & 0xFF00) >> 8
                        let isKeyDown = (keyState == 0xa)
                        
                        if isKeyDown {
                            if keyType == 3 { // NX_KEYTYPE_BRIGHTNESS_DOWN
                                print("🔆 Brightness Down hardware key detected!")
                                DispatchQueue.main.async {
                                    MacroStore.shared.triggerMacroBySpecialKey(name: "brightness_down")
                                }
                                return nil // Swallow keypress so macOS doesn't lower screen brightness
                            } else if keyType == 2 { // NX_KEYTYPE_BRIGHTNESS_UP
                                print("🔆 Brightness Up hardware key detected!")
                                DispatchQueue.main.async {
                                    MacroStore.shared.triggerMacroBySpecialKey(name: "brightness_up")
                                }
                                return nil // Swallow keypress so macOS doesn't raise screen brightness
                            }
                        }
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )
        
        guard let tap = eventTap else {
            print("⚠️ Failed to create event tap for media/special hardware keys")
            return
        }
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("👑 Event tap initialized successfully for hardware brightness keys")
    }

    private func scanDirectory(at url: URL, loadedMacros: inout [MacroItem], existingMacrosMap: [String: MacroItem], parentConfig: FolderConfig? = nil) -> [FileSystemNode] {
        guard let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        
        var nodes: [FileSystemNode] = []
        let sorted = items.sorted {
            let isDir0 = (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let isDir1 = (try? $1.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir0 != isDir1 {
                return isDir0 // Folders on top like Finder / Obsidian
            }
            return $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        
        for item in sorted {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                let config = loadFolderConfig(at: item)
                let children = scanDirectory(at: item, loadedMacros: &loadedMacros, existingMacrosMap: existingMacrosMap, parentConfig: config)
                nodes.append(.folder(name: item.lastPathComponent, url: item, config: config, children: children))
            } else if item.pathExtension.lowercased() == "shortking" {
                if let parsed = ShortKingParser.parseFile(at: item) {
                    let macro: MacroItem
                    if let existing = existingMacrosMap[item.path] {
                        existing.fileName = parsed.fileName
                        existing.fileURL = parsed.fileURL
                        existing.triggers = parsed.triggers
                        existing.actionItems = parsed.actionItems
                        existing.isEnabled = parsed.isEnabled
                        existing.parentFolderConfig = parentConfig
                        macro = existing
                    } else {
                        parsed.parentFolderConfig = parentConfig
                        macro = parsed
                    }
                    loadedMacros.append(macro)
                    nodes.append(.macro(item: macro))
                }
            }
        }
        return nodes
    }

    func loadMacros() {
        try? FileManager.default.createDirectory(at: watchDirectoryURL, withIntermediateDirectories: true)
        
        var existingMap: [String: MacroItem] = [:]
        for m in self.macros {
            existingMap[m.fileURL.path] = m
        }
        
        var loaded: [MacroItem] = []
        let tree = scanDirectory(at: watchDirectoryURL, loadedMacros: &loaded, existingMacrosMap: existingMap)
        
        DispatchQueue.main.async {
            self.treeNodes = tree
            self.macros = loaded
            if let current = self.selectedFilePath, loaded.contains(where: { $0.fileURL.path == current }) {
                // Keep current selection
            } else if let currentFolder = self.selectedFolderPath, FileManager.default.fileExists(atPath: currentFolder) {
                // Keep folder selection
            } else {
                self.selectedFilePath = nil
                self.selectedFolderPath = nil
            }
            self.registerAllCarbonHotKeys()
        }
    }

    func setWatchDirectory(_ url: URL) {
        stopWatching()
        self.watchDirectoryURL = url
        UserDefaults.standard.set(url.path, forKey: "watchDirectoryPath")
        UserDefaults.standard.synchronize()
        loadMacros()
        startWatching()
    }

    func registerAllCarbonHotKeys() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.registerAllCarbonHotKeys() }
            return
        }
        CarbonHotKeyManager.shared.unregisterAll()
        
        let activeBundle = self.activeAppBundle
        let activeName = self.activeAppName
        
        // Track which key combos are already registered by global macros
        // Key: "\(keyCode)-\(modifiers)" to uniquely identify a hotkey combo
        var registeredKeyCombos = Set<String>()
        
        // Helper to create a unique key for a trigger combo
        func comboKey(for trig: Trigger) -> String {
            var mods = ""
            if trig.requireCmd { mods += "C" }
            if trig.requireShift { mods += "S" }
            if trig.requireOption { mods += "O" }
            if trig.requireControl { mods += "X" }
            return "\(trig.keyCode)-\(mods)"
        }
        
        // Helper to register a macro's triggers
        func registerTriggers(for macro: MacroItem, trackCombo: Bool) {
            let items = macro.actionItems
            for trig in macro.triggers {
                if trig.keyCode == 144 || trig.keyCode == 145 { continue }
                
                let combo = comboKey(for: trig)
                
                // If this combo is already registered by a higher priority macro, skip
                if registeredKeyCombos.contains(combo) {
                    print("⚠️ Combo \(combo) (\(trig.displayString)) already registered. Skipping macro: \(macro.fileName)")
                    continue
                }
                
                print("🔑 Registering hotkey combo \(combo) (\(trig.displayString)) for macro: \(macro.fileName)")
                if trackCombo {
                    registeredKeyCombos.insert(combo)
                }
                
                let trigID = trig.id
                let trigMode = trig.mode
                let altItems = trig.alternateActionItems
                CarbonHotKeyManager.shared.register(trigger: trig) { [weak self] in
                    print("🚀 Executing: \(macro.fileName)")
                    let originPos: CGPoint = {
                        if let loc = CGEvent(source: nil)?.location, loc != .zero { return loc }
                        let cp = NSEvent.mouseLocation
                        let sh = NSScreen.screens.first?.frame.height ?? 1080
                        return CGPoint(x: cp.x, y: sh - cp.y)
                    }()
                    let windowRect = InputSimulator.getFrontmostWindowRect()
                    
                    let executionItems: [MacroActionItem]
                    if trigMode == .keySwitch && !altItems.isEmpty {
                        let useAlternate = self?.keySwitchStates[trigID] ?? false
                        executionItems = useAlternate ? altItems : items
                        self?.keySwitchStates[trigID] = !useAlternate
                        print("🔄 Key Switch: \(useAlternate ? "alternate" : "primary") actions")
                    } else {
                        executionItems = items
                    }
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        InputSimulator.execute(items: executionItems, preRecordedOrigin: originPos, preRecordedWindowRect: windowRect, macroID: macro.id)
                    }
                }
            }
        }
        
        // Helper to check if a macro is restricted to apps and matches the current active app
        func getRestrictionStatus(for macro: MacroItem) -> (isRestricted: Bool, matchesActiveApp: Bool) {
            guard let cfg = macro.parentFolderConfig else {
                return (false, false)
            }
            
            // Check explicit restrictions
            let hasExplicitApps = cfg.isRestrictedToApps && !cfg.targetApps.isEmpty
            // Check implicit restriction via custom folder app icon
            let hasImplicitApp = cfg.customAppIconBundleId != nil && !cfg.customAppIconBundleId!.isEmpty
            
            let isRestricted = hasExplicitApps || hasImplicitApp
            
            var matches = false
            if hasExplicitApps {
                matches = cfg.targetApps.contains { target in
                    target.bundleId == activeBundle || target.name.localizedCaseInsensitiveCompare(activeName) == .orderedSame
                }
            }
            
            if !matches, let bundleId = cfg.customAppIconBundleId, !bundleId.isEmpty {
                matches = (bundleId == activeBundle)
            }
            
            return (isRestricted, matches)
        }
        
        // PASS 1: Register APP-SPECIFIC macros first (if target app matches current active app)
        for macro in macros {
            guard macro.isEffectivelyEnabled else { continue }
            let status = getRestrictionStatus(for: macro)
            
            if status.isRestricted && status.matchesActiveApp {
                registerTriggers(for: macro, trackCombo: true)
            }
        }
        
        // PASS 2: Register GLOBAL macros only if key combo is not already taken by active app-specific macro
        for macro in macros {
            guard macro.isEffectivelyEnabled else { continue }
            let status = getRestrictionStatus(for: macro)
            
            if !status.isRestricted {
                registerTriggers(for: macro, trackCombo: true)
            }
        }
    }

    func stopWatching() {
        if let stream = watchStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            watchStream = nil
        }
    }

    private var isReloading = false
    private var isSavingInternally = false

    func startWatching() {
        stopWatching()
        
        let pathsToWatch = [watchDirectoryURL.path] as CFArray
        
        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let callback: FSEventStreamCallback = { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            guard let info = clientCallBackInfo else { return }
            let store = Unmanaged<MacroStore>.fromOpaque(info).takeUnretainedValue()
            
            // If the app itself just wrote to disk, ignore the filesystem bounce
            guard !store.isSavingInternally else { return }
            guard !store.isReloading else { return }
            store.isReloading = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                store.loadMacros()
                store.isReloading = false
            }
        }
        
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        
        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, // Latency in seconds
            flags
        ) else { return }
        
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        watchStream = stream
    }

    func saveMacro(_ macro: MacroItem) {
        let triggers = macro.triggers
        let actionItems = macro.actionItems
        let isEnabled = macro.isEnabled
        let fileURL = macro.fileURL
        
        self.isSavingInternally = true
        
        DispatchQueue.global(qos: .utility).async {
            let content = ShortKingParser.generateScript(triggers: triggers, actionItems: actionItems, isEnabled: isEnabled)
            try? content.write(to: fileURL, atomically: true, encoding: .utf8)
            
            DispatchQueue.main.async {
                self.registerAllCarbonHotKeys()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.isSavingInternally = false
                }
            }
        }
    }

    func moveSelectedActionsUp() {
        guard let macro = selectedMacro else { return }
        let selected = selectedActionIDs
        let indices = macro.actionItems.enumerated().filter { selected.contains($1.id) }.map { $0.offset }
        guard let first = indices.first, first > 0 else { return }
        macro.actionItems.move(fromOffsets: IndexSet(indices), toOffset: first - 1)
        saveMacro(macro)
    }

    func moveSelectedActionsDown() {
        guard let macro = selectedMacro else { return }
        let selected = selectedActionIDs
        let indices = macro.actionItems.enumerated().filter { selected.contains($1.id) }.map { $0.offset }
        guard let last = indices.last, last < macro.actionItems.count - 1 else { return }
        macro.actionItems.move(fromOffsets: IndexSet(indices), toOffset: last + 2)
        saveMacro(macro)
    }
    
    func toggleMacroEnabled(_ macro: MacroItem) {
        macro.isEnabled.toggle()
        saveMacro(macro)
        objectWillChange.send()
    }

    func renameMacro(_ macro: MacroItem, newBaseName: String) {
        let cleanName = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
                                   .replacingOccurrences(of: ".shortking", with: "")
        guard !cleanName.isEmpty else { return }
        
        let newFileName = cleanName + ".shortking"
        let oldURL = macro.fileURL
        let parentDir = oldURL.deletingLastPathComponent()
        let newURL = parentDir.appendingPathComponent(newFileName)
        
        guard oldURL.path != newURL.path else { return }
        
        do {
            if FileManager.default.fileExists(atPath: oldURL.path) {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
            } else {
                let content = ShortKingParser.generateScript(triggers: macro.triggers, actions: macro.actions)
                try content.write(to: newURL, atomically: true, encoding: .utf8)
            }
            macro.fileURL = newURL
            macro.fileName = newFileName
            self.selectedFilePath = newURL.path
            
            // Update Finder icon on new file safely
            updateMacroFinderIcon(for: newURL, trigger: macro.trigger)
            
            loadMacros()
        } catch {
            print("❌ Failed to rename file: \(error)")
        }
    }

    @discardableResult
    func createNewFolder(parentURL: URL? = nil) -> URL {
        let targetDir = parentURL ?? (selectedFolderPath.map { URL(fileURLWithPath: $0) } ?? watchDirectoryURL)
        var count = 1
        var folderName = "New Folder"
        var folderURL = targetDir.appendingPathComponent(folderName)
        while FileManager.default.fileExists(atPath: folderURL.path) {
            count += 1
            folderName = "New Folder \(count)"
            folderURL = targetDir.appendingPathComponent(folderName)
        }
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        self.selectedFolderPath = folderURL.path
        self.selectedFilePath = nil
        self.editingFolderPath = folderURL.path
        loadMacros()
        return folderURL
    }

    func createFolder(name: String, parentURL: URL? = nil) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let targetDir = parentURL ?? watchDirectoryURL
        let folderURL = targetDir.appendingPathComponent(clean)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        loadMacros()
    }

    func deleteFolder(at url: URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let backupURL = tempDir.appendingPathComponent(url.lastPathComponent)
        
        do {
            try FileManager.default.copyItem(at: url, to: backupURL)
            try FileManager.default.removeItem(at: url)
            loadMacros()
            
            undoManager.registerUndo(withTarget: self) { [weak self] store in
                guard let self = self else { return }
                try? FileManager.default.copyItem(at: backupURL, to: url)
                try? FileManager.default.removeItem(at: tempDir)
                self.loadMacros()
                self.selectedFolderPath = url.path
                
                store.undoManager.registerUndo(withTarget: self) { store in
                    store.deleteFolder(at: url)
                }
            }
        } catch {
            print("❌ Failed to delete/backup folder: \(error)")
        }
    }

    func renameFolder(at url: URL, newName: String) {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let parent = url.deletingLastPathComponent()
        let dest = parent.appendingPathComponent(clean)
        guard dest != url else { return }
        try? FileManager.default.moveItem(at: url, to: dest)
        if selectedFolderPath == url.path {
            selectedFolderPath = dest.path
        }
        loadMacros()
    }

    func createNewMacro(inFolder parentURL: URL? = nil) {
        var targetDir: URL
        
        if let parent = parentURL {
            targetDir = parent
        } else if let selectedFolder = selectedFolderPath {
            targetDir = URL(fileURLWithPath: selectedFolder)
        } else if let selectedPath = selectedFilePath {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: selectedPath, isDirectory: &isDir) {
                if isDir.boolValue {
                    targetDir = URL(fileURLWithPath: selectedPath)
                } else {
                    targetDir = URL(fileURLWithPath: selectedPath).deletingLastPathComponent()
                }
            } else {
                targetDir = watchDirectoryURL
            }
        } else {
            // Default when no selection: put in "New Macros" folder!
            let newMacrosFolderURL = watchDirectoryURL.appendingPathComponent("New Macros")
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: newMacrosFolderURL.path, isDirectory: &isDir) || !isDir.boolValue {
                try? FileManager.default.createDirectory(at: newMacrosFolderURL, withIntermediateDirectories: true, attributes: nil)
            }
            targetDir = newMacrosFolderURL
        }
        
        var count = 1
        var fileName = "Macro \(count).shortking"
        var url = targetDir.appendingPathComponent(fileName)
        while FileManager.default.fileExists(atPath: url.path) {
            count += 1
            fileName = "Macro \(count).shortking"
            url = targetDir.appendingPathComponent(fileName)
        }
        
        self.selectedFilePath = url.path
        self.selectedFolderPath = nil
        self.focusedPane = .right
        let t = Trigger(keyCode: 40, requireCmd: true, requireShift: true, requireOption: false, requireControl: false)
        let a: [MacroAction] = []
        try? ShortKingParser.generateScript(triggers: [t], actions: a).write(to: url, atomically: true, encoding: .utf8)
        loadMacros()
    }

    func renameMacro(_ macro: MacroItem, newName: String) {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let baseName = clean.hasSuffix(".shortking") ? String(clean.dropLast(10)) : clean
        let parentDir = macro.fileURL.deletingLastPathComponent()
        let newURL = parentDir.appendingPathComponent("\(baseName).shortking")
        guard newURL != macro.fileURL else { return }
        
        do {
            try FileManager.default.moveItem(at: macro.fileURL, to: newURL)
            if selectedFilePath == macro.fileURL.path {
                selectedFilePath = newURL.path
            }
            loadMacros()
        } catch {
            print("❌ Failed to rename macro: \(error)")
        }
    }

    func duplicateMacro(_ macro: MacroItem) {
        let baseName = macro.fileName.replacingOccurrences(of: ".shortking", with: "")
        let parentDir = macro.fileURL.deletingLastPathComponent()
        var newName = "\(baseName) copy"
        var newURL = parentDir.appendingPathComponent("\(newName).shortking")
        var copyIndex = 2
        while FileManager.default.fileExists(atPath: newURL.path) {
            newName = "\(baseName) copy \(copyIndex)"
            newURL = parentDir.appendingPathComponent("\(newName).shortking")
            copyIndex += 1
        }
        
        self.selectedFilePath = newURL.path
        
        saveMacro(macro)
        
        do {
            try FileManager.default.copyItem(at: macro.fileURL, to: newURL)
            loadMacros()
        } catch {
            print("❌ Failed to duplicate macro: \(error)")
        }
    }

    func deleteMacro(_ macro: MacroItem) {
        let fileURL = macro.fileURL
        
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            try? FileManager.default.removeItem(at: fileURL)
            loadMacros()
            return
        }
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            loadMacros()
            
            undoManager.registerUndo(withTarget: self) { [weak self] store in
                guard let self = self else { return }
                try? content.write(to: fileURL, atomically: true, encoding: .utf8)
                self.loadMacros()
                self.selectedFilePath = fileURL.path
                
                if let restoredMacro = self.macros.first(where: { $0.fileURL.path == fileURL.path }) {
                    self.undoManager.registerUndo(withTarget: self) { store in
                        store.deleteMacro(restoredMacro)
                    }
                }
            }
        } catch {
            print("❌ Failed to delete macro: \(error)")
        }
    }

    func revealInFinder(_ macro: MacroItem) {
        NSWorkspace.shared.activateFileViewerSelecting([macro.fileURL])
    }

    func revealFolderInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func moveItems(paths: [String], toFolder targetFolderURL: URL) {
        for path in paths {
            let sourceURL = URL(fileURLWithPath: path)
            let fileName = sourceURL.lastPathComponent
            let destURL = targetFolderURL.appendingPathComponent(fileName)
            
            guard sourceURL.standardizedFileURL.path != destURL.standardizedFileURL.path else { continue }
            
            // Avoid moving a parent folder into its own subfolder
            if targetFolderURL.path.hasPrefix(sourceURL.path + "/") { continue }
            
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    let base = sourceURL.deletingPathExtension().lastPathComponent
                    let ext = sourceURL.pathExtension
                    var newName = "\(base) copy"
                    if !ext.isEmpty { newName += ".\(ext)" }
                    var uniqueDest = targetFolderURL.appendingPathComponent(newName)
                    var idx = 2
                    while FileManager.default.fileExists(atPath: uniqueDest.path) {
                        newName = "\(base) copy \(idx)"
                        if !ext.isEmpty { newName += ".\(ext)" }
                        uniqueDest = targetFolderURL.appendingPathComponent(newName)
                        idx += 1
                    }
                    try FileManager.default.moveItem(at: sourceURL, to: uniqueDest)
                } else {
                    try FileManager.default.moveItem(at: sourceURL, to: destURL)
                }
            } catch {
                print("❌ Failed to move item: \(error)")
            }
        }
        loadMacros()
    }

    func deleteItems(paths: [String]) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        var backupMap: [(originalURL: URL, backupURL: URL)] = []
        for path in paths {
            let origURL = URL(fileURLWithPath: path)
            let bkpURL = tempDir.appendingPathComponent(UUID().uuidString + "_" + origURL.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: origURL, to: bkpURL)
                backupMap.append((origURL, bkpURL))
                try FileManager.default.removeItem(at: origURL)
            } catch {
                print("❌ Failed to delete item at \(path): \(error)")
            }
        }
        loadMacros()
        
        guard !backupMap.isEmpty else { return }
        
        undoManager.registerUndo(withTarget: self) { [weak self] store in
            guard let self = self else { return }
            for item in backupMap {
                try? FileManager.default.copyItem(at: item.backupURL, to: item.originalURL)
            }
            try? FileManager.default.removeItem(at: tempDir)
            self.loadMacros()
            
            self.undoManager.registerUndo(withTarget: self) { store in
                store.deleteItems(paths: paths)
            }
        }
    }

    func runMacro(_ macro: MacroItem) {
        let items = macro.actionItems
        // Capture cursor origin on main thread before dispatching to background
        let originPos: CGPoint = {
            if let loc = CGEvent(source: nil)?.location, loc != .zero {
                return loc
            }
            let cocoaPt = NSEvent.mouseLocation
            let screenH = NSScreen.screens.first?.frame.height ?? 1080
            return CGPoint(x: cocoaPt.x, y: screenH - cocoaPt.y)
        }()
        let windowRect = InputSimulator.getFrontmostWindowRect()
        DispatchQueue.global(qos: .userInitiated).async { InputSimulator.execute(items: items, preRecordedOrigin: originPos, preRecordedWindowRect: windowRect, macroID: macro.id) }
    }

    func pasteCopiedMacro(toFolder destDir: URL) {
        guard let copiedURL = copiedMacroURL else { return }
        let baseName = copiedURL.deletingPathExtension().lastPathComponent
        var newName = "\(baseName) copy"
        var newURL = destDir.appendingPathComponent("\(newName).shortking")
        var copyIndex = 2
        while FileManager.default.fileExists(atPath: newURL.path) {
            newName = "\(baseName) copy \(copyIndex)"
            newURL = destDir.appendingPathComponent("\(newName).shortking")
            copyIndex += 1
        }
        
        do {
            try FileManager.default.copyItem(at: copiedURL, to: newURL)
            self.selectedFilePath = newURL.path
            self.selectedFolderPath = nil
            loadMacros()
        } catch {
            print("❌ Failed to paste macro: \(error)")
        }
    }

    func moveSelectionUp(expandedFolders: Set<String>) {
        let visible = getVisiblePaths(expandedFolders: expandedFolders)
        guard !visible.isEmpty else { return }
        let current = selectedFilePath ?? selectedFolderPath
        let currentIndex = current.flatMap { visible.firstIndex(of: $0) } ?? -1
        
        if currentIndex > 0 {
            selectPath(visible[currentIndex - 1])
        }
    }
    
    func moveSelectionDown(expandedFolders: Set<String>) {
        let visible = getVisiblePaths(expandedFolders: expandedFolders)
        guard !visible.isEmpty else { return }
        let current = selectedFilePath ?? selectedFolderPath
        let currentIndex = current.flatMap { visible.firstIndex(of: $0) } ?? -1
        
        if currentIndex < visible.count - 1 {
            selectPath(visible[currentIndex + 1])
        }
    }
    
    private func selectPath(_ path: String) {
        if path.hasSuffix(".shortking") {
            selectedFilePath = path
            selectedFolderPath = nil
        } else {
            selectedFolderPath = path
            selectedFilePath = nil
        }
    }
    
    func getVisiblePaths(expandedFolders: Set<String>) -> [String] {
        return getVisiblePathsRecursively(nodes: treeNodes, expandedFolders: expandedFolders)
    }
    
    private func getVisiblePathsRecursively(nodes: [FileSystemNode], expandedFolders: Set<String>) -> [String] {
        var paths: [String] = []
        for node in nodes {
            switch node {
            case .folder(_, let url, _, let children):
                paths.append(url.path)
                if expandedFolders.contains(url.path) {
                    paths.append(contentsOf: getVisiblePathsRecursively(nodes: children, expandedFolders: expandedFolders))
                }
            case .macro(let item):
                paths.append(item.fileURL.path)
            }
        }
        return paths
    }

    func moveActionSelectionUp() {
        guard let selected = selectedMacro else { return }
        let items = selected.actionItems
        
        if isGridFocused {
            let cols = 4
            if gridSelectedIndex >= cols {
                gridSelectedIndex -= cols
            } else {
                // Jump up from Action Grid to last Action card
                isGridFocused = false
                if let last = items.last {
                    selectedActionIDs = [last.id]
                    lastSelectedActionID = last.id
                    isTriggerFocused = false
                } else {
                    isTriggerFocused = true
                }
            }
            return
        }
        
        if isTriggerFocused {
            return
        }
        
        let currentID = lastSelectedActionID ?? selectedActionIDs.first
        let currentIndex = currentID.flatMap { id in items.firstIndex(where: { $0.id == id }) } ?? -1
        
        if currentIndex > 0 {
            let prevItem = items[currentIndex - 1]
            selectedActionIDs = [prevItem.id]
            lastSelectedActionID = prevItem.id
            isTriggerFocused = false
            isGridFocused = false
        } else if currentIndex == 0 || items.isEmpty {
            selectedActionIDs.removeAll()
            lastSelectedActionID = nil
            isTriggerFocused = true
            isGridFocused = false
        } else {
            if let last = items.last {
                selectedActionIDs = [last.id]
                lastSelectedActionID = last.id
                isTriggerFocused = false
            } else {
                isTriggerFocused = true
            }
            isGridFocused = false
        }
    }
    
    func moveActionSelectionDown() {
        guard let selected = selectedMacro else { return }
        let items = selected.actionItems
        
        if isGridFocused {
            let total = SearchableActionDef.allActions.count
            let cols = 4
            if gridSelectedIndex + cols < total {
                gridSelectedIndex += cols
            } else if gridSelectedIndex < total - 1 {
                gridSelectedIndex = total - 1
            }
            return
        }
        
        if isTriggerFocused {
            if let first = items.first {
                selectedActionIDs = [first.id]
                lastSelectedActionID = first.id
                isTriggerFocused = false
                isGridFocused = false
            } else {
                isTriggerFocused = false
                isGridFocused = true
                gridSelectedIndex = 0
            }
            return
        }
        
        guard !items.isEmpty else {
            isTriggerFocused = false
            isGridFocused = true
            gridSelectedIndex = 0
            return
        }
        
        let currentID = lastSelectedActionID ?? selectedActionIDs.first
        let currentIndex = currentID.flatMap { id in items.firstIndex(where: { $0.id == id }) } ?? -1
        
        if currentIndex >= 0 && currentIndex < items.count - 1 {
            let nextItem = items[currentIndex + 1]
            selectedActionIDs = [nextItem.id]
            lastSelectedActionID = nextItem.id
            isTriggerFocused = false
            isGridFocused = false
        } else if currentIndex == items.count - 1 {
            // Jump down from last action to Action Grid!
            selectedActionIDs.removeAll()
            lastSelectedActionID = nil
            isTriggerFocused = false
            isGridFocused = true
            gridSelectedIndex = 0
        } else if currentIndex == -1 {
            if let first = items.first {
                selectedActionIDs = [first.id]
                lastSelectedActionID = first.id
                isTriggerFocused = false
                isGridFocused = false
            }
        }
    }
    
    func moveGridSelectionLeft() {
        if isGridFocused {
            if gridSelectedIndex > 0 {
                gridSelectedIndex -= 1
            } else {
                focusedPane = .left
                isGridFocused = false
            }
        }
    }
    
    func moveGridSelectionRight() {
        if isGridFocused {
            let total = SearchableActionDef.allActions.count
            if gridSelectedIndex < total - 1 {
                gridSelectedIndex += 1
            }
        }
    }
    
    func insertDefaultAction(typeName: String) {
        guard let macro = selectedMacro else { return }
        let newAction: MacroAction
        switch typeName {
        case "Path": newAction = .path(points: [])
        case "Left Click": newAction = .click(point: .zero, button: .left)
        case "Right Click": newAction = .click(point: .zero, button: .right)
        case "Drag": newAction = .drag(start: .zero, end: .zero)
        case "Move Cursor": newAction = .moveCursor(point: .zero)
        case "Delay": newAction = .delay(ms: 300)
        case "Text": newAction = .typeText(text: "Hello ShortKing")
        case "Key": newAction = .pressKey(keyCode: 36)
        case "Do Again": newAction = .doAgain(target: .origin)
        case "Group": newAction = .group(name: "New Group", actions: [])
        case "Custom": newAction = .customAction(script: "osascript -e 'set volume output volume (output volume of (get volume settings) + 6)'")
        case "Open File": newAction = .openFile(path: "")
        case "Vol Up": newAction = .volumeUp
        case "Vol Down": newAction = .volumeDown
        case "Brit Up": newAction = .brightnessUp
        case "Brit Down": newAction = .brightnessDown
        case "Window Transform": newAction = .windowTransform(p1: .zero, p2: .zero, p3: .zero, p4: .zero)
        case "Origin": newAction = .originAction(type: .cursor)
        default: newAction = .delay(ms: 300)
        }
        
        let newActionItem = MacroActionItem(action: newAction)
        macro.actionItems.append(newActionItem)
        selectedActionIDs = [newActionItem.id]
        lastSelectedActionID = newActionItem.id
        isGridFocused = false
        saveMacro(macro)
    }
}

// ==========================================
// MARK: - Permission Manager (macOS Accessibility & Input Monitoring)
// ==========================================
