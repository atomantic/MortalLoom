import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {

    var app: XCUIApplication!

    private static let projectDir: String = {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }()

    private static let launchArgs = ["-sample-data", "-hasCompletedOnboarding", "1", "-force-pro"]

    private lazy var cachedConfig: [String: String] = {
        for path in ["\(Self.projectDir)/.screenshot_config.json",
                     "/tmp/mortalloom_screenshot_config.json"] {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                return dict
            }
        }
        return [:]
    }()

    private var deviceType: String {
        cachedConfig["device"] ?? "iphone_6.7"
    }

    private var isIPad: Bool {
        if let device = cachedConfig["device"] { return device.hasPrefix("ipad") }
        return UIDevice.current.userInterfaceIdiom == .pad
    }

    private var outputDir: String {
        cachedConfig["output_dir"] ?? "\(Self.projectDir)/screenshots"
    }

    private var targetScreen: String? {
        let s = cachedConfig["target_screen"] ?? ""
        return s.isEmpty ? nil : s
    }

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = Self.launchArgs
        app.launch()
        try await Task.sleep(for: .seconds(3))
        dismissSystemAlerts()
    }

    // MARK: - iPhone Screenshots

    func testCaptureIPhoneScreenshots() throws {
        guard !isIPad else { return }

        saveScreenshot("01_overview")

        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        saveScreenshot("02_overview_scroll")
        app.swipeDown()
        app.swipeDown()
        Thread.sleep(forTimeInterval: 0.3)

        tapCustomTab("Goals")
        saveScreenshot("03_goals")

        tapCustomTab("Habits")
        saveScreenshot("04_habits_alcohol")

        if app.buttons["Nicotine"].waitForExistence(timeout: 2) {
            app.buttons["Nicotine"].tap()
            Thread.sleep(forTimeInterval: 1)
            saveScreenshot("05_habits_nicotine")
        }

        tapCustomTab("Body")
        saveScreenshot("06_body")

        tapHamburger()
        tapSideMenuItem("Blood")
        saveScreenshot("07_blood")

        tapCustomTab("Calendar")
        saveScreenshot("08_calendar")

        tapHamburger()
        tapSideMenuItem("Sleep")
        saveScreenshot("09_sleep")

        tapHamburger()
        tapSideMenuItem("Lifestyle")
        saveScreenshot("10_lifestyle")
    }

    // MARK: - iPad Screenshots

    func testCaptureIPadScreenshots() throws {
        guard isIPad else { return }

        saveScreenshot("01_overview")

        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        saveScreenshot("02_overview_scroll")
        app.swipeDown()
        app.swipeDown()
        Thread.sleep(forTimeInterval: 0.3)

        tapCustomTab("Goals")
        saveScreenshot("03_goals")

        tapCustomTab("Habits")
        saveScreenshot("04_habits_alcohol")

        tapCustomTab("Body")
        saveScreenshot("05_body")

        tapHamburger()
        tapSideMenuItem("Blood")
        saveScreenshot("06_blood")

        tapCustomTab("Calendar")
        saveScreenshot("07_calendar")

        tapHamburger()
        tapSideMenuItem("Sleep")
        saveScreenshot("08_sleep")
    }

    // MARK: - Helpers

    private func tapCustomTab(_ name: String) {
        let button = app.buttons[name]
        if button.waitForExistence(timeout: 3) {
            button.tap()
            Thread.sleep(forTimeInterval: 1)
            return
        }
        let text = app.staticTexts[name]
        if text.waitForExistence(timeout: 2) {
            text.tap()
            Thread.sleep(forTimeInterval: 1)
        }
    }

    private func tapHamburger() {
        let navBar = app.navigationBars.firstMatch
        if navBar.waitForExistence(timeout: 2) {
            navBar.buttons.element(boundBy: 0).tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    private func tapSideMenuItem(_ name: String) {
        for element in [app.buttons[name], app.staticTexts[name]] {
            if element.waitForExistence(timeout: 2) {
                element.tap()
                Thread.sleep(forTimeInterval: 1)
                return
            }
        }
    }

    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Don't Allow", "OK"] {
            let btn = springboard.buttons[label]
            if btn.waitForExistence(timeout: 1) {
                btn.tap()
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }

    private func saveScreenshot(_ name: String) {
        if let target = targetScreen, target != name { return }

        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(deviceType)_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let dir = "\(outputDir)/en/\(deviceType)"
        let url = URL(fileURLWithPath: "\(dir)/\(name).png")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: url)
    }
}
