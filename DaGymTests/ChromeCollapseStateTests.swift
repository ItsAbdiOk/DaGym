import Foundation
import Testing

@testable import DaGym

@Suite("ChromeCollapseState")
struct ChromeCollapseStateTests {
    @Test("stays expanded below the collapse threshold")
    func staysExpandedBelowThreshold() {
        var state = ChromeCollapseState()
        #expect(state.update(offset: 0) == false)
        #expect(state.update(offset: 79) == false)
        #expect(state.isCollapsed == false)
    }

    @Test("collapses once content scrolls past 80pt")
    func collapsesPastThreshold() {
        var state = ChromeCollapseState()
        _ = state.update(offset: 40)
        let changed = state.update(offset: 90)
        #expect(changed)
        #expect(state.isCollapsed)
    }

    @Test("stays collapsed for a scroll-up smaller than the expand hysteresis")
    func staysCollapsedWithinHysteresis() {
        var state = ChromeCollapseState()
        _ = state.update(offset: 90)
        let changed = state.update(offset: 70) // 20pt up — under the 24pt hysteresis
        #expect(changed == false)
        #expect(state.isCollapsed)
    }

    @Test("expands once scrolled up past the hysteresis from the deepest offset")
    func expandsPastHysteresis() {
        var state = ChromeCollapseState()
        _ = state.update(offset: 90)
        let changed = state.update(offset: 65) // 25pt up — past the 24pt hysteresis
        #expect(changed)
        #expect(state.isCollapsed == false)
    }

    @Test("tracks the deepest offset seen while collapsed, not just the last reading")
    func tracksDeepestOffsetWhileCollapsed() {
        var state = ChromeCollapseState()
        _ = state.update(offset: 90)
        _ = state.update(offset: 130) // deepens further
        let changed = state.update(offset: 108) // 22pt up from 130 — still under hysteresis
        #expect(changed == false)
        #expect(state.isCollapsed)
    }

    @Test("update returns false when the state does not change")
    func returnsFalseWhenUnchanged() {
        var state = ChromeCollapseState()
        #expect(state.update(offset: 10) == false)
        #expect(state.update(offset: 20) == false)
    }
}
