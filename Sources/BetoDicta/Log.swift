import Foundation

// MARK: - Registro simple (~/.betodicta/betodicta.log) para diagnosticar sin adivinar

enum Log {
    static func write(_ message: String) {
        let url = Config.dir.appendingPathComponent("betodicta.log")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        if let handle = FileHandle(forWritingAtPath: url.path) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
