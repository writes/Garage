import AVFoundation
import Foundation
import Testing
@testable import Garage

/// `contextualStrings` is the only lever that improves accuracy BEFORE the transcript exists, and
/// everything downstream — the extraction model, the prefilled form — inherits whatever the
/// recogniser got wrong. These pin the parts that are ours to get right.
struct SpeechVocabularyTests {
    private func vehicle(make: String, model: String, nickname: String = "") -> Vehicle {
        var vehicle = Vehicle.empty
        vehicle.make = make
        vehicle.model = model
        vehicle.nickname = nickname
        return vehicle
    }

    @Test func theGenericListCoversTheTermsRecognisersManglePersistently() {
        let terms = Set(SpeechVocabulary.automotive.map { $0.lowercased() })
        // "rotors" transcribes as "routers", "Mobil 1" as "mobile one" — the exact words that
        // decide an entry's type and its part fields.
        for expected in ["rotors", "mobil 1", "michelin", "odometer", "brake pads", "tread depth"] {
            #expect(terms.contains(expected))
        }
    }

    /// The user's own car is the proper noun most likely in the sentence and the one no generic
    /// list can hold, so it must lead rather than trail.
    @Test func theUsersVehicleLeadsTheHints() {
        let terms = SpeechVocabulary.terms(for: vehicle(make: "Porsche", model: "911"))
        #expect(terms.first == "Porsche")
        #expect(terms.contains("Porsche 911"))
        #expect(terms.contains("rotors"))
    }

    @Test func aNilVehicleStillYieldsTheGenericList() {
        #expect(SpeechVocabulary.terms(for: nil) == SpeechVocabulary.automotive)
    }

    /// Duplicates dilute the bias — the hint list competes with itself — so a nickname that repeats
    /// the make must not be sent twice.
    @Test func repeatedTermsAreDeduplicatedCaseInsensitively() {
        let terms = SpeechVocabulary.terms(for: vehicle(make: "Michelin", model: "X", nickname: "michelin"))
        let lowered = terms.map { $0.lowercased() }
        #expect(Set(lowered).count == lowered.count)
    }

    @Test func emptyMakeAndModelDoNotProduceBlankHints() {
        let terms = SpeechVocabulary.terms(for: vehicle(make: "  ", model: "  "))
        #expect(!terms.contains(""))
        #expect(!terms.contains("   "))
    }

    @Test func aNicknameIsIncludedWhenItAddsSomething() {
        #expect(SpeechVocabulary.terms(for: vehicle(make: "Dodge", model: "Viper", nickname: "Track car"))
            .contains("Track car"))
    }
}

/// Which audio notifications should abort a recording. Getting this wrong in either direction is
/// user-visible: too eager and a routine notification kills a live dictation, too lax and the app
/// keeps claiming to listen on a microphone iOS has already taken away.
struct AudioInterruptionClassifierTests {
    private func note(_ name: Notification.Name, _ info: [AnyHashable: Any]) -> Notification {
        Notification(name: name, object: nil, userInfo: info)
    }

    @Test func anInterruptionBeginningAborts() {
        let began = note(AVAudioSession.interruptionNotification,
                         [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        #expect(SpeechTranscriptionService.isDisruptive(began))
    }

    /// The END of an interruption must not abort — by then there is nothing left to tear down, and
    /// treating it as a failure would surface an error after the user already stopped.
    @Test func anInterruptionEndingDoesNotAbort() {
        let ended = note(AVAudioSession.interruptionNotification,
                         [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        #expect(!SpeechTranscriptionService.isDisruptive(ended))
    }

    /// Headphones unplugged mid-sentence: the route the engine was capturing from is gone.
    @Test func losingTheCurrentInputDeviceAborts() {
        let reason = AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
        let lost = note(AVAudioSession.routeChangeNotification, [AVAudioSessionRouteChangeReasonKey: reason])
        #expect(SpeechTranscriptionService.isDisruptive(lost))
    }

    /// A device merely BECOMING available — AirPods connecting in the next room — is routine and
    /// must not kill a recording in progress. This is the case a naive "any route change" check
    /// gets wrong.
    @Test func aNewDeviceBecomingAvailableDoesNotAbort() {
        let reason = AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
        let gained = note(AVAudioSession.routeChangeNotification, [AVAudioSessionRouteChangeReasonKey: reason])
        #expect(!SpeechTranscriptionService.isDisruptive(gained))
    }

    @Test func aRouteChangeWithNoReasonDoesNotAbort() {
        #expect(!SpeechTranscriptionService.isDisruptive(note(AVAudioSession.routeChangeNotification, [:])))
    }

    /// An engine reconfiguration invalidates the installed tap, so it always aborts.
    @Test func anEngineConfigurationChangeAborts() {
        #expect(SpeechTranscriptionService.isDisruptive(note(.AVAudioEngineConfigurationChange, [:])))
    }
}
