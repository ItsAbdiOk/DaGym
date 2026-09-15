import SwiftUI

extension EnvironmentValues {
    /// Whether the tab this view sits in is the selected one *and* nothing full-screen (the
    /// active workout, its summary) is covering it. `RootView` sets it per `Tab`; the default
    /// `true` keeps previews, sheets and tests behaving as if nothing were hidden.
    @Entry var isTabVisible = true
}

extension View {
    /// Runs `refresh` when the store saves while this tab is visible. A save that lands while
    /// the tab is hidden — another tab selected, or the active workout covering everything —
    /// is remembered and paid for once, the moment the tab is next shown, however many saves
    /// were missed. This is what keeps a set logged in the workout from re-running every other
    /// tab's whole refresh (Home's ten fetches, the Library's 1 500-row catalogue) underneath
    /// the full-screen cover on every tap.
    func refreshOnStoreChange(_ refresh: @escaping () -> Void) -> some View {
        modifier(StoreChangeRefresh(refresh: refresh))
    }
}

private struct StoreChangeRefresh: ViewModifier {
    var refresh: () -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(\.isTabVisible) private var isTabVisible
    /// A save arrived while hidden; refresh on the next show.
    @State private var isStale = false

    func body(content: Content) -> some View {
        content
            .onChange(of: store.changeToken) { _, _ in
                if isTabVisible {
                    refresh()
                } else {
                    isStale = true
                }
            }
            .onChange(of: isTabVisible) { _, visible in
                guard visible, isStale else { return }
                isStale = false
                refresh()
            }
    }
}
