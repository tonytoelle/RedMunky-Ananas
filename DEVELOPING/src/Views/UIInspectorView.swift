import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon

struct UIInspectorView: View {
    @ObservedObject var inspector = AXInspectorManager.shared
    @ObservedObject var store = MacroStore.shared
    
    @State private var attributeSearchText: String = ""
    @State private var selectedTab: Int = 0 // 0: Attributes, 1: AI Prompt & Scripts
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
            // Permission Alert Banner if Accessibility not granted
            if !inspector.isAccessibilityGranted {
                permissionAlertBanner
            }
            
            // ═══════════════════════════════════════════════════
            // TOP TOOLBAR & APP SELECTOR
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
            // BOTTOM STATUS FOOTER WITH BIG COPY BUTTON
            // ═══════════════════════════════════════════════════
            bottomFooter
        }
        .frame(minWidth: 860, minHeight: 600)
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
    
    // MARK: - Permission Alert Banner
    private var permissionAlertBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(.yellow)
            
            Text("Accessibility permission is required for RedMunky Ananas to inspect other apps & context menus.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
            
            Button("Grant Permission") {
                inspector.requestAccessibilityPermission()
            }
            .buttonStyle(PlainButtonStyle())
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.yellow.opacity(0.25))
            .foregroundColor(.yellow)
            .cornerRadius(6)
            
            Button(action: {
                inspector.checkAccessibility()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Re-check permission status")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(red: 0.45, green: 0.25, blue: 0.05))
    }
    
    // MARK: - Top Toolbar
    private var topToolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Target App Badge / Icon
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
                        Text("Hover cursor over any application window or context menu…")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                
                Spacer()
                
                // Inspect Frontmost App Button
                Button(action: {
                    inspector.inspectFrontmostApp()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "macwindow.on.rectangle")
                            .font(.system(size: 11))
                        Text("Inspect Active App")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.purple.opacity(0.25))
                    .foregroundColor(.purple)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Inspect the frontmost active window and UI element")
                
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
                        Text("Highlight")
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
                        Text(inspector.isLocked ? "Locked (F10)" : "Lock (F10)")
                            .font(.system(size: 11, weight: .bold))
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
                .help("Freeze current element inspection anywhere on screen (Press F10)")
            }
            
            // Sub-bar: App Quick Picker
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    Text("Filter App:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Menu {
                        Button("Any App (Live Cursor)") {
                            inspector.selectedAppPID = nil
                            inspector.startInspecting()
                        }
                        Divider()
                        ForEach(inspector.runningApps) { app in
                            Button(app.name) {
                                inspector.selectedAppPID = app.pid
                                inspector.inspectApp(pid: app.pid)
                            }
                        }
                    } label: {
                        Text(inspector.selectedAppPID != nil ? (inspector.runningApps.first(where: { $0.pid == inspector.selectedAppPID })?.name ?? "Selected App") : "Any App (Live Cursor)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.cyan)
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text("Press F10 anywhere to Freeze / Unfreeze")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 2)
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
                        Text("Hover over any external app window to view AX hierarchy")
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
                    Text("AI Prompt & Scripts").tag(1)
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
                // TAB 1: AI Prompts, Scripts & Macro Integration
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
                        Text(attributeSearchText.isEmpty ? "Hover over any app element to view its accessibility attributes" : "No attributes matching \"\(attributeSearchText)\"")
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
    
    // MARK: - Scripts & AI Integration View
    private var scriptsAndIntegrationView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Natural Language / AI Direction Prompt Box
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.cyan)
                        Text("AI AUTOMATION & SHORTCUT PROMPT")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                        
                        Button(action: {
                            let prompt = inspector.generateNaturalLanguagePrompt()
                            copyToClipboard(text: prompt, message: "Copied Full AI Prompt & Location!")
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc.fill")
                                Text("Copy Prompt")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.cyan.opacity(0.2))
                            .foregroundColor(.cyan)
                            .cornerRadius(5)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    let aiPrompt = inspector.generateNaturalLanguagePrompt()
                    Text(aiPrompt)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.35))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                        )
                }
                
                // 2. RedMunky Ananas Macro Click Coordinate
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.yellow)
                        Text("REDMUNKY ANANAS MACRO ACTION")
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
                
                // 3. AppleScript / Context Menu Automation Snippet
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
                
                // 4. Swift AX Snippet
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
        HStack(spacing: 12) {
            // Status Dot & Message
            HStack(spacing: 8) {
                Circle()
                    .fill(inspector.isLocked ? Color.orange : (inspector.isInspecting ? Color.green : Color.gray))
                    .frame(width: 9, height: 9)
                
                Text(copyFeedbackText ?? inspector.statusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(copyFeedbackText != nil ? .green : .white.opacity(0.7))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // ═══════════════════════════════════════════════════
            // PROMINENT BIG COPY AI PROMPT / LOCATION BUTTON (KANAN BAWAH)
            // ═══════════════════════════════════════════════════
            Button(action: {
                let prompt = inspector.generateNaturalLanguagePrompt()
                copyToClipboard(text: prompt, message: "📋 Copied Natural Language / AI Direction Prompt!")
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Copy AI Prompt / Location")
                            .font(.system(size: 12, weight: .bold))
                        Text("Natural language description to direct AI / shortcuts")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.15, green: 0.55, blue: 0.95),
                            Color(red: 0.35, green: 0.25, blue: 0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(8)
                .shadow(color: Color.blue.opacity(0.4), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Copy ready-to-use natural language location & directions for AI or keyboard shortcut creation")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.35))
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
