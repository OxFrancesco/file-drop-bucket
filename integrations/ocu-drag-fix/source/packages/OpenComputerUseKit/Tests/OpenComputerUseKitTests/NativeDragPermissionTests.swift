import XCTest
@testable import OpenComputerUseKit

final class NativeDragPermissionTests: XCTestCase {
    func testNativeDragRequiresExplicitPointerConsent() {
        XCTAssertThrowsError(try requireNativeDragPermission(environment: [:]))
        for value in ["", "0", "false", "no", "off"] {
            XCTAssertThrowsError(try requireNativeDragPermission(environment: ["OPEN_COMPUTER_USE_ALLOW_NATIVE_DRAG": value]))
        }
    }

    func testDragOnlyConsentDoesNotEnableGlobalClicksOrScrolling() {
        for value in ["1", "true", " YES ", "on"] {
            let environment = ["OPEN_COMPUTER_USE_ALLOW_NATIVE_DRAG": value]
            XCTAssertNoThrow(try requireNativeDragPermission(environment: environment))
            XCTAssertFalse(globalPointerFallbacksEnabled(environment: environment))
        }
    }

    func testExistingGlobalConsentStillAllowsDragging() {
        XCTAssertNoThrow(try requireNativeDragPermission(environment: ["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS": "1"]))
    }
}
