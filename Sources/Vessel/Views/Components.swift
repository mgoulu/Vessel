import SwiftUI

extension View {
    // Content-layer card: standard material, no glass. Liquid Glass stays in
    // the chrome (toolbar/sidebar) per HIG — glass never sits on content.
    func card(cornerRadius: CGFloat = 12) -> some View {
        self
            .padding(14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct StatusDot: View {
    let state: String

    var body: some View {
        Circle()
            .fill(state.lowercased() == "running" ? Color.green : Color.red)
            .frame(width: 9, height: 9)
            .help(state.capitalized)
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
