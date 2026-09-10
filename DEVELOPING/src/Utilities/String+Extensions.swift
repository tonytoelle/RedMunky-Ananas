import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

// ==========================================
// MARK: - Fuzzy Search Utilities
// ==========================================
func levenshteinDistance(_ a: String, _ b: String) -> Int {
    let aChars = Array(a)
    let bChars = Array(b)
    let n = aChars.count
    let m = bChars.count
    if n == 0 { return m }
    if m == 0 { return n }
    
    var matrix = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
    for i in 0...n { matrix[i][0] = i }
    for j in 0...m { matrix[0][j] = j }
    
    for i in 1...n {
        for j in 1...m {
            let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
            matrix[i][j] = min(
                matrix[i - 1][j] + 1,
                matrix[i][j - 1] + 1,
                matrix[i - 1][j - 1] + cost
            )
        }
    }
    return matrix[n][m]
}

func fuzzyMatch(_ query: String, in target: String, tolerance: Int = 3) -> (matches: Bool, score: Int) {
    let q = query.lowercased()
    let t = target.lowercased()
    
    // Exact substring match = best score
    if t.contains(q) { return (true, 0) }
    
    // Prefix match
    if t.hasPrefix(q) { return (true, 0) }
    
    // Levenshtein distance on whole strings
    let dist = levenshteinDistance(q, t)
    if dist <= tolerance { return (true, dist) }
    
    // Check if query is a fuzzy prefix (distance of query to any prefix of target)
    if q.count <= t.count {
        let prefix = String(t.prefix(q.count))
        let prefixDist = levenshteinDistance(q, prefix)
        if prefixDist <= tolerance { return (true, prefixDist) }
    }
    
    // Word-level matching: check query against each word in target
    let words = t.split(separator: " ").map(String.init)
    for word in words {
        let wordDist = levenshteinDistance(q, word)
        if wordDist <= tolerance { return (true, wordDist + 1) }
    }
    
    return (false, Int.max)
}

// ==========================================
extension String {
    func toTitleCase() -> String {
        let formatted = self.replacingOccurrences(of: "_", with: " ")
                            .replacingOccurrences(of: "-", with: " ")
        return formatted.capitalized
    }
    
    func wrapWords(maxWordsPerLine: Int = 3) -> String {
        let words = self.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard words.count > maxWordsPerLine else { return self }
        var lines: [String] = []
        for i in stride(from: 0, to: words.count, by: maxWordsPerLine) {
            let end = min(i + maxWordsPerLine, words.count)
            lines.append(words[i..<end].joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }
}
