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
        captureAppStoreScreenshots()
    }

    // MARK: - iPad Screenshots

    func testCaptureIPadScreenshots() throws {
        guard isIPad else { return }
        captureAppStoreScreenshots()
    }

    func testCustomizeBottomTabBarAndKeepOtherPagesInMore() throws {
        let more = app.buttons["bottom-tab-more"]
        let customize = app.buttons["customize-bottom-tab-bar"]
        let reset = app.buttons["reset-bottom-tab-shortcuts"]
        let calendarTab = app.buttons["bottom-tab-5"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        XCTAssertTrue(customize.waitForExistence(timeout: 5))
        customize.tap()
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()

        let first = app.descendants(matching: .any)["first-bottom-tab-shortcut"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        let choices = app.buttons.matching(identifier: "Calendar")
        let visibleChoice = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            choices.allElementsBoundByIndex.contains { $0.isHittable }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visibleChoice], timeout: 5), .completed)
        try XCTUnwrap(choices.allElementsBoundByIndex.first { $0.isHittable }).tap()
        app.buttons["Done"].tap()
        app.buttons["dismiss-side-menu"].tap()
        XCTAssertTrue(calendarTab.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["bottom-tab-11"].exists)

        app.terminate()
        app.launch()
        XCTAssertTrue(calendarTab.waitForExistence(timeout: 5))
        more.tap()
        XCTAssertTrue(app.buttons["Habits"].waitForExistence(timeout: 5))
        customize.tap()
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()
        app.buttons["Done"].tap()
        app.buttons["dismiss-side-menu"].tap()
        XCTAssertTrue(app.buttons["bottom-tab-3"].waitForExistence(timeout: 5))
        XCTAssertFalse(calendarTab.exists)
    }

    // MARK: - Shared Capture Flow

    /// Shared capture sequence used by both iPhone and iPad tests. The nav flow
    /// is identical on both idioms: 4 pages live in the bottom tab bar
    /// (Overview, Goals, Habits, Reports by default) and the rest are reached through the
    /// "More" button which opens the side menu.
    private func captureAppStoreScreenshots() {
        saveScreenshot("01_overview")

        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        saveScreenshot("02_overview_scroll")
        app.swipeDown()
        app.swipeDown()
        Thread.sleep(forTimeInterval: 0.3)

        tapCustomTab("Goals")
        saveScreenshot("03_goals")

        openSideMenu()
        tapSideMenuItem("Calendar")
        saveScreenshot("04_calendar")

        tapCustomTab("Habits")
        if app.buttons["My Habits"].waitForExistence(timeout: 2) {
            app.buttons["My Habits"].tap()
        }
        Thread.sleep(forTimeInterval: 0.5)
        saveScreenshot("05_habits")

        if app.buttons["Alcohol"].waitForExistence(timeout: 2) {
            app.buttons["Alcohol"].tap()
            Thread.sleep(forTimeInterval: 0.5)
            saveScreenshot("05a_habits_alcohol")
        }

        if app.buttons["Nicotine"].waitForExistence(timeout: 2) {
            app.buttons["Nicotine"].tap()
            Thread.sleep(forTimeInterval: 1)
            saveScreenshot("06_habits_nicotine")
        }

        openSideMenu()
        tapSideMenuItem("Body")
        saveScreenshot("07_body")

        openSideMenu()
        tapSideMenuItem("Blood")
        saveScreenshot("08_blood")

        openSideMenu()
        tapSideMenuItem("Sleep")
        saveScreenshot("09_sleep")

        openSideMenu()
        tapSideMenuItem("Lifestyle")
        saveScreenshot("10_lifestyle")
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

    /// Opens the side menu by tapping the "More" button in the bottom tab bar.
    private func openSideMenu() {
        let more = app.buttons["More"]
        if more.waitForExistence(timeout: 3) {
            more.tap()
            Thread.sleep(forTimeInterval: 0.6)
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
