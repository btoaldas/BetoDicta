import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Reemplazos (palabra completa, sin distinguir mayúsculas)

func applyReplacements(_ text: String) -> String {
    var result = text
    let rules = Config.replacements().sorted { $0.original.count > $1.original.count }
    for rule in rules {
        if rule.isRegex == true {
            if let regex = try? NSRegularExpression(pattern: rule.original, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range,
                                                        withTemplate: rule.replacement)
            }
            continue
        }
        let variants = rule.original.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        for variant in variants {
            let escaped = NSRegularExpression.escapedPattern(for: variant)
            let pattern = "(?<![\\p{L}\\p{N}])" + escaped + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, options: [], range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: rule.replacement))
        }
    }
    return result
}

