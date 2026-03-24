import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-sample-data"]
        app.launch()
        Thread.sleep(forTimeInterval: 3)
    }

    func testCaptureAllPages() throws {
        let dir = "/Users/antic/github.com/atomantic/MortalLoom/screenshots"

        // 1. Overview (default page)
        Thread.sleep(forTimeInterval: 1)
        save("01-overview", to: dir)

        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        save("01b-overview-scroll", to: dir)
        app.swipeDown()
        app.swipeDown()
        Thread.sleep(forTimeInterval: 0.3)

        // 2. Habits - Alcohol
        tapCustomTab("Habits")
        save("02-habits-alcohol", to: dir)

        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        save("03-habits-alcohol-hrv", to: dir)
        app.swipeDown()
        app.swipeDown()
        Thread.sleep(forTimeInterval: 0.3)

        // Nicotine sub-tab
        if app.buttons["Nicotine"].waitForExistence(timeout: 2) {
            app.buttons["Nicotine"].tap()
            Thread.sleep(forTimeInterval: 1)
            save("04-habits-nicotine", to: dir)

            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
            save("05-habits-nicotine-hr", to: dir)
            app.swipeDown()
            app.swipeDown()
            Thread.sleep(forTimeInterval: 0.3)
        }

        // 3. Body
        tapCustomTab("Body")
        save("06-body", to: dir)

        // 4. Blood
        tapCustomTab("Blood")
        save("07-blood", to: dir)

        // 5. Calendar
        tapCustomTab("Calendar")
        save("08-calendar", to: dir)

        // 6. Lifestyle via side menu
        tapHamburger()
        tapSideMenuItem("Lifestyle")
        save("09-lifestyle", to: dir)

        // 7. Genome
        tapHamburger()
        tapSideMenuItem("Genome")
        save("10-genome", to: dir)

        // 8. Settings
        tapHamburger()
        tapSideMenuItem("Settings")
        save("11-settings", to: dir)
    }

    // MARK: - Helpers

    private func tapCustomTab(_ name: String) {
        // Custom tab bar uses plain buttons with the page title as text
        let button = app.buttons[name]
        if button.waitForExistence(timeout: 3) {
            button.tap()
            Thread.sleep(forTimeInterval: 1)
            return
        }
        // Fallback: try static text
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

    private func save(_ name: String, to dir: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let url = URL(fileURLWithPath: "\(dir)/\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
    }
}
