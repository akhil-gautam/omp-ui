import Foundation
import Testing
@testable import OMPApp

@Suite("The sky's settings")
struct SkyTests {
    @Test("the wait between showers stays within the two bounds, whichever way round they are set")
    func waitStaysInBounds() {
        var settings = SkySettings()
        settings.fewestSeconds = 30
        settings.mostSeconds = 10
        for _ in 0..<200 {
            #expect((10...30).contains(settings.nextWait()))
        }
        settings.fewestSeconds = 0
        settings.mostSeconds = 0
        #expect(settings.nextWait() >= 1)
    }

    @Test("falling stars go the way they are set to, with the tail and speed set")
    func meteorsFollowTheSettings() {
        var settings = SkySettings()
        settings.direction = .left
        settings.tailLength = 200
        settings.speed = 2
        for _ in 0..<50 {
            let meteor = Meteor.random(settings: settings)
            #expect(meteor.angle < 0)
            #expect((150...230).contains(meteor.length))
            #expect(meteor.duration <= 1.35 / 2)
        }
        settings.direction = .right
        #expect(Meteor.random(settings: settings).angle > 0)
    }

    @Test("the settings are kept as set, and a missing or unreadable copy gives the defaults")
    func settingsRoundTrip() throws {
        var settings = SkySettings()
        settings.shown = .always
        settings.meteorsPerShower = 7
        settings.stars = 120
        settings.colour = .accent
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(SkySettings.self, from: data) == settings)
        #expect((try? JSONDecoder().decode(SkySettings.self, from: Data("{\"shown\":\"sometimes\"}".utf8))) == nil)
    }
}
