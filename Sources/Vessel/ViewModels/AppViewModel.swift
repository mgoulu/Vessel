import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var containers: [ContainerRecord] = []
    @Published var images: [ImageRecord] = []
    @Published var statsByID: [String: ContainerStats] = [:]
    @Published var selectedContainerID: String?
    @Published var systemStatus = ""
    @Published var logs = ""
    @Published var inspectText = ""
    @Published var processes: [ServiceProcess] = []
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var cpuPercentByID: [String: Double] = [:]
    @Published var historyByID: [String: [UsageSample]] = [:]
    @Published var cliInstalled = CommandRunner.isCLIInstalled

    private let cli = ContainerCLI()
    private var previousCPU: [String: (usec: Int64, at: Date)] = [:]
    private static let historyWindow: TimeInterval = 30 * 60

    var selectedContainer: ContainerRecord? {
        containers.first { $0.id == selectedContainerID }
    }

    var selectedStats: ContainerStats? {
        guard let selectedContainerID else { return nil }
        return statsByID[selectedContainerID]
    }

    func refreshAllAsync() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let status = run { try self.cli.systemStatus() }
            async let records = run { try self.cli.listContainers() }
            async let stats = run { try self.cli.stats() }
            async let imageRecords = run { try self.cli.images() }

            systemStatus = (try? await status) ?? "container system is not available"
            containers = try await records
            images = (try? await imageRecords) ?? []
            updateStats((try? await stats) ?? [])

            await refreshSelected()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshLiveData() async {
        if !cliInstalled {
            cliInstalled = CommandRunner.isCLIInstalled
            guard cliInstalled else { return }
            await ensureSystemRunning()
        }
        do {
            async let recordsTask = run { try self.cli.listContainers() }
            async let statsTask = run { try self.cli.stats() }
            containers = try await recordsTask
            updateStats((try? await statsTask) ?? [])
            if selectedContainerID != nil {
                await refreshSelected()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func updateStats(_ stats: [ContainerStats]) {
        statsByID = Dictionary(stats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let now = Date()
        var percents = cpuPercentByID.filter { statsByID[$0.key] != nil }
        for stat in stats {
            guard let usec = stat.cpuUsageUsec else { continue }
            if let previous = previousCPU[stat.id] {
                let elapsed = now.timeIntervalSince(previous.at)
                if elapsed > 0.2, usec >= previous.usec {
                    // Normalize by the container's CPU allocation so it reads 0-100%.
                    let cpus = containers.first { $0.id == stat.id }?.configuration?.resources?.cpus ?? 1
                    let rawPercent = Double(usec - previous.usec) / (elapsed * 1_000_000) * 100
                    percents[stat.id] = min(rawPercent / max(cpus, 1), 100)
                }
            }
            previousCPU[stat.id] = (usec, now)
        }
        previousCPU = previousCPU.filter { statsByID[$0.key] != nil }
        cpuPercentByID = percents

        let knownIDs = Set(containers.map(\.id))
        let cutoff = now.addingTimeInterval(-Self.historyWindow)
        var history = historyByID.filter { knownIDs.isEmpty || knownIDs.contains($0.key) }
        for stat in stats {
            var samples = history[stat.id, default: []]
            samples.append(UsageSample(
                time: now,
                cpuPercent: percents[stat.id] ?? 0,
                memoryBytes: stat.memoryUsageBytes ?? 0
            ))
            samples.removeAll { $0.time < cutoff }
            history[stat.id] = samples
        }
        historyByID = history
    }

    func select(_ container: ContainerRecord) {
        selectedContainerID = container.id
        Task { await refreshSelected() }
    }

    func refreshSelected() async {
        guard let container = selectedContainer else {
            logs = ""
            inspectText = ""
            processes = []
            return
        }

        do {
            async let detail = run { try self.cli.inspect(containerID: container.id) }
            async let recentLogs = run { try self.cli.logs(containerID: container.id) }
            inspectText = (try? await detail) ?? ""
            logs = (try? await recentLogs) ?? "No logs yet."

            if container.isRunning {
                processes = (try? await run { try self.cli.processes(containerID: container.id) }) ?? []
            } else {
                processes = []
            }
            lastError = nil
        }
    }

    func start(_ containerID: String) { performAction { try self.cli.start(containerID: containerID) } }
    func stop(_ containerID: String) { performAction { try self.cli.stop(containerID: containerID) } }
    func kill(_ containerID: String) { performAction { try self.cli.kill(containerID: containerID) } }
    func remove(_ containerID: String) {
        if selectedContainerID == containerID { selectedContainerID = nil }
        performAction { try self.cli.delete(containerID: containerID) }
    }

    func ensureSystemRunning() async {
        guard cliInstalled else { return }
        _ = try? await run { try self.cli.startSystem() }
    }

    func runContainer(image: String, name: String, command: String) {
        performAction { try self.cli.runDetached(image: image, name: name, command: command) }
    }

    private func performAction(_ action: @escaping @Sendable () throws -> Void) {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                try await run(action)
                await refreshAllAsync()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func run<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try operation() }.value
    }
}
