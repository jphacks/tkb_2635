import Foundation
import Testing
@testable import StarCore

@Suite struct SoundEffectTests {
    private let now = Date(timeIntervalSince1970: 1_792_843_200)

    @Test func everySoundHasDistinctFileAndQuietVolume() {
        let names = SoundEffect.allCases.map(\.fileName)
        #expect(Set(names).count == names.count)
        #expect(SoundEffect.allCases.allSatisfy { $0.volume > 0 && $0.volume <= 0.5 })
    }

    @Test func playbackIsQuieterThanSpecVolume() {
        #expect(SoundEffect.allCases.allSatisfy { $0.playbackVolume == $0.volume * SoundEffect.masterVolume })
        #expect(SoundEffect.masterVolume > 0 && SoundEffect.masterVolume < 1)
    }

    @Test func backgroundMusicStaysQuietAndFadesIn() {
        #expect(BackgroundMusic.volume > 0 && BackgroundMusic.volume <= 0.3)
        #expect(BackgroundMusic.fadeInDuration > 0)
        #expect(BackgroundMusic.startDelay >= 0)
    }

    @Test func throttleBlocksRepeatsWithinInterval() {
        var throttle = SoundThrottle()
        let interval = SoundEffect.timeTick.minimumInterval
        let first = throttle.allows(.timeTick, at: now)
        let tooSoon = throttle.allows(.timeTick, at: now.addingTimeInterval(interval / 2))
        let afterInterval = throttle.allows(.timeTick, at: now.addingTimeInterval(interval))
        #expect(first)
        #expect(!tooSoon)
        #expect(afterInterval)
    }

    @Test func throttleKeepsEachSoundSeparate() {
        var throttle = SoundThrottle()
        let gesture = throttle.allows(.mapGesture, at: now)
        let tick = throttle.allows(.timeTick, at: now)
        let gestureAgain = throttle.allows(.mapGesture, at: now.addingTimeInterval(0.1))
        #expect(gesture)
        #expect(tick)
        #expect(!gestureAgain)
    }

    @Test func spotFoundOnlyWhenBecomingRecommended() {
        #expect(SoundEffect.announcesSpotFound(previous: nil, current: .recommended))
        #expect(SoundEffect.announcesSpotFound(previous: .notVisible, current: .recommended))
        #expect(!SoundEffect.announcesSpotFound(previous: .recommended, current: .recommended))
        #expect(!SoundEffect.announcesSpotFound(previous: .notVisible, current: .needsCheck))
        #expect(!SoundEffect.announcesSpotFound(previous: nil, current: .notVisible))
    }
}
