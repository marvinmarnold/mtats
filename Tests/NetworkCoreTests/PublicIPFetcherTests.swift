// Tests/NetworkCoreTests/PublicIPFetcherTests.swift
// SPDX-License-Identifier: MIT
import XCTest
@testable import NetworkCore

final class PublicIPFetcherTests: XCTestCase {
    func test_parsesPlainTextIPResponse() {
        XCTAssertEqual(PublicIPFetcher.parse(responseBody: "203.0.113.42\n"), "203.0.113.42")
    }

    func test_rejectsGarbageResponse() {
        // Review Focus: a captive portal or proxy can return an HTML error page instead of
        // an IP. Must return nil, not a garbage "IP".
        XCTAssertNil(PublicIPFetcher.parse(responseBody: "<html>captive portal</html>"))
    }

    func test_rejectsEmptyResponse() {
        XCTAssertNil(PublicIPFetcher.parse(responseBody: ""))
    }
}
