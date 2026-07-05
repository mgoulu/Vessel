import SwiftUI
import Charts

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var showingRunSheet = false
    @State private var containerToRemove: ContainerRecord?
    @State private var openContainerID: String?

    private static let listWidth: CGFloat = 540
    private static let rowHeight: CGFloat = 58
    private static let chromeHeight: CGFloat = 46
    private static let minHeight: CGFloat = 220
    private static let maxHeight: CGFloat = 640
    private static let detailSize = CGSize(width: 920, height: 560)

    private var windowWidth: CGFloat {
        openContainerID == nil ? Self.listWidth : Self.detailSize.width
    }

    private var windowHeight: CGFloat {
        guard openContainerID == nil else { return Self.detailSize.height }
        guard !viewModel.containers.isEmpty else { return Self.minHeight }
        let content = Self.chromeHeight + CGFloat(viewModel.containers.count) * Self.rowHeight
        return min(content, Self.maxHeight)
    }

    var body: some View {
        Group {
            if !viewModel.cliInstalled {
                setupView
                    .navigationTitle("Vessel")
            } else if let openContainerID {
                ContainerDetailView(viewModel: viewModel, containerID: openContainerID)
                    .navigationTitle(openContainerID)
            } else {
                containerList
                    .navigationTitle("Containers")
            }
        }
        .frame(width: windowWidth, height: windowHeight)
        .animation(.snappy(duration: 0.25), value: windowHeight)
        .toolbar { toolbarContent }
        .onChange(of: viewModel.containers) { _, newContainers in
            if let openContainerID, !newContainers.contains(where: { $0.id == openContainerID }) {
                self.openContainerID = nil
                viewModel.selectedContainerID = nil
            }
        }
        .task {
            await viewModel.ensureSystemRunning()
            await viewModel.refreshAllAsync()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                await viewModel.refreshLiveData()
            }
        }
        .sheet(isPresented: $showingRunSheet) {
            RunContainerSheet(viewModel: viewModel)
        }
        .alert(
            "Remove container?",
            isPresented: Binding(
                get: { containerToRemove != nil },
                set: { if !$0 { containerToRemove = nil } }
            ),
            presenting: containerToRemove
        ) { container in
            Button("Remove", role: .destructive) { viewModel.remove(container.id) }
            Button("Cancel", role: .cancel) {}
        } message: { container in
            Text("\"\(container.id)\" (\(container.imageName)) will be deleted. This cannot be undone.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if openContainerID != nil {
            ToolbarItem(placement: .navigation) {
                Button("Back", systemImage: "chevron.left") {
                    openContainerID = nil
                    viewModel.selectedContainerID = nil
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Run", systemImage: "plus") { showingRunSheet = true }
        }
    }

    private var setupView: some View {
        ContentUnavailableView {
            Label("Apple container CLI not found", systemImage: "shippingbox.and.arrow.backward")
        } description: {
            Text("Vessel drives Apple's `container` CLI. Install the signed installer package from Apple's GitHub releases, then come back — Vessel picks it up automatically.")
        } actions: {
            Link("Download container CLI", destination: URL(string: "https://github.com/apple/container/releases")!)
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var containerList: some View {
        if viewModel.containers.isEmpty {
            ContentUnavailableView {
                Label("No containers", systemImage: "shippingbox")
            } description: {
                Text(viewModel.lastError ?? "Run a new container with the + button.")
            }
        } else {
            List {
                if let lastError = viewModel.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                ForEach(viewModel.containers) { container in
                    ContainerRow(
                        container: container,
                        stats: viewModel.statsByID[container.id],
                        cpuPercent: viewModel.cpuPercentByID[container.id],
                        onStart: { viewModel.start(container.id) },
                        onStop: { viewModel.stop(container.id) },
                        onRemove: { containerToRemove = container },
                        onOpen: {
                            viewModel.select(container)
                            openContainerID = container.id
                        }
                    )
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct ContainerRow: View {
    let container: ContainerRecord
    let stats: ContainerStats?
    let cpuPercent: Double?
    let onStart: () -> Void
    let onStop: () -> Void
    let onRemove: () -> Void
    let onOpen: () -> Void

    private var cpuText: String {
        guard container.isRunning, let cpuPercent else { return "—" }
        return String(format: "%.1f%%", cpuPercent)
    }

    private var memoryText: String {
        guard container.isRunning else { return "—" }
        return ByteFormat.string(stats?.memoryUsageBytes)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(container.id)
                        .font(.headline)
                        .lineLimit(1)
                    StatusDot(state: container.state)
                }
                HStack(spacing: 6) {
                    Text(container.imageName)
                        .lineLimit(1)
                    ForEach(container.publishedPorts, id: \.self) { port in
                        Text(port.summary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary.opacity(0.6), in: Capsule())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Grid(alignment: .trailing, verticalSpacing: 2) {
                GridRow {
                    Text("CPU").font(.caption2).foregroundStyle(.tertiary)
                    Text(cpuText)
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .gridColumnAlignment(.trailing)
                }
                GridRow {
                    Text("MEM").font(.caption2).foregroundStyle(.tertiary)
                    Text(memoryText)
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                }
            }

            HStack(spacing: 10) {
                if container.isRunning {
                    Button("Stop", systemImage: "stop.fill", action: onStop)
                } else {
                    Button("Start", systemImage: "play.fill", action: onStart)
                }
                Button("Remove", systemImage: "trash", action: onRemove)
            }
            .buttonStyle(.glass)
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .padding(.leading, 6)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}

struct ContainerDetailView: View {
    @ObservedObject var viewModel: AppViewModel
    let containerID: String

    private var container: ContainerRecord? {
        viewModel.containers.first { $0.id == containerID }
    }

    private var samples: [UsageSample] {
        viewModel.historyByID[containerID] ?? []
    }

    var body: some View {
        if let container {
            HStack(alignment: .top, spacing: 14) {
                infoColumn(container)
                    .frame(width: 210)
                processColumn
                    .frame(width: 270)
                chartsColumn
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        } else {
            ContentUnavailableView("Container removed", systemImage: "shippingbox")
        }
    }

    private func infoColumn(_ container: ContainerRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(container.id)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                StatusDot(state: container.state)
            }
            Text(container.imageName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Grid(alignment: .leading, verticalSpacing: 6) {
                GridRow {
                    Text("CPU").font(.caption2).foregroundStyle(.tertiary)
                    Text(viewModel.cpuPercentByID[container.id].map { String(format: "%.1f%%", $0) } ?? "—")
                        .font(.system(.callout, design: .monospaced).weight(.medium))
                }
                GridRow {
                    Text("MEM").font(.caption2).foregroundStyle(.tertiary)
                    Text(ByteFormat.string(viewModel.selectedStats?.memoryUsageBytes))
                        .font(.system(.callout, design: .monospaced).weight(.medium))
                }
            }

            if let stats = viewModel.selectedStats {
                ProgressView(value: stats.memoryFraction)
                    .tint(.green)
            }

            if !container.publishedPorts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PORTS").font(.caption2).foregroundStyle(.tertiary)
                    ForEach(container.publishedPorts, id: \.self) { port in
                        if let url = port.localURL {
                            Link("\(port.summary) ↗", destination: url)
                                .font(.system(.caption, design: .monospaced).weight(.medium))
                        } else {
                            Text(port.summary)
                                .font(.system(.caption, design: .monospaced).weight(.medium))
                        }
                    }
                }
            }

            Spacer()

            VStack(spacing: 8) {
                if container.isRunning {
                    Button("Stop", systemImage: "stop.fill") { viewModel.stop(container.id) }
                    Button("Kill", systemImage: "xmark.octagon") { viewModel.kill(container.id) }
                } else {
                    Button("Start", systemImage: "play.fill") { viewModel.start(container.id) }
                }
            }
            .buttonStyle(.glass)
            .frame(maxWidth: .infinity)
        }
        .padding(14)
    }

    private var processColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Inside")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.processes.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.processes.isEmpty {
                Text("No process data.\nStart the container to inspect inside.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                HStack {
                    Text("PROCESS").frame(maxWidth: .infinity, alignment: .leading)
                    Text("CPU").frame(width: 44, alignment: .trailing)
                    Text("MEM").frame(width: 44, alignment: .trailing)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.processes) { process in
                            HStack {
                                Text(process.command)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(process.cpu ?? "—")
                                    .frame(width: 44, alignment: .trailing)
                                Text(process.memory ?? "—")
                                    .frame(width: 52, alignment: .trailing)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .padding(.vertical, 5)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(.separator).frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
        .card()
    }

    private var chartsColumn: some View {
        VStack(spacing: 14) {
            usageChart(
                title: "CPU % — last 30 min",
                color: .blue,
                yDomain: 0...100,
                value: { $0.cpuPercent }
            )
            usageChart(
                title: "Memory MB — last 30 min",
                color: .green,
                value: { Double($0.memoryBytes) / 1_048_576 }
            )
        }
    }

    @ViewBuilder
    private func usageChart(
        title: String,
        color: Color,
        yDomain: ClosedRange<Double>? = nil,
        value: @escaping (UsageSample) -> Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if samples.count < 2 {
                Text("Collecting data…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let chart = Chart(samples, id: \.time) { sample in
                    LineMark(
                        x: .value("Time", sample.time),
                        y: .value(title, value(sample))
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute(), centered: false)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }

                if let yDomain {
                    chart.chartYScale(domain: yDomain)
                } else {
                    chart
                }
            }
        }
        .frame(maxHeight: .infinity)
        .card()
    }
}
