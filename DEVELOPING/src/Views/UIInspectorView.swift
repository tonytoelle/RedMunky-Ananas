import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon

struct UIInspectorView: View {
    @ObservedObject var inspector = AXInspectorManager.shared
    @ObservedObject var store = MacroStore.shared
    
    @State private var attributeSearchText: String = ""
    @State private var selectedTab: Int = 0 // 0: Attributes, 1: Scripts & Actions
    @State private var copyFeedbackText: String? = nil
    
    var filteredAttributes: [(key: String, value: String)] {
        if attributeSearchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return inspector.attributes
        }
        let q = attributeSearchText.lowercased()
        return inspector.attributes.filter {
            $0.key.lowercased().contains(q) || $0.value.lowercased().contains(q)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ═══════════════════════════════════════════════════
            // TOP TOOLBAR & STATUS BAR
            // ═══════════════════════════════════════════════════
            topToolbar
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            // ═══════════════════════════════════════════════════
            // MAIN CONTENT (SPLIT VIEW)
            // ═══════════════════════════════════════════════════
            HSplitView {
                // LEFT PANE: Hierarchy, Element Overview, Actions
                leftHierarchyPane
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 460)
                
                // RIGHT PANE: Attributes & Code Generators
                rightDetailsPane
                    .frame(minWidth: 420)
            }
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            // ═══════════════════════════════════════════════════
            // BOTTOM STATUS FOOTER
            // ═══════════════════════════════════════════════════
            bottomFooter
        }
        .frame(minWidth: 800, minHeight: 560)
        .background(
            ZStack {
                Color(red: 0.11, green: 0.11, blue: 0.14)
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.17, blue: 0.24).opacity(0.4),
                        Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        )
        .onAppear {
            inspector.startInspecting()
        }
        .onDisappear {
            inspector.stopInspecting()
        }
    }
    
    // MARK: - Top Toolbar
    private var topToolbar: some View {
        HStack(spacing: 12) {
            // Target App Badge
            if let app = inspector.targetApp {
                HStack(spacing: 8) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 6) {
                            Text("PID: \(app.pid)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                            
                            if let bundle = app.bundleIdentifier {
                                Text("• \(bundle)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.4))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .cornerRadius(8)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Hover cursor over any app element…")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            
            Spacer()
            
            // Cursor Location Pill
            HStack(spacing: 5) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                Text("X: \(Int(inspector.currentMousePosition.x)), Y: \(Int(inspector.currentMousePosition.y))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.3))
            .cornerRadius(6)
            
            // Highlight Bounds Toggle
            Button(action: {
                inspector.highlightOnScreen.toggle()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: inspector.highlightOnScreen ? "eye.fill" : "eye.slash")
                        .font(.system(size: 12))
                    Text("Highlight Frame")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(inspector.highlightOnScreen ? Color.green.opacity(0.2) : Color.white.opacity(0.06))
                .foregroundColor(inspector.highlightOnScreen ? .green : .white.opacity(0.7))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Draw a visual boundary around the inspected element on your screen")
            
            // Lock / Freeze Toggle Button
            Button(action: {
                inspector.toggleLock()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: inspector.isLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 12))
                    Text(inspector.isLocked ? "Locked (Space)" : "Lock Element (Space)")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(inspector.isLocked ? Color.orange.opacity(0.3) : Color.blue.opacity(0.25))
                .foregroundColor(inspector.isLocked ? .orange : Color(red: 0.35, green: 0.75, blue: 1.0))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(inspector.isLocked ? Color.orange.opacity(0.6) : Color.blue.opacity(0.5), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .help("Freeze current element inspection (Press Spacebar)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.2))
    }
    
    // MARK: - Left Hierarchy Pane
    private var leftHierarchyPane: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Ancestor Chain / Hierarchy
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                        Text("AX HIERARCHY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                    }
                    
                    if inspector.hierarchy.isEmpty {
                        Text("No hierarchy detected")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.vertical, 6)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(inspector.hierarchy.enumerated()), id: \.offset) { index, node in
                                Button(action: {
                                    inspector.selectHierarchyNode(node)
                                }) {
                                    HStack(spacing: 6) {
                                        // Indentation line
                                        Rectangle()
                                            .fill(index == inspector.hierarchy.count - 1 ? Color.green : Color.white.opacity(0.15))
                                            .frame(width: 2, height: 16)
                                            .padding(.leading, CGFloat(index * 10))
                                        
                                        // Role badge
                                        Text(node.roleShort)
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(
                                                index == inspector.hierarchy.count - 1
                                                ? Color.green.opacity(0.25)
                                                : Color.white.opacity(0.08)
                                            )
                                            .foregroundColor(
                                                index == inspector.hierarchy.count - 1
                                                ? Color.green
                                                : Color.white.opacity(0.8)
                                            )
                                            .cornerRadius(4)
                                        
                                        if let title = node.title, !title.isEmpty {
                                            Text("\"\(title)\"")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                        } else if let sub = node.subrole {
                                            Text("(\(sub.replacingOccurrences(of: "AX", with: "")))")
                                                .font(.system(size: 10))
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 6)
                                    .background(
                                        index == inspector.hierarchy.count - 1
                                        ? Color.white.opacity(0.08)
                                        : Color.clear
                                    )
                                    .cornerRadius(6)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.25))
                        .cornerRadius(8)
                    }
                }
                
                // 2. Selected Element Overview Card
                if let element = inspector.currentElement {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "square.dashed.inset.filled")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                            Text("ELEMENT PROPERTIES")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Role:")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                                    .frame(width: 65, alignment: .leading)
                                Text(element.role)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                            
                            if let subrole = element.subrole {
                                HStack {
                                    Text("Subrole:")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.5))
                                        .frame(width: 65, alignment: .leading)
                                    Text(subrole)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.85))
                                }
                            }
                            
                            if let title = element.title, !title.isEmpty {
                                HStack {
                                    Text("Title:")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.5))
                                        .frame(width: 65, alignment: .leading)
                                    Text("\"\(title)\"")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.yellow)
                                }
                            }
                            
                            if let desc = element.description, !desc.isEmpty {
                                HStack {
                                    Text("Desc:")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.5))
                                        .frame(width: 65, alignment: .leading)
                                    Text(desc)
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            
                            if let val = element.value, !val.isEmpty {
                                HStack {
                                    Text("Value:")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.5))
                                        .frame(width: 65, alignment: .leading)
                                    Text(val)
                                        .font(.system(size: 11))
                                        .foregroundColor(.cyan)
                                }
                            }
                            
                            if let id = element.identifier, !id.isEmpty {
                                HStack {
                                    Text("ID:")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.5))
                                        .frame(width: 65, alignment: .leading)
                                    Text(id)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.purple)
                                }
                            }
                            
                            if let frame = element.frame {
                                HStack {
                                    Text("Bounds:")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.5))
                                        .frame(width: 65, alignment: .leading)
                                    Text("x:\(Int(frame.origin.x)), y:\(Int(frame.origin.y)), w:\(Int(frame.width)), h:\(Int(frame.height))")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.75))
                                }
                                
                                HStack {
                                    Text("Center:")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.5))
                                        .frame(width: 65, alignment: .leading)
                                    Text("(\(Int(frame.midX)), \(Int(frame.midY)))")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(8)
                    }
                }
                
                // 3. Available Actions Explorer & Click Tester
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "bolt.badge.play")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text("AVAILABLE AX ACTIONS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                    }
                    
                    if inspector.actions.isEmpty {
                        Text("No direct accessibility actions exposed by this element")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(inspector.actions, id: \.self) { action in
                                HStack {
                                    Text(action)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.9))
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        inspector.performAction(action)
                                    }) {
                                        HStack(spacing: 3) {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 8))
                                            Text("Trigger")
                                                .font(.system(size: 10, weight: .semibold))
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.2))
                                        .foregroundColor(.orange)
                                        .cornerRadius(5)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(6)
                            }
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.25))
                        .cornerRadius(8)
                    }
                    
                    if let status = inspector.lastActionStatus {
                        Text(status)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.green)
                            .padding(.top, 2)
                    }
                }
                
                // 4. Children Elements (Sub-elements)
                if !inspector.children.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "folder.badge.gearshape")
                                .font(.system(size: 11))
                                .foregroundColor(.purple)
                            Text("CHILDREN (\(inspector.children.count))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(inspector.children) { child in
                                Button(action: {
                                    inspector.selectHierarchyNode(child)
                                }) {
                                    HStack(spacing: 6) {
                                        Text(child.roleShort)
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1.5)
                                            .background(Color.purple.opacity(0.25))
                                            .foregroundColor(.purple)
                                            .cornerRadius(3)
                                        
                                        Text(child.displayName)
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.85))
                                            .lineLimit(1)
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8))
                                            .foregroundColor(.white.opacity(0.3))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.white.opacity(0.03))
                                    .cornerRadius(4)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(6)
                        .background(Color.black.opacity(0.25))
                        .cornerRadius(8)
                    }
                }
            }
            .padding(12)
        }
        .background(Color.black.opacity(0.15))
    }
    
    // MARK: - Right Details Pane
    private var rightDetailsPane: some View {
        VStack(spacing: 0) {
            // Segmented Tab Picker
            HStack(spacing: 12) {
                Picker("", selection: $selectedTab) {
                    Text("Attributes (\(inspector.attributes.count))").tag(0)
                    Text("Shortcuts & Scripts").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 260)
                
                Spacer()
                
                if selectedTab == 0 {
                    // Search Bar
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                        TextField("Filter attributes…", text: $attributeSearchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                        if !attributeSearchText.isEmpty {
                            Button(action: { attributeSearchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(6)
                    .frame(width: 180)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.1))
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            if selectedTab == 0 {
                // TAB 0: Attributes Table
                attributesTableView
            } else {
                // TAB 1: Scripts & Macro Integration
                scriptsAndIntegrationView
            }
        }
    }
    
    // MARK: - Attributes Table View
    private var attributesTableView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 2) {
                if filteredAttributes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.2))
                        Text(attributeSearchText.isEmpty ? "Hover over an element to view its accessibility attributes" : "No attributes matching \"\(attributeSearchText)\"")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    ForEach(filteredAttributes, id: \.key) { attr in
                        HStack(alignment: .top, spacing: 8) {
                            Text(attr.key)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(red: 0.4, green: 0.75, blue: 1.0))
                                .frame(width: 170, alignment: .leading)
                                .lineLimit(1)
                            
                            Text(attr.value)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Button(action: {
                                copyToClipboard(text: attr.value, message: "Copied '\(attr.key)' value")
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Copy value")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.02))
                        .cornerRadius(4)
                    }
                }
            }
            .padding(12)
        }
    }
    
    // MARK: - Scripts & Integration View
    private var scriptsAndIntegrationView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                // 1. ShortKing Macro Click Coordinate
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.yellow)
                        Text("SHORTKING MACRO ACTION")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                    }
                    
                    if let element = inspector.currentElement, let frame = element.frame {
                        let centerX = Int(frame.midX)
                        let centerY = Int(frame.midY)
                        let macroCode = "click(x: \(centerX), y: \(centerY))"
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Coordinates:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.5))
                                Text("X: \(centerX), Y: \(centerY)")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.green)
                                Spacer()
                            }
                            
                            HStack(spacing: 8) {
                                Button(action: {
                                    copyToClipboard(text: macroCode, message: "Copied Macro Click Action")
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.doc")
                                        Text("Copy Click Action")
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                if let selectedMacro = store.selectedMacro {
                                    Button(action: {
                                        let actionItem = MacroActionItem(action: .click(point: CGPoint(x: centerX, y: centerY), button: .left))
                                        store.registerUndoState(for: selectedMacro)
                                        selectedMacro.actionItems.append(actionItem)
                                        store.saveMacro(selectedMacro)
                                        showBanner("Added Click (\(centerX), \(centerY)) to '\(selectedMacro.fileName)'")
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus.circle.fill")
                                            Text("Insert into '\(selectedMacro.fileName)'")
                                        }
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundColor(.green)
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(8)
                    } else {
                        Text("No element frame detected")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                
                // 2. AppleScript / Context Menu Automation Snippet
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "applescript.fill")
                            .foregroundColor(.orange)
                        Text("APPLESCRIPT / RESOLVE AUTOMATION")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        
                        Button(action: {
                            let script = inspector.generateAppleScriptSnippet()
                            copyToClipboard(text: script, message: "Copied AppleScript snippet")
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy Script")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.orange)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    let appleScript = inspector.generateAppleScriptSnippet()
                    Text(appleScript)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.35))
                        .cornerRadius(8)
                }
                
                // 3. Swift AX Snippet
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "swift")
                            .foregroundColor(.red)
                        Text("SWIFT ACCESSIBILITY SNIPPET")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        
                        Button(action: {
                            let swiftCode = inspector.generateSwiftSnippet()
                            copyToClipboard(text: swiftCode, message: "Copied Swift snippet")
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy Swift")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    let swiftSnippet = inspector.generateSwiftSnippet()
                    Text(swiftSnippet)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.35))
                        .cornerRadius(8)
                }
            }
            .padding(14)
        }
    }
    
    // MARK: - Bottom Footer
    private var bottomFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(inspector.isLocked ? Color.orange : (inspector.isInspecting ? Color.green : Color.gray))
                .frame(width: 8, height: 8)
            
            Text(copyFeedbackText ?? inspector.statusMessage)
                .font(.system(size: 11))
                .foregroundColor(copyFeedbackText != nil ? .green : .white.opacity(0.6))
                .lineLimit(1)
            
            Spacer()
            
            Text("ShortKing UI Inspector • Press Spacebar to freeze inspection")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.3))
    }
    
    // MARK: - Helpers
    private func copyToClipboard(text: String, message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showBanner(message)
    }
    
    private func showBanner(_ message: String) {
        copyFeedbackText = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if copyFeedbackText == message {
                copyFeedbackText = nil
            }
        }
    }
}
