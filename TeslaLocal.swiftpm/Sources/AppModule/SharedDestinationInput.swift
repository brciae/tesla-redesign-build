import Foundation

struct SharedDestinationInput {
    var query: String
    var latitude: Double?
    var longitude: Double?
    static func parse(_ raw: String) throws -> Self {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2000 else { throw InputError.invalid }
        guard text.contains("://") else { return .init(query: String(text.prefix(300))) }
        guard let url = URLComponents(string: text), url.user == nil, url.password == nil else { throw InputError.invalid }
        let hosts = ["map.naver.com", "m.map.naver.com", "maps.apple.com", "maps.google.com", "www.google.com", "map.kakao.com", "kko.kakao.com", "naver.me", "maps.app.goo.gl"]
        guard ["nmap", "tmap", "kakaonavi"].contains(url.scheme ?? "") || (["http", "https"].contains(url.scheme ?? "") && hosts.contains(url.host ?? "")) else { throw InputError.invalid }
        let items = url.queryItems ?? []
        func item(_ keys: [String]) -> String? { keys.compactMap { key in items.first { $0.name == key }?.value }.first }
        var lat = item(["dlat", "lat", "latitude", "y"]).flatMap(Double.init)
        var lon = item(["dlng", "lng", "longitude", "x"]).flatMap(Double.init)
        if let ll = item(["ll"]), lat == nil { let values = ll.split(separator: ",").compactMap { Double($0) }; if values.count == 2 { lat = values[0]; lon = values[1] } }
        let name = item(["dname", "name", "query", "q"]) ?? ""
        if lat == nil, url.host == "map.kakao.com", url.path.hasPrefix("/link/map/") {
            let values = url.path.split(separator: ","); if values.count >= 3 { lat = Double(values[values.count - 2]); lon = Double(values[values.count - 1]) }
        }
        if let lat, let lon, lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon), !(lat == 0 && lon == 0) {
            return .init(query: name.isEmpty ? "공유된 목적지" : String(name.prefix(120)), latitude: lat, longitude: lon)
        }
        if lat != nil || lon != nil { throw InputError.invalid }
        guard !name.isEmpty, !name.contains("://") else { throw InputError.shortLink }
        return .init(query: String(name.prefix(300)))
    }
    enum InputError: LocalizedError {
        case invalid, shortLink
        var errorDescription: String? {
            switch self {
            case .shortLink: return "짧은 지도 링크에는 위치가 없음. 원본 지도 앱에서 주소 또는 전체 위치 링크로 공유 필요함."
            case .invalid: return "장소·주소 또는 지원하는 지도 위치 링크 확인 필요함"
            }
        }
    }
}
