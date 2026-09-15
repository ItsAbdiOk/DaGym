import SwiftUI
import WidgetKit

@main
struct DaGymWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RestLiveActivity()
        TodayWorkoutWidget()
        StreakWidget()
        ConsistencyWidget()
        RestTimerControl()
    }
}
