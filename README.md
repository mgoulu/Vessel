# Vessel

A tiny, native macOS GUI for [Apple's `container` CLI](https://github.com/apple/container) — like a featherweight Docker Desktop for Apple Silicon, built with SwiftUI and macOS 26 Liquid Glass.

- **~1 MB app, ~80 MB RAM, 0% idle CPU.** One Swift binary, no Electron, no daemon of its own.
- **Live dashboard.** Container list with per-container CPU % and memory, refreshed every 1.5 s straight from the CLI — state changes made in your terminal show up in the app and vice versa.
- **Drill-down view.** Click a container: processes running inside it, plus 30-minute line charts of CPU and memory — handy for spotting leaks and CPU spikes.
- **Container lifecycle.** Run new containers, start/stop/kill, and remove (with confirmation) from the UI.
- **Native look.** System Liquid Glass toolbar and materials, dynamic window sizing, dark/light aware.

## Requirements

- macOS 26 (Tahoe) on Apple Silicon
- [Apple `container` CLI](https://github.com/apple/container/releases) installed at `/usr/local/bin/container`

Vessel shells out to the `container` CLI; it does not bundle it. The CLI ships as a signed `.pkg` that installs system services Vessel can't embed. If the CLI is missing, Vessel shows a setup screen with a download link and picks it up automatically once installed. Vessel starts the container system service itself on launch.

## Install

Build and package from source:

```sh
bash scripts/package_app.sh
cp -R dist/Vessel.app /Applications/
```

The script produces `dist/Vessel.app` and a `dist/Vessel-<version>.dmg`. Builds are ad-hoc signed; for public distribution sign with a Developer ID certificate and notarize.

## Development

```sh
swift build          # debug build
swift run            # run without packaging
```

Project layout:

```text
Sources/Vessel
├── VesselApp.swift              # window scene, glass background
├── Models/ContainerModels.swift # CLI JSON decoding + usage samples
├── Services/CommandRunner.swift # process runner (timeouts, pipe draining)
├── Services/ContainerCLI.swift  # typed wrappers over container subcommands
├── ViewModels/AppViewModel.swift# polling loop, CPU% deltas, 30-min history
└── Views/                       # ContentView, detail, run sheet, components
```

No dependencies beyond the system SDK.

## Notes

- CPU % is normalized by the container's CPU allocation, so 100% means the whole allocation is busy.
- Per-process CPU/MEM in the detail view depends on the `ps` inside the image; BusyBox (Alpine) only reports PID/user/command.

## Credits

App icon is the Containerization logo from [apple/container](https://github.com/apple/container) (Apache 2.0). Vessel is not affiliated with Apple.

## License

MIT — see [LICENSE](LICENSE).
