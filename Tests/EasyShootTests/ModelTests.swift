import Carbon.HIToolbox
import XCTest
@testable import EasyShoot

final class ModelTests: XCTestCase {
    func testKeyComboDisplayOrder() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_4), carbonModifiers: UInt32(cmdKey | shiftKey | optionKey), key: "4")
        XCTAssertEqual(combo.displayString, "⌥⇧⌘4")
        XCTAssertEqual(combo.eventModifiers, [.option, .shift, .command])
        XCTAssertEqual(combo.menuKeyEquivalent, "4")
    }

    func testKeyComboRoundTripsThroughJSON() throws {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_S), carbonModifiers: UInt32(cmdKey), key: "S")
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(combo))
        XCTAssertEqual(decoded, combo)
    }

    func testExportFactor() {
        var options = ExportOptions()
        XCTAssertEqual(options.factor(canvasWidth: 1000), 1)
        options.resizeMode = .percent
        options.percent = 50
        XCTAssertEqual(options.factor(canvasWidth: 1000), 0.5)
        options.percent = 1000
        XCTAssertEqual(options.factor(canvasWidth: 1000), 4, "percent is capped at 400%")
        options.resizeMode = .width
        options.width = 500
        XCTAssertEqual(options.factor(canvasWidth: 1000), 0.5)
        XCTAssertEqual(options.factor(canvasWidth: 0), 1, "no division by zero")
    }

    func testGradientIndexIsClamped() {
        var background = BackgroundSettings()
        background.gradientIndex = 999
        XCTAssertEqual(background.gradientColors, GradientPreset.all.last?.colors)
        background.gradientIndex = -3
        XCTAssertEqual(background.gradientColors, GradientPreset.all.first?.colors)
    }

    func testPresetsSurviveJSON() throws {
        let presets = Preset.builtIns
        let decoded = try JSONDecoder().decode([Preset].self, from: JSONEncoder().encode(presets))
        XCTAssertEqual(decoded, presets)
    }
}
