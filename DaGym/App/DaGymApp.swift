import SwiftUI

@main
struct DaGymApp: App {
    var body: some Scene {
        WindowGroup {
            if let route = DebugRoute.fromLaunchArguments {
                DebugScreenView(route: route)
            } else {
                RootView()
            }
        }
    }
}
