import Foundation

struct ContainerRecord: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let configuration: ContainerConfiguration?
    let status: ContainerStatus?

    var imageName: String { configuration?.image?.reference ?? "unknown image" }
    var state: String { status?.state ?? "created" }
    var isRunning: Bool { state.lowercased() == "running" }

    var command: String {
        guard let initProcess = configuration?.initProcess else { return "—" }
        return ([initProcess.executable] + initProcess.arguments).joined(separator: " ")
    }

    var publishedPorts: [PublishedPort] {
        configuration?.publishedPorts ?? []
    }
}

struct ContainerConfiguration: Decodable, Hashable, Sendable {
    let creationDate: String?
    let id: String?
    let image: ContainerImageReference?
    let initProcess: InitProcess?
    let networks: [ConfiguredNetwork]?
    let platform: PlatformInfo?
    let publishedPorts: [PublishedPort]?
    let resources: ResourceLimits?
}

struct ContainerImageReference: Decodable, Hashable, Sendable {
    let reference: String?
}

struct InitProcess: Decodable, Hashable, Sendable {
    let arguments: [String]
    let executable: String
    let environment: [String]?
    let workingDirectory: String?
}

struct ConfiguredNetwork: Decodable, Hashable, Sendable {
    let network: String?
}

struct PlatformInfo: Decodable, Hashable, Sendable {
    let architecture: String?
    let os: String?
}

struct PublishedPort: Decodable, Hashable, Sendable {
    let containerPort: Int?
    let hostPort: Int?
    let proto: String?
    let hostAddress: String?

    var summary: String {
        "\(hostPort.map(String.init) ?? "?"):\(containerPort.map(String.init) ?? "?")/\(proto ?? "tcp")"
    }

    var localURL: URL? {
        guard let hostPort else { return nil }
        return URL(string: "http://localhost:\(hostPort)")
    }
}

struct ResourceLimits: Decodable, Hashable, Sendable {
    let cpus: Double?
    let memoryInBytes: Int64?
}

struct ContainerStatus: Decodable, Hashable, Sendable {
    let networks: [RuntimeNetwork]?
    let startedDate: String?
    let state: String?
}

struct RuntimeNetwork: Decodable, Hashable, Sendable {
    let hostname: String?
    let ipv4Address: String?
    let ipv6Address: String?
    let network: String?
}

struct ContainerStats: Decodable, Identifiable, Hashable, Sendable {
    let blockReadBytes: Int64?
    let blockWriteBytes: Int64?
    let cpuUsageUsec: Int64?
    let id: String
    let memoryLimitBytes: Int64?
    let memoryUsageBytes: Int64?
    let networkRxBytes: Int64?
    let networkTxBytes: Int64?
    let numProcesses: Int?

    var memoryFraction: Double {
        guard let used = memoryUsageBytes, let limit = memoryLimitBytes, limit > 0 else { return 0 }
        return min(Double(used) / Double(limit), 1)
    }
}

struct UsageSample: Hashable, Sendable {
    let time: Date
    let cpuPercent: Double
    let memoryBytes: Int64
}

struct ServiceProcess: Identifiable, Hashable, Sendable {
    var id: String { pid }
    let pid: String
    let parentPID: String
    let user: String
    let state: String
    let cpu: String?
    let memory: String?
    let command: String
    let arguments: String
    var listeningPorts: [Int] = []

    var displayName: String {
        if !command.isEmpty, command != "?" { return command }
        return arguments.split(separator: " ").first
            .map { URL(fileURLWithPath: String($0)).lastPathComponent } ?? "?"
    }
}

struct ImageRecord: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let configuration: ImageConfiguration?

    var name: String { configuration?.name ?? id }
}

struct ImageConfiguration: Decodable, Hashable, Sendable {
    let creationDate: String?
    let name: String?
}

enum ByteFormat {
    static func string(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return String(format: value >= 10 ? "%.0f %@" : "%.1f %@", value, units[index])
    }
}
