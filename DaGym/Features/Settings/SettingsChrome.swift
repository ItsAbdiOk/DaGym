import SwiftUI

/// The chrome every Settings page is built from (the prototype's `sList` template): a wash
/// under a scroll of white row groups, uppercase kickers, hairline rows, a footnote under a
/// group. Shared here rather than re-declared per section file — `private` is file-scoped, so
/// the sections alongside used to carry their own copies of `row`/`caption`/`Divider`.

/// A pushed Settings page: inline title, system back button, wash, scroll. Never wraps a
/// `NavigationStack` — the page is pushed inside the You hub's (or `SettingsView`'s standalone
/// one when it is shown as a sheet).
struct SettingsPage<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s3) { content }
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, 100)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One white row group (radius 16) with an optional uppercase kicker above and a footnote
/// below. Rows go in `content`, separated by `SettingsDivider`.
struct SettingsSection<Content: View>: View {
    var title: String?
    var note: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            if let title {
                Text(title).dgLabel()
                    .padding(.horizontal, DGSpace.s1)
                    .padding(.top, DGSpace.s3)
            }
            VStack(spacing: 0) { content }
                .dgCard(radius: 16, padding: 0)
            if let note {
                SettingsNote(text: note)
            }
        }
    }
}

/// The footnote under a row group.
struct SettingsNote: View {
    var text: String
    var tint: Color = DGColor.ink3

    var body: some View {
        Text(text)
            .font(DGFont.footnote)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DGSpace.s1)
    }
}

/// One "label … trailing control" row inside a group. `sub` is the small dim line under the
/// label (the prototype's `row.sub`).
struct SettingsRow<Trailing: View>: View {
    var label: String
    var sub: String?
    var labelTint: Color = DGColor.ink1
    @ViewBuilder var trailing: Trailing

    var body: some View {
        DGAdaptiveStack(verticalAlignment: .center, spacing: DGSpace.s3) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(DGFont.subhead).foregroundStyle(labelTint)
                if let sub {
                    Text(sub)
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 15)
        .padding(.vertical, DGSpace.s2)
        .frame(minHeight: 46)
    }
}

/// A row whose right side is a dim read-only value.
struct SettingsValueRow: View {
    var label: String
    var value: String
    var sub: String?

    var body: some View {
        SettingsRow(label: label, sub: sub) {
            Text(value)
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
                .monospacedDigit()
        }
    }
}

/// An accent switch row.
struct SettingsToggleRow: View {
    var label: String
    var sub: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(label: label, sub: sub) {
            Toggle(label, isOn: $isOn).tint(DGColor.coral).labelsHidden()
        }
    }
}

/// A tappable row with an optional value and a chevron — opens a sheet, a picker or a link.
struct SettingsLinkRow: View {
    var label: String
    var value: String?
    var sub: String?
    var labelTint: Color = DGColor.ink1
    var isBusy = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRow(label: label, sub: sub, labelTint: labelTint) {
                HStack(spacing: DGSpace.s2) {
                    if let value {
                        Text(value).font(DGFont.subhead).foregroundStyle(DGColor.ink3).lineLimit(1)
                    }
                    if isBusy {
                        ProgressView().tint(DGColor.ink3).accessibilityLabel("In progress")
                    } else {
                        SettingsChevron()
                    }
                }
            }
        }
        .buttonStyle(.dgRow)
        .disabled(isBusy)
        .accessibilityLabel(value.map { "\(label): \($0)" } ?? label)
    }
}

/// The dim chevron on the right of a link row.
struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right").accessibilityHidden(true)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DGColor.ink4)
    }
}

/// The 30pt accent-wash square with an accent glyph that leads each index row.
struct SettingsIconSquare: View {
    var symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(DGColor.coral)
            .frame(width: 30, height: 30)
            .background(DGColor.coralWash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Hairline separator between rows, indented to align with row text.
struct SettingsDivider: View {
    var body: some View {
        Divider().overlay(DGColor.hairline).padding(.leading, 15)
    }
}

/// A segmented "pill" picker for the two- and three-way settings (kg | lb, RPE | RIR, …).
/// The system segmented control already matches the prototype's white-on-grey pill.
struct SettingsSegment<Value: Hashable>: View {
    var label: String
    @Binding var selection: Value
    var options: [(Value, String)]

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(options, id: \.0) { option in
                Text(option.1).tag(option.0)
            }
        }
        .pickerStyle(.segmented)
        .tint(DGColor.coral)
        .fixedSize()
    }
}
