import GymCore
import SwiftUI

/// Placeholder until the owner's design mockups arrive. Proves the app builds
/// and that GymCore is linked.
struct ContentView: View {
    private let oneRepMax = OneRepMax.estimate(weight: 100, reps: 5)

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 48))
            Text("DaGym")
                .font(.largeTitle.bold())
            if let oneRepMax {
                Text("100 kg × 5 ≈ \(oneRepMax, format: .number.precision(.fractionLength(1))) kg e1RM")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
