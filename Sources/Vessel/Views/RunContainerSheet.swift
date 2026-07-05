import SwiftUI
import UniformTypeIdentifiers

struct RunContainerSheet: View {
    private enum Mode: Hashable {
        case run, build
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AppViewModel

    @State private var mode: Mode = .run

    @State private var image = "docker.io/library/alpine:latest"
    @State private var name = ""
    @State private var command = "sleep 3600"

    @State private var buildTag = "myapp:local"
    @State private var buildDirectory: URL?
    @State private var showingFolderPicker = false
    @State private var buildError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("", selection: $mode) {
                Text("Run image").tag(Mode.run)
                Text("Build from Dockerfile").tag(Mode.build)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .run: runForm
            case .build: buildForm
            }
        }
        .padding(24)
        .frame(width: 460)
        .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                buildDirectory = url
            }
        }
    }

    private var runForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Starts a detached Apple container using the local `container` CLI.")
                .foregroundStyle(.secondary)

            TextField("Image", text: $image)
                .textFieldStyle(.roundedBorder)
            TextField("Name (optional)", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("Command", text: $command)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Run") {
                    viewModel.runContainer(image: image, name: name, command: command)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var buildForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Builds an image from a folder containing a Dockerfile. The builder VM runs only for the duration of the build.")
                .foregroundStyle(.secondary)

            TextField("Tag (e.g. myapp:local)", text: $buildTag)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text(buildDirectory?.path ?? "No folder selected")
                    .font(.callout)
                    .foregroundStyle(buildDirectory == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose…") { showingFolderPicker = true }
            }

            if let buildError {
                Text(buildError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(4)
            }

            HStack {
                if viewModel.isBuilding {
                    ProgressView().controlSize(.small)
                    Text("Building… this can take a while.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .disabled(viewModel.isBuilding)
                Button("Build") { startBuild() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        viewModel.isBuilding
                        || buildDirectory == nil
                        || buildTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }
        }
    }

    private func startBuild() {
        guard let buildDirectory else { return }
        buildError = nil
        let tag = buildTag.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if await viewModel.buildImage(tag: tag, directory: buildDirectory.path) {
                // Hand the fresh image straight to the run form.
                image = tag
                name = ""
                mode = .run
            } else {
                buildError = viewModel.lastError
            }
        }
    }
}
