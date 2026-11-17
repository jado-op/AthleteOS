import Foundation

/// "Need to talk to someone?" — who to call, by country. Configured here;
/// the phone's region picks the entry (Germany: Nummer gegen Kummer).
public struct SupportResource: Equatable, Sendable {
    public let name: String
    /// Dialable digits for a tel: link, or nil when there is no single number.
    public let phone: String?
    /// The number as people write it.
    public let display: String?
    public let detail: String
    public let emergency: String
    public let website: String?
}

public enum SupportResources {
    /// Region code (ISO 3166) → resource. Add a country here.
    public static let byRegion: [String: SupportResource] = [
        "DE": SupportResource(name: "Nummer gegen Kummer", phone: "116111", display: "116 111",
                              detail: "Kinder- und Jugendtelefon: free and anonymous, Monday to Saturday, 2–8 pm.",
                              emergency: "112", website: "https://www.nummergegenkummer.de"),
        "AT": SupportResource(name: "Rat auf Draht", phone: "147", display: "147",
                              detail: "Free and anonymous, any time.", emergency: "112", website: "https://www.rataufdraht.at"),
        "CH": SupportResource(name: "Pro Juventute 147", phone: "147", display: "147",
                              detail: "Free and confidential, any time — also by chat and text.", emergency: "112",
                              website: "https://www.147.ch"),
        "US": SupportResource(name: "988 Suicide & Crisis Lifeline", phone: "988", display: "988",
                              detail: "Call or text, free, any time.", emergency: "911", website: "https://988lifeline.org"),
        "GB": SupportResource(name: "Childline", phone: "08001111", display: "0800 1111",
                              detail: "Free and confidential, any time.", emergency: "999", website: "https://www.childline.org.uk"),
    ]

    /// Anywhere else.
    public static let fallback = SupportResource(
        name: "Someone you trust", phone: nil, display: nil,
        detail: "Talk to a parent, a coach, a teacher or another adult you trust.",
        emergency: "your local emergency number", website: nil)

    public static func resource(region: String?) -> SupportResource {
        region.flatMap { byRegion[$0.uppercased()] } ?? fallback
    }
}
