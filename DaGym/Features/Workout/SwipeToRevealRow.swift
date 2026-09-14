import SwiftUI

/// Lightweight trailing swipe reveal for a row that can't sit in a `List`
/// (the exercise card is a plain `VStack`): drag left past a threshold to
/// reveal fixed-width actions, snapping open or closed with `DGMotion.standard`.
/// Used by `SetRow` for its delete / change-type actions.
struct SwipeToRevealRow<Content: View, Actions: View>: View {
    var actionsWidth: CGFloat
    @Binding var isOpen: Bool
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ZStack(alignment: .trailing) {
            // Hidden until open: a done row's tinted fill is translucent, so the buttons would
            // otherwise show through it.
            actions()
                .frame(width: actionsWidth, alignment: .trailing)
                .clipShape(RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous))
                .opacity(isOpen ? 1 : 0)
                .allowsHitTesting(isOpen)
            content()
                .offset(x: isOpen ? -actionsWidth : 0)
                .gesture(dragGesture)
        }
        .dgAnimation(DGMotion.standard, value: isOpen)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                if value.translation.width < -40 {
                    isOpen = true
                } else if value.translation.width > 40 {
                    isOpen = false
                }
            }
    }
}
