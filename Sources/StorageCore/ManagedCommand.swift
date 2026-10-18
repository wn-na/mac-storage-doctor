import Foundation
import Darwin

public struct CommandResult: Sendable {
    public let status: Int32
    public let output: String
}
public enum ManagedCommand {
    public static func displayArgument(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Runs an absolute executable without a shell. Output and elapsed time are bounded.
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 60) throws -> CommandResult {
        guard executable.hasPrefix("/") else { throw CleanupError.blocked("도구의 절대 경로가 필요합니다.") }
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        var environment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                           "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin", "LANG": "en_US.UTF-8"]
        let java = "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
        if FileManager.default.fileExists(atPath: java) { environment["JAVA_HOME"] = java }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        let fd = pipe.fileHandleForReading.fileDescriptor
        guard fcntl(fd, F_SETFL, O_NONBLOCK) != -1 else { throw CleanupError.blocked("도구 출력 연결 실패") }
        try process.run()
        try? pipe.fileHandleForWriting.close()
        defer { try? pipe.fileHandleForReading.close() }
        let started = ProcessInfo.processInfo.systemUptime
        var output = Data(), buffer = [UInt8](repeating: 0, count: 16384)
        func drain() throws {
            while true {
                let size = Darwin.read(fd, &buffer, buffer.count)
                if size <= 0 { break }
                guard output.count + size <= 8 * 1024 * 1024 else { throw CleanupError.blocked("도구 출력이 제한을 초과했습니다.") }
                output.append(contentsOf: buffer.prefix(size))
            }
        }
        do {
            while process.isRunning {
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.systemUptime - started < timeout else { throw CleanupError.blocked("도구 실행 시간이 초과되었습니다. 상태를 새로고침하세요.") }
                try drain(); Thread.sleep(forTimeInterval: 0.03)
            }
            process.waitUntilExit(); try drain()
        } catch {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit(); throw error
        }
        return CommandResult(status: process.terminationStatus, output: String(decoding: output, as: UTF8.self))
    }
    public static func checked(_ executable: String, _ arguments: [String], timeout: TimeInterval = 60) throws -> String {
        let result = try run(executable, arguments, timeout: timeout)
        guard result.status == 0 else {
            throw CleanupError.blocked("도구 종료 코드 \(result.status): \(result.output.suffix(3000))")
        }
        return result.output
    }
    public static func requireIdle(owners: [String]) throws {
        let commands = try checked("/bin/ps", ["-axo", "comm="]).lowercased()
        for owner in owners where commands.contains(owner.lowercased()) {
            throw CleanupError.blocked("\(owner) 작업을 종료하고 다시 시도하세요.")
        }
    }
}
