import Foundation

enum DeepLink {
    static func noteID(from url: URL) -> UUID? {
        guard url.scheme == "cache" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = url.host ?? url.path.replacingOccurrences(of: "/", with: "")
        guard path == "edit" else { return nil }
        let idString = components?.queryItems?.first(where: { $0.name == "id" })?.value
        guard let idString, let id = UUID(uuidString: idString) else {
            return nil
        }
        return id
    }
}
