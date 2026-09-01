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
    private static let detailSize = CGSize(width: 920, height: 700)

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
            Text("\"\(container.id)\" (\(container.imageName)) will be stopped if running and deleted. This cannot be undone.")
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
    @State private var imageToRemove: ImageRecord?
    @State private var showingPruneConfirmation = false

    private var container: ContainerRecord? {
        viewModel.containers.first { $0.id == containerID }
    }

    private var samples: [UsageSample] {
        viewModel.historyByID[containerID] ?? []
    }

    private var projectName: String {
        container.map { ImageRecord.projectName(from: $0.imageName) } ?? ""
    }

    private var projectImages: [ImageRecord] {
        viewModel.images.filter { $0.projectName == projectName }
    }

    private var sortedImages: [ImageRecord] {
        projectImages.sorted {
            ($0.configuration?.creationDate ?? "") > ($1.configuration?.creationDate ?? "")
        }
    }

    private var totalImageBytes: Int64 {
        Dictionary(projectImages.map { ($0.digest, $0.sizeBytes) }, uniquingKeysWith: { max($0, $1) })
            .values.reduce(0, +)
    }

    var body: some View {
        if let container {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    infoColumn(container)
                        .frame(width: 210)
                    processColumn
                        .frame(width: 270)
                    chartsColumn
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 360)

                imagesCard
            }
            .padding(16)
            .alert(
                "Remove stored image?",
                isPresented: Binding(
                    get: { imageToRemove != nil },
                    set: { if !$0 { imageToRemove = nil } }
                ),
                presenting: imageToRemove
            ) { image in
                Button("Remove", role: .destructive) { viewModel.removeImage(image.name) }
                Button("Cancel", role: .cancel) {}
            } message: { image in
                Text("\"\(image.name)\" will be removed from local storage. This cannot be undone.")
            }
            .confirmationDialog(
                "Remove all unused images?",
                isPresented: $showingPruneConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove unused images", role: .destructive) {
                    viewModel.pruneUnusedImages()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes cached and stored images not used by any container, across all projects. Images referenced by a container are kept.")
            }
        } else {
            ContentUnavailableView("Container removed", systemImage: "shippingbox")
        }
    }

    private var imagesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("\(projectName) images", systemImage: "internaldrive")
                    .font(.headline)
                Text("\(projectImages.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Spacer()
                Text(ByteFormat.string(totalImageBytes))
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if projectImages.isEmpty {
                ContentUnavailableView("No stored images for \(projectName)", systemImage: "shippingbox")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedImages) { image in
                            imageRow(image)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Free unused image storage")
                        .font(.caption.weight(.semibold))
                    Text("Keeps every image referenced by a container.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Remove unused", systemImage: "trash", role: .destructive) {
                    showingPruneConfirmation = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(viewModel.isLoading || viewModel.images.isEmpty)
                .help("Remove unused images across all projects")
            }
        }
        .card()
    }

    private func imageRow(_ image: ImageRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: image.name == container?.imageName ? "shippingbox.fill" : "shippingbox")
                .foregroundStyle(image.name == container?.imageName ? .blue : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(image.name)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .lineLimit(1)
                    .help(image.name)
                Text("sha256:\(image.shortDigest)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            if let creationDate = image.configuration?.creationDate,
               let date = try? Date.ISO8601FormatStyle().parse(creationDate) {
                Text(date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 88, alignment: .trailing)
            }

            Text(ByteFormat.string(image.sizeBytes))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .trailing)

            Button("Remove image", systemImage: "trash", role: .destructive) {
                imageToRemove = image
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Remove \(image.name) from local storage")
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.separator).frame(height: 1)
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

            let internalPorts = unpublishedListeningPorts(container)
            if !container.publishedPorts.isEmpty || !internalPorts.isEmpty {
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
                    // Listeners without a published mapping are still reachable
                    // via the container's own IP — link them there.
                    ForEach(internalPorts, id: \.self) { port in
                        if let ip = container.ipv4Address,
                           let url = URL(string: "http://\(ip):\(port)") {
                            Link(":\(String(port)) via \(ip) ↗", destination: url)
                                .font(.system(.caption, design: .monospaced).weight(.medium))
                        } else {
                            Text(":\(String(port)) internal")
                                .font(.system(.caption, design: .monospaced).weight(.medium))
                                .foregroundStyle(.secondary)
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

    private func unpublishedListeningPorts(_ container: ContainerRecord) -> [Int] {
        let published = Set(container.publishedPorts.compactMap(\.containerPort))
        let listening = Set(viewModel.processes.flatMap(\.listeningPorts))
        return listening.subtracting(published).sorted()
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
                        ForEach(processTree, id: \.process.pid) { entry in
                            HStack(spacing: 6) {
                                Text(entry.process.displayName)
                                    .fontWeight(entry.depth == 0 ? .semibold : .regular)
                                    .lineLimit(1)
                                    .padding(.leading, CGFloat(entry.depth) * 14)
                                    .help(entry.process.arguments)
                                ForEach(entry.process.listeningPorts, id: \.self) { port in
                                    Text(":\(String(port))")
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 4)
                                        .background(.blue.opacity(0.12), in: Capsule())
                                }
                                Spacer(minLength: 4)
                                Text(entry.process.cpu ?? "—")
                                    .frame(width: 44, alignment: .trailing)
                                Text(entry.process.memory ?? "—")
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

    // Parent→child ordering with indentation so the column reads like a
    // service tree: the init process on top, what it spawned nested below.
    private var processTree: [(process: ServiceProcess, depth: Int)] {
        let processes = viewModel.processes
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var children: [String: [ServiceProcess]] = [:]
        var roots: [ServiceProcess] = []
        for process in processes {
            if process.parentPID != process.pid, byPID[process.parentPID] != nil {
                children[process.parentPID, default: []].append(process)
            } else {
                roots.append(process)
            }
        }

        var ordered: [(process: ServiceProcess, depth: Int)] = []
        var visited = Set<String>()
        func walk(_ process: ServiceProcess, _ depth: Int) {
            guard visited.insert(process.pid).inserted else { return }
            ordered.append((process, depth))
            for child in children[process.pid] ?? [] {
                walk(child, min(depth + 1, 3))
            }
        }
        for root in roots { walk(root, 0) }
        return ordered
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
