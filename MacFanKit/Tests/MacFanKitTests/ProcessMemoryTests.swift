import Darwin
import Foundation
import Testing

@testable import MacFanKit

struct ProcessMemoryTests {
    @Test func listsTheCurrentProcessWithItsCommandLine() throws {
        let current = try #require(ProcessMemory.all().first { $0.pid == getpid() })
        #expect(current.footprintBytes > 0)
        #expect(current.path == Bundle.main.executablePath.map { URL(filePath: $0).resolvingSymlinksInPath().path })
        #expect(current.name == URL(filePath: CommandLine.arguments[0]).lastPathComponent)
        #expect(current.arguments == Array(CommandLine.arguments.dropFirst()))
    }

    @Test func leavesOutOtherUsersProcesses() {
        #expect(!ProcessMemory.all().contains { $0.pid == 1 })
    }

    @Test func parsesTheArgumentsAfterThePaddedExecutablePath() {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: Int32(3)) { bytes += $0 }
        bytes += Array("/usr/bin/tool".utf8) + [0, 0, 0, 0]
        bytes += Array("tool".utf8) + [0] + [0] + Array("--flag".utf8) + [0]
        bytes += Array("PATH=/usr/bin".utf8) + [0]
        #expect(ProcessMemory.parseCommandLine(bytes[...]) == ["tool", "", "--flag"])
        #expect(ProcessMemory.parseCommandLine([1, 0][...]) == nil)
    }

    @Test func findsTheAppsAroundAnExecutable() {
        let helper =
            "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/"
            + "Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        #expect(
            ProcessMemory.appBundlePaths(containing: helper) == [
                "/Applications/Google Chrome.app",
                "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/"
                    + "Google Chrome Helper (Renderer).app",
            ])
        #expect(ProcessMemory.appBundlePaths(containing: "/opt/homebrew/bin/node") == [])
        #expect(ProcessMemory.appBundlePaths(containing: "/Users/me/bin/odd.app") == [])
    }

    @Test func summarizesAJavaProgramFromItsMainClass() {
        let gradle = [
            "-Xmx2048m", "--add-opens=java.base/java.lang=ALL-UNNAMED", "-cp", "/gradle/lib/gradle-daemon-main.jar",
            "-javaagent:/gradle/lib/agent.jar", "org.gradle.launcher.daemon.bootstrap.GradleDaemon", "9.1.0",
        ]
        #expect(ProcessMemory.summary(name: "java", arguments: gradle) == "GradleDaemon 9.1.0")
        let jar = ["-jar", "/srv/app.jar", "--port", "80"]
        #expect(ProcessMemory.summary(name: "java", arguments: jar) == "app.jar --port 80")
        #expect(ProcessMemory.summary(name: "java", arguments: ["--module", "app/com.example.Main"]) == "Main")
        #expect(ProcessMemory.summary(name: "java", arguments: ["-version"]) == "-version")
        #expect(ProcessMemory.summary(name: "codex", arguments: ["app-server", "--listen"]) == "app-server --listen")
    }

    @Test func signalsTheProcessItWasReadFrom() throws {
        let sleeper = try startSleeping()
        let process = try #require(ProcessMemory.all().first { $0.pid == sleeper.processIdentifier })
        #expect(process.name == "sleep")
        #expect(process.arguments == ["30"])
        try process.send(SIGTERM)
        sleeper.waitUntilExit()
        #expect(sleeper.terminationReason == .uncaughtSignal)
        #expect(sleeper.terminationStatus == SIGTERM)
        try process.send(SIGTERM)
    }

    @Test func leavesAloneAProcessThatReusedTheID() throws {
        let sleeper = try startSleeping()
        defer { sleeper.terminate() }
        let process = try #require(ProcessMemory.all().first { $0.pid == sleeper.processIdentifier })
        let earlier = ProcessMemory(
            id: .init(pid: process.pid, startTime: process.id.startTime - 1), name: process.name, path: process.path,
            arguments: process.arguments, footprintBytes: process.footprintBytes)
        try earlier.send(SIGTERM)
        #expect(sleeper.isRunning)
    }

    private func startSleeping() throws -> Process {
        let sleeper = Process()
        sleeper.executableURL = URL(filePath: "/bin/sleep")
        sleeper.arguments = ["30"]
        try sleeper.run()
        return sleeper
    }
}
