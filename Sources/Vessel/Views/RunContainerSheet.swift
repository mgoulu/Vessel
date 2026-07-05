import SwiftUI

struct RunContainerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AppViewModel

    @State private var image = "docker.io/library/alpine:latest"
    @State private var name = ""
    @State private var command = "sleep 3600"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Run Container")
                    .font(.title2.weight(.semibold))
                Text("Starts a detached Apple container using the local `container` CLI.")
                    .foregroundStyle(.secondary)
            }

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
        .padding(24)
        .frame(width: 460)
    }
}
