#if DEBUG
import SwiftUI

// @available(*, deprecated, message: "Use scripts/cloudkit-schema.sh instead of the probe button")
/// Debug builds only: tools for the developer, never compiled into a release. Today that is
/// the CloudKit schema probe — see `CloudKitSchemaProbe` for why the Development schema needs
/// forcing before "Deploy Schema Changes" can promote every type and field to Production.
///
/// DEPRECATED: the probe is superseded by `scripts/cloudkit-schema.sh` (dry run, then
/// `--deploy`), which needs no tap in the app. This section stays as a manual fallback only.
struct DeveloperSettingsSection: View {
    @Environment(WorkoutStore.self) private var store
    @State private var probePresent = false

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Developer").dgLabel()
            VStack(spacing: 0) {
                if probePresent {
                    row(title: "Remove CloudKit schema probe", symbol: "trash", tint: DGColor.danger) {
                        CloudKitSchemaProbe.remove(from: store.context)
                        store.save()
                        probePresent = false
                    }
                } else {
                    row(
                        title: "Insert CloudKit schema probe", symbol: "icloud.and.arrow.up",
                        tint: DGColor.coral
                    ) {
                        CloudKitSchemaProbe.insert(into: store.context)
                        store.save()
                        probePresent = true
                    }
                }
            }
            .dgCard(padding: 0)
            Text(probePresent
                ? "Probe rows are in the store. Give iCloud about a minute to export, then remove them."
                : "Inserts one row of every synced type so the CloudKit Development schema gets every field.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
        .onAppear { probePresent = CloudKitSchemaProbe.isPresent(in: store.context) }
    }

    private func row(title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).font(DGFont.body).foregroundStyle(DGColor.ink1)
                Spacer()
            }
            .padding(.horizontal, DGSpace.s5)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
