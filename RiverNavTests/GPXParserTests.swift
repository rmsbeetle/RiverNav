import CoreLocation
import XCTest
@testable import RiverNav

final class GPXParserTests: XCTestCase {
    var parser: GPXParser!

    override func setUp() {
        super.setUp()
        parser = GPXParser()
    }

    func testParsesTrkpt() {
        let coords = parser.parse(data: gpxData(body: """
        <trk><trkseg>
          <trkpt lat="55.7558" lon="37.6173"/>
          <trkpt lat="55.7600" lon="37.6200"/>
        </trkseg></trk>
        """))
        XCTAssertEqual(coords.count, 2)
        XCTAssertEqual(coords[0].latitude,  55.7558, accuracy: 1e-4)
        XCTAssertEqual(coords[0].longitude, 37.6173, accuracy: 1e-4)
        XCTAssertEqual(coords[1].latitude,  55.7600, accuracy: 1e-4)
    }

    func testParsesRtept() {
        let coords = parser.parse(data: gpxData(body: """
        <rte>
          <rtept lat="55.7700" lon="37.6300"/>
          <rtept lat="55.7750" lon="37.6350"/>
        </rte>
        """))
        XCTAssertEqual(coords.count, 2)
        XCTAssertEqual(coords[0].latitude,  55.7700, accuracy: 1e-4)
        XCTAssertEqual(coords[0].longitude, 37.6300, accuracy: 1e-4)
    }

    func testParsesMixedFromFile() throws {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "test_route", withExtension: "gpx"),
            "test_route.gpx not found in test bundle"
        )
        let coords = parser.parse(data: try Data(contentsOf: url))
        XCTAssertEqual(coords.count, 5) // 3 trkpt + 2 rtept
    }

    func testEmptyGPX() {
        let coords = parser.parse(data: gpxData(body: ""))
        XCTAssertTrue(coords.isEmpty)
    }

    func testInvalidXML() {
        let coords = parser.parse(data: Data("not xml at all".utf8))
        XCTAssertTrue(coords.isEmpty)
    }

    func testMissingLonIgnored() {
        // trkpt with only lat — must be skipped
        let coords = parser.parse(data: gpxData(body: """
        <trk><trkseg><trkpt lat="55.0"/></trkseg></trk>
        """))
        XCTAssertTrue(coords.isEmpty)
    }

    // MARK: - Helper

    private func gpxData(body: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">\(body)</gpx>
        """.utf8)
    }
}
