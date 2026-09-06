import Foundation

/// Opt-in local timing only; no window names, content, or network output.
enum SwitchTrace {
    private static let path: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--trace-switches"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }()
    private static let queue = DispatchQueue(label: "WindowPilot.switch-trace", qos: .utility)
    static func mark(_ stage: String) {
        guard let path else { return }
        let line = "\(DispatchTime.now().uptimeNanoseconds) \(stage)\n"
        queue.async {
            if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
            guard let file = FileHandle(forWritingAtPath: path) else { return }
            defer { try? file.close() }
            do { try file.seekToEnd(); try file.write(contentsOf: Data(line.utf8)) } catch { }
        }
    }
}
