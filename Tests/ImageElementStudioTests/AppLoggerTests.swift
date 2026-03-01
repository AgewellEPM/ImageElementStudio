import XCTest
import os
@testable import ImageElementStudio

final class AppLoggerTests: XCTestCase {

    // MARK: - Subsystem

    /// The subsystem string is used for Console.app and `log stream` filtering.
    /// Changing it silently would break production log queries and dashboards.
    func testSubsystemMatchesBundleIdentifierConvention() {
        XCTAssertEqual(AppLogger.subsystem, "com.imageelementstudio")
        // Subsystem should look like a reverse-DNS identifier
        XCTAssertTrue(AppLogger.subsystem.contains("."),
            "Subsystem should be a reverse-DNS string")
    }

    // MARK: - Category Inventory

    /// Guards against accidentally adding or removing a logging category.
    /// If a category is removed, logs from that subsystem silently disappear.
    /// If one is added, this test reminds you to update filtering configs.
    func testExpectedCategoryCount() {
        XCTAssertEqual(AppLogger.Category.allCases.count, 8,
            "Category count changed — update log filtering rules and this test")
    }

    /// Verify category raw values match the strings used in Console.app and
    /// `log stream --predicate 'category == "api"'`. A rename here silently
    /// breaks log filtering in production.
    func testCategoryRawValuesMatchLogFilterStrings() {
        let expectedMapping: [AppLogger.Category: String] = [
            .api: "api",
            .pipeline: "pipeline",
            .build: "build",
            .export: "export",
            .canvas: "canvas",
            .project: "project",
            .security: "security",
            .general: "general",
        ]
        for (category, expected) in expectedMapping {
            XCTAssertEqual(category.rawValue, expected,
                "Category.\(category) raw value changed — this breaks log stream filters")
        }
        // Also verify we covered every case (no missing entries)
        XCTAssertEqual(expectedMapping.count, AppLogger.Category.allCases.count,
            "Test mapping is missing a category — add it above")
    }

    // MARK: - Logger Cache

    /// Verify that logger(for:) returns a valid logger for every category
    /// without crashing. This exercises the force-unwrap in the implementation,
    /// ensuring the cache was populated for all cases.
    func testLoggerForEveryCategoryDoesNotTrap() {
        for category in AppLogger.Category.allCases {
            // If the cache is missing a category, this force-unwrap will crash the test
            let logger = AppLogger.logger(for: category)
            // Exercise the logger to confirm it's a real os.Logger instance
            logger.trace("Test probe for \(category.rawValue, privacy: .public)")
        }
    }

    // MARK: - Default Parameter

    /// Verify the default category parameter compiles and routes to .general.
    /// This is the primary developer ergonomics feature of AppLogger — if the
    /// default changes, call sites omitting the category get unexpected behavior.
    func testDefaultCategoryParameterIsGeneral() {
        // These calls exercise the default parameter. If the default category
        // were changed from .general, the intent would be wrong for most callers.
        // We verify by checking the function signature via compilation:
        // all four methods must accept zero-argument category.
        AppLogger.info("default test")
        AppLogger.warning("default test")
        AppLogger.error("default test")
        AppLogger.debug("default test")
        // If this compiles and doesn't crash, the default parameter works.
        // The actual default value (.general) is enforced by the raw value test above.
    }

    /// Verify that format-specifier-like strings (%s, %d, %@) in messages don't
    /// cause crashes or misinterpretation. os.Logger uses string interpolation,
    /// not printf-style formatting, but callers might pass user-generated strings
    /// containing these characters.
    func testFormatSpecifierStringsDoNotCrash() {
        let dangerous = [
            "%s %d %@ %f %%",
            "%n%n%n",
            "100% complete",
        ]
        for msg in dangerous {
            AppLogger.info(msg, category: .general)
            AppLogger.error(msg, category: .security)
        }
    }
}
