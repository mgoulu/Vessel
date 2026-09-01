import XCTest
@testable import Vessel

final class ImageRecordTests: XCTestCase {
    func testImageMetadataAndProjectMatching() throws {
        let json = #"{"id":"abcdef1234567890","configuration":{"creationDate":"2026-08-13T16:03:39Z","name":"registry.example.com/optionbook:main-123"},"variants":[{"size":80},{"size":20}]}"#
        let image = try JSONDecoder().decode(ImageRecord.self, from: Data(json.utf8))

        XCTAssertEqual(image.projectName, "optionbook")
        XCTAssertEqual(image.sizeBytes, 100)
        XCTAssertEqual(image.shortDigest, "abcdef123456")
        XCTAssertEqual(ImageRecord.projectName(from: "docker.io/library/optionbook:local"), "optionbook")
    }
}
