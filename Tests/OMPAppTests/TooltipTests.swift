import SwiftUI
import Testing
@testable import OMPApp

@Suite("The tooltips")
struct TooltipTests {
    @Test("a choice's tooltip carries its detail")
    func theTipCarriesTheDetail() {
        #expect(Select.Item(id: "a", title: "Arctic").tip == "Arctic")
        #expect(Select.Item(id: "b", title: "Arctic", detail: "light").tip == "Arctic — light")
        #expect(Select.Item(id: "c", title: "Arctic", detail: "").tip == "Arctic")
    }
}
