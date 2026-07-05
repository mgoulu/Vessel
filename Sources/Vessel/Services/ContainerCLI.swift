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
        // Prefer ps; slim images often ship without it, so fall back to /proc,
        // which always exists. Tab-delimited because comm may contain spaces.
        let script = """
        if command -v ps >/dev/null 2>&1; then
          ps -o pid,ppid,user,stat,%cpu,%mem,comm,args 2>/dev/null || ps -o pid,ppid,user,stat,comm,args
        else
          printf 'PID\\tRSS\\tCOMM\\tARGS\\n'
          self=$$
          for p in /proc/[0-9]*; do
            pid=${p#/proc/}
            [ "$pid" = "$self" ] && continue
            comm=$(cat "$p/comm" 2>/dev/null)
            rss=$(grep VmRSS "$p/status" 2>/dev/null | tr -dc "0-9")
            args=$(tr "\\0" " " < "$p/cmdline" 2>/dev/null)
            printf '%s\\t%s\\t%s\\t%s\\n' "$pid" "${rss:-0}" "${comm:-?}" "$args"
          done
        fi
        """
        let output = try CommandRunner.run(["exec", containerID, "sh", "-c", script], timeout: 10).stdout
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

    func builderStart() throws {
        _ = try CommandRunner.run(["builder", "start"], timeout: 180)
    }

    func builderStop() throws {
        _ = try CommandRunner.run(["builder", "stop"], timeout: 60)
    }

    func build(tag: String, directory: String) throws {
        _ = try CommandRunner.run(["build", "-t", tag, directory], timeout: 1800)
    }
}

enum ProcessListParser {
    static func parse(_ text: String) -> [ServiceProcess] {
        let lines = text
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard let header = lines.first else { return [] }

        // /proc fallback mode: tab-delimited PID/RSS/COMM/ARGS, memory in KB.
        if header.hasPrefix("PID\t") {
            return lines.dropFirst().compactMap { line -> ServiceProcess? in
                let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 3 else { return nil }
                let rssKB = Int64(parts[1]) ?? 0
                return ServiceProcess(
                    pid: parts[0],
                    parentPID: "—",
                    user: "—",
                    state: "",
                    cpu: nil,
                    memory: rssKB > 0 ? ByteFormat.string(rssKB * 1024) : nil,
                    command: parts[2],
                    arguments: parts.count > 3 ? parts[3].trimmingCharacters(in: .whitespaces) : ""
                )
            }
            .sorted { (Int($0.pid) ?? 0) < (Int($1.pid) ?? 0) }
        }

        let hasCPU = header.localizedCaseInsensitiveContains("%CPU")

        return lines.dropFirst().compactMap { line in
            let parts = line.split(separator: " ", maxSplits: hasCPU ? 7 : 5, omittingEmptySubsequences: true).map(String.init)
            if hasCPU, parts.count >= 8 {
                return ServiceProcess(
                    pid: parts[0],
                    parentPID: parts[1],
                    user: parts[2],
                    state: parts[3],
                    cpu: parts[4] + "%",
                    memory: parts[5] + "%",
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
