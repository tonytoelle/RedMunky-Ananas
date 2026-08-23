import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

enum FileSystemNode: Identifiable {
    case folder(name: String, url: URL, config: FolderConfig, children: [FileSystemNode])
    case macro(item: MacroItem)

    var id: String {
        switch self {
        case .folder(_, let url, _, _): return "folder:" + url.path
        case .macro(let item): return "macro:" + item.fileURL.path
        }
    }

    var name: String {
        switch self {
        case .folder(let name, _, _, _): return name
        case .macro(let item): return item.fileName.replacingOccurrences(of: ".shortking", with: "")
        }
    }

    var isFolder: Bool {
        switch self {
        case .folder: return true
        case .macro: return false
        }
    }

    var folderURL: URL? {
        switch self {
        case .folder(_, let url, _, _): return url
        case .macro: return nil
        }
    }

    var folderConfig: FolderConfig? {
        switch self {
        case .folder(_, _, let config, _): return config
        case .macro: return nil
        }
    }
}

// ==========================================
// MARK: - Macro Store with Hierarchical Folder Tree
// ==========================================
