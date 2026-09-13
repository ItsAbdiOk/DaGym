import AppIntents
import SwiftUI
import WidgetKit

/// Control Center control (iOS 18+ `ControlWidget`): starts a default-length rest without first
/// opening a workout screen. Runs `StartRestTimerIntent`, which opens the app; `RootView` does
/// the actual rest-starting once it appears (see `PendingIntentAction`).
struct RestTimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "dev.abdirahmanmohamed.dagym.resttimer"
        ) {
            ControlWidgetButton(action: StartRestTimerIntent()) {
                Label("Rest Timer", systemImage: "timer")
            }
        }
        .displayName("Rest Timer")
        .description("Start a default-length rest timer.")
    }
}
