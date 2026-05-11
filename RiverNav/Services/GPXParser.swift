import CoreLocation
import Foundation

final class GPXParser: NSObject {
    private var coordinates: [CLLocationCoordinate2D] = []

    func parse(data: Data) -> [CLLocationCoordinate2D] {
        coordinates = []
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.parse()
        return coordinates
    }
}

extension GPXParser: XMLParserDelegate {
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "trkpt" || elementName == "rtept",
              let latStr = attributeDict["lat"], let lat = Double(latStr),
              let lonStr = attributeDict["lon"], let lon = Double(lonStr)
        else { return }
        coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }
}
