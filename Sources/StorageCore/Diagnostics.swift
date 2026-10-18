import Foundation

public enum Diagnostics {
    public static func run(executable: String, arguments: [String]) throws -> String {
        let task = Process(); task.executableURL = URL(fileURLWithPath: executable); task.arguments = arguments
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = pipe
        try task.run()
        let timeout = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
        defer { timeout.cancel() }
        let output = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
        return "종료 코드: \(task.terminationStatus)\n" + String(decoding: output, as: UTF8.self)
    }
    public static func snapshots() -> String {
        var lines: [String] = []
        for path in ["/", "/System/Volumes/Data"] {
            lines.append("\n볼륨: \(path)\n" + ((try? run(executable: "/usr/sbin/diskutil", arguments: ["apfs", "listSnapshots", path])) ?? "APFS 스냅샷 조회 불가"))
        }
        lines.append((try? run(executable: "/usr/bin/tmutil", arguments: ["listlocalsnapshots", "/"])) ?? "Time Machine 조회 불가")
        return lines.joined(separator: "\n")
    }
    public static func simulators() -> String {
        (try? run(executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "-j"])) ?? "Xcode 도구를 사용할 수 없습니다."
    }
    public static func maskedReport(_ report: ScanReport, home: String = FileManager.default.homeDirectoryForCurrentUser.path) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let original = String(decoding: try encoder.encode(report), as: UTF8.self)
        // Mask all user homes, including other users discovered by a full scan.
        let masked = original.replacingOccurrences(of: #"(?:/System/Volumes/Data)?/Users/[^/\"\s]+"#, with: "<USER>", options: .regularExpression)
            .replacingOccurrences(of: home, with: "<HOME>")
        return Data(masked.utf8)
    }
}
