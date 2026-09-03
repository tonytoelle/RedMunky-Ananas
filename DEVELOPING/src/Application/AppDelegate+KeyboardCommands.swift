import Cocoa

extension AppDelegate {
    func installDeleteKeyMonitor() {
        deleteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Self.isEditingText {
                return event
            }

            let characters = event.charactersIgnoringModifiers?.lowercased()
            let hasCommand = event.modifierFlags.contains(.command)

            if hasCommand && characters == "z" {
                let undoManager = MacroStore.shared.undoManager
                if event.modifierFlags.contains(.shift), undoManager.canRedo {
                    undoManager.redo()
                    return nil
                }
                if undoManager.canUndo {
                    undoManager.undo()
                    return nil
                }
            }

            if event.keyCode == 51 || event.keyCode == 117 {
                if !MacroStore.shared.selectedActionIDs.isEmpty {
                    MacroStore.shared.deleteSelectedActions()
                    return nil
                }
            }

            if hasCommand && characters == "c" {
                if !MacroStore.shared.selectedActionIDs.isEmpty,
                   let selectedMacro = MacroStore.shared.selectedMacro {
                    let selectedItems = selectedMacro.actionItems.filter {
                        MacroStore.shared.selectedActionIDs.contains($0.id)
                    }
                    if !selectedItems.isEmpty {
                        MacroStore.shared.copiedActions = selectedItems
                        MacroStore.shared.copiedMacroURL = nil
                        return nil
                    }
                }

                if let selectedPath = MacroStore.shared.selectedFilePath {
                    MacroStore.shared.copiedMacroURL = URL(fileURLWithPath: selectedPath)
                    MacroStore.shared.copiedActions = []
                    return nil
                }
            }

            if hasCommand && characters == "v" {
                if !MacroStore.shared.copiedActions.isEmpty,
                   let selectedMacro = MacroStore.shared.selectedMacro {
                    MacroStore.shared.registerUndoState(for: selectedMacro)
                    let pastedItems = MacroStore.shared.copiedActions.map {
                        MacroActionItem(action: $0.action, repeatCount: $0.repeatCount)
                    }

                    if let selectedID = MacroStore.shared.lastSelectedActionID,
                       let index = selectedMacro.actionItems.firstIndex(where: { $0.id == selectedID }) {
                        selectedMacro.actionItems.insert(contentsOf: pastedItems, at: index + 1)
                    } else {
                        selectedMacro.actionItems.append(contentsOf: pastedItems)
                    }
                    MacroStore.shared.saveMacro(selectedMacro)
                    return nil
                }

                if MacroStore.shared.copiedMacroURL != nil {
                    MacroStore.shared.pasteCopiedMacro(toFolder: Self.pasteDestination)
                    return nil
                }
            }

            return event
        }
    }

    private static var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if let textView = responder as? NSTextView {
            return textView.isEditable
        }
        if let textField = responder as? NSTextField {
            return textField.isEditable
        }
        return false
    }

    private static var pasteDestination: URL {
        if let folderPath = MacroStore.shared.selectedFolderPath {
            return URL(fileURLWithPath: folderPath)
        }
        if let filePath = MacroStore.shared.selectedFilePath {
            return URL(fileURLWithPath: filePath).deletingLastPathComponent()
        }
        return MacroStore.shared.watchDirectoryURL
    }

    @objc func undoAction(_ sender: Any?) {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.isEditable,
           let undoManager = textView.undoManager,
           undoManager.canUndo {
            undoManager.undo()
            return
        }
        if MacroStore.shared.undoManager.canUndo {
            MacroStore.shared.undoManager.undo()
        }
    }

    @objc func redoAction(_ sender: Any?) {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.isEditable,
           let undoManager = textView.undoManager,
           undoManager.canRedo {
            undoManager.redo()
            return
        }
        if MacroStore.shared.undoManager.canRedo {
            MacroStore.shared.undoManager.redo()
        }
    }

    @objc func deleteSelectedActionFromMenu(_ sender: Any?) {
        guard !MacroStore.shared.selectedActionIDs.isEmpty else { return }
        MacroStore.shared.deleteSelectedActions()
    }
}
