import OSLog

/// os.Logger + file log parity with the Python app (~/Library/Logs/
/// EconomicCalendar/widget.log when bundled, ./data/widget.log in dev).
final class AppLog: @unchecked Sendable {
    static let shared = AppLog()

    private let osLog = Logger(subsystem: "com.economiccalendar.widget", category: "app")
    private let queue = DispatchQueue(label: "com.economiccalendar.widget.applog")
    private let fileHandle: FileHandle?

    private init() {
        let path = AppPaths.logFile
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        fileHandle = FileHandle(forWritingAtPath: path)
    }

    private func write(level: String, _ message: String) {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let line = "\(f.string(from: Date())) \(level) \(message)\n"
        switch level {
        case "ERROR": osLog.error("\(message, privacy: .public)")
        case "DEBUG": osLog.debug("\(message, privacy: .public)")
        default: osLog.info("\(message, privacy: .public)")
        }
        queue.async { [fileHandle] in
            guard let fileHandle else { return }
            fileHandle.seekToEndOfFile()
            fileHandle.write(Data(line.utf8))
        }
    }

    func info(_ message: String) { write(level: "INFO", message) }
    func error(_ message: String) { write(level: "ERROR", message) }
    func debug(_ message: String) { write(level: "DEBUG", message) }
}
