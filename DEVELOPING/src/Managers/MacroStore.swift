import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

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
    @Published var watchDirectoryURL: URL
    @Published var isSidebarVisible = true
    @Published var selectedActionIDs: Set<UUID> = []
    @Published var lastSelectedActionID: UUID? = nil
    // Key switch toggle state: maps trigger ID -> current state (false = primary, true = alternate)
    var keySwitchStates: [UUID: Bool] = [:]
    
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
        if savedPath.contains("tonytoelle/Documents/PROJECTS") || !fileManager.fileExists(atPath: savedPath) {
            savedPath = defaultPath
            UserDefaults.standard.set(savedPath, forKey: "watchDirectoryPath")
        }

        self.watchDirectoryURL = URL(fileURLWithPath: savedPath)

        loadMacros()
        startWatching()
        setupEventTap()
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
    
    @objc private func handleAppChange() {
        registerAllCarbonHotKeys()
    }

    func triggerMacroBySpecialKey(name: String) {
        for macro in macros {
            guard macro.isEnabled else { continue }
            let items = macro.actionItems
            for trigger in macro.triggers {
                let targetCode: CGKeyCode = (name == "brightness_down") ? 145 : 144
                if trigger.keyCode == targetCode {
                    print("🚀 Executing special hardware key macro: \(macro.fileName)")
                    let originPos: CGPoint = {
                        if let loc = CGEvent(source: nil)?.location, loc != .zero { return loc }
                        let cp = NSEvent.mouseLocation
                        let sh = NSScreen.main?.frame.height ?? 1080
                        return CGPoint(x: cp.x, y: sh - cp.y)
                    }()
                    DispatchQueue.global(qos: .userInitiated).async {
                        InputSimulator.execute(items: items, preRecordedOrigin: originPos)
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
            } else if let firstMacro = loaded.first {
                self.selectedFilePath = firstMacro.fileURL.path
                self.selectedFolderPath = nil
            } else {
                self.selectedFilePath = nil
            }
            self.registerAllCarbonHotKeys()
        }
    }

    func setWatchDirectory(_ url: URL) {
        stopWatching()
        self.watchDirectoryURL = url
        UserDefaults.standard.set(url.path, forKey: "watchDirectoryPath")
        loadMacros()
        startWatching()
    }

    func registerAllCarbonHotKeys() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.registerAllCarbonHotKeys() }
            return
        }
        CarbonHotKeyManager.shared.unregisterAll()
        
        let frontApp = NSWorkspace.shared.frontmostApplication
        let activeBundle = frontApp?.bundleIdentifier ?? ""
        let activeName = frontApp?.localizedName ?? ""
        
        for macro in macros {
            guard macro.isEnabled else { continue }
            let items = macro.actionItems
            let folderConfig = macro.parentFolderConfig
            
            // App targeting restriction check
            if let cfg = folderConfig, cfg.isRestrictedToApps && !cfg.targetApps.isEmpty {
                let matches = cfg.targetApps.contains { target in
                    target.bundleId == activeBundle || target.name.localizedCaseInsensitiveCompare(activeName) == .orderedSame
                }
                // Skip registering hotkey globally if active app doesn't match targeting list
                if !matches {
                    continue
                }
            }
            
            for trig in macro.triggers {
                // Skip registering brightness keys (144, 145) with Carbon, since they are handled via Event Tap
                if trig.keyCode == 144 || trig.keyCode == 145 {
                    continue
                }
                let trigID = trig.id
                let trigMode = trig.mode
                let altItems = trig.alternateActionItems
                CarbonHotKeyManager.shared.register(trigger: trig) { [weak self] in
                    print("🚀 Executing: \(macro.fileName)")
                    // Capture cursor origin NOW before background dispatch
                    let originPos: CGPoint = {
                        if let loc = CGEvent(source: nil)?.location, loc != .zero { return loc }
                        let cp = NSEvent.mouseLocation
                        let sh = NSScreen.main?.frame.height ?? 1080
                        return CGPoint(x: cp.x, y: sh - cp.y)
                    }()
                    
                    // Determine which action set to run for key switch triggers
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
                        InputSimulator.execute(items: executionItems, preRecordedOrigin: originPos)
                    }
                }
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
        let content = ShortKingParser.generateScript(triggers: macro.triggers, actionItems: macro.actionItems, isEnabled: macro.isEnabled)
        let fileURL = macro.fileURL
        let trigger = macro.trigger
        
        self.isSavingInternally = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            try? content.write(to: fileURL, atomically: true, encoding: .utf8)
            updateMacroFinderIcon(for: fileURL, trigger: trigger)
            
            DispatchQueue.main.async {
                self.registerAllCarbonHotKeys()
                // Reset saving flag after disk latency window
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.isSavingInternally = false
                }
            }
        }
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
        loadMacros()
    }

    func createNewMacro(inFolder parentURL: URL? = nil) {
        var targetDir = watchDirectoryURL
        
        if let parent = parentURL {
            targetDir = parent
        } else if let selectedPath = selectedFilePath {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: selectedPath, isDirectory: &isDir) {
                if isDir.boolValue {
                    targetDir = URL(fileURLWithPath: selectedPath)
                } else {
                    targetDir = URL(fileURLWithPath: selectedPath).deletingLastPathComponent()
                }
            }
        }
        
        let count = macros.count + 1
        let fileName = "macro \(count).shortking"
        let url = targetDir.appendingPathComponent(fileName)
        self.selectedFilePath = url.path
        let t = Trigger(keyCode: 40, requireCmd: true, requireShift: true, requireOption: false, requireControl: false)
        let a: [MacroAction] = []
        try? ShortKingParser.generateScript(triggers: [t], actions: a).write(to: url, atomically: true, encoding: .utf8)
        loadMacros()
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
            let screenH = NSScreen.main?.frame.height ?? 1080
            return CGPoint(x: cocoaPt.x, y: screenH - cocoaPt.y)
        }()
        DispatchQueue.global(qos: .userInitiated).async { InputSimulator.execute(items: items, preRecordedOrigin: originPos) }
    }
}

// ==========================================
// MARK: - Permission Manager (macOS Accessibility & Input Monitoring)
// ==========================================
