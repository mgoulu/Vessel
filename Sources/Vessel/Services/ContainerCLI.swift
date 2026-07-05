import Foundation

struct ContainerCLI: Sendable {
    private let decoder = JSONDecoder()

    func systemStatus() throws -> String {
        try CommandRunner.run(["system", "status"]).stdout
    }

    func startSystem() throws {
        _ = try CommandRunner.run(["system", "start"], timeout: 60)
    }

    func stopSystem() throws {
        _ = try CommandRunner.run(["system", "stop"], timeout: 60)
    }

    func listContainers() throws -> [ContainerRecord] {
        let output = try CommandRunner.run(["ls", "--all", "--format", "json"]).stdout
        return try decoder.decode([ContainerRecord].self, from: Data(output.utf8))
    }

    func stats() throws -> [ContainerStats] {
        let output = try CommandRunner.run(["stats", "--no-stream", "--format", "json"]).stdout
        return try decoder.decode([ContainerStats].self, from: Data(output.utf8))
    }

    func images() throws -> [ImageRecord] {
        let output = try CommandRunner.run(["image", "ls", "--format", "json"]).stdout
        return try decoder.decode([ImageRecord].self, from: Data(output.utf8))
    }

    func inspect(containerID: String) throws -> String {
        try CommandRunner.run(["inspect", containerID]).stdout
    }

    func logs(containerID: String, lines: Int = 240) throws -> String {
        try CommandRunner.run(["logs", "-n", String(lines), containerID], timeout: 10).stdout
    }

    func processes(containerID: String) throws -> [ServiceProcess] {
        let script = "ps -o pid,ppid,user,stat,%cpu,%mem,comm,args 2>/dev/null || ps -o pid,ppid,user,stat,comm,args"
        let output = try CommandRunner.run(["exec", containerID, "sh", "-lc", script], timeout: 10).stdout
        return ProcessListParser.parse(output)
    }

    func start(containerID: String) throws {
        _ = try CommandRunner.run(["start", containerID], timeout: 60)
    }

    func stop(containerID: String) throws {
        _ = try CommandRunner.run(["stop", containerID], timeout: 60)
    }

    func kill(containerID: String) throws {
        _ = try CommandRunner.run(["kill", containerID], timeout: 20)
    }

    func delete(containerID: String) throws {
        _ = try CommandRunner.run(["rm", containerID], timeout: 20)
    }

    func runDetached(image: String, name: String, command: String) throws {
        var args = ["run", "-d"]
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args += ["--name", name]
        }
        args.append(image)
        if !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args += ["sh", "-lc", command]
        }
        _ = try CommandRunner.run(args, timeout: 120)
    }
}

enum ProcessListParser {
    static func parse(_ text: String) -> [ServiceProcess] {
        let lines = text
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard let header = lines.first else { return [] }
        let hasCPU = header.localizedCaseInsensitiveContains("%CPU")

        return lines.dropFirst().compactMap { line in
            let parts = line.split(separator: " ", maxSplits: hasCPU ? 7 : 5, omittingEmptySubsequences: true).map(String.init)
            if hasCPU, parts.count >= 8 {
                return ServiceProcess(
                    pid: parts[0],
                    parentPID: parts[1],
                    user: parts[2],
                    state: parts[3],
                    cpu: parts[4],
                    memory: parts[5],
                    command: parts[6],
                    arguments: parts[7]
                )
            }
            if !hasCPU, parts.count >= 6 {
                return ServiceProcess(
                    pid: parts[0],
                    parentPID: parts[1],
                    user: parts[2],
                    state: parts[3],
                    cpu: nil,
                    memory: nil,
                    command: parts[4],
                    arguments: parts[5]
                )
            }
            return nil
        }
    }
}
