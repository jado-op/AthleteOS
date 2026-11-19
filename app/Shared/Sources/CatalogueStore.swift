import Foundation

/// A merged, queryable view over every pack currently downloaded (§3: "every
/// downloaded sport's full library... works offline always"). Built once
/// from whatever is on disk — however partial that is — never assumed to be
/// the whole catalogue.
public struct Catalogue: Sendable {
    public let itemsBySlug: [String: CatalogueItem]
    public let sportsBySlug: [String: SportInfo]

    public init(itemsBySlug: [String: CatalogueItem] = [:], sportsBySlug: [String: SportInfo] = [:]) {
        self.itemsBySlug = itemsBySlug
        self.sportsBySlug = sportsBySlug
    }

    public func item(_ slug: String) -> CatalogueItem? {
        itemsBySlug[slug]
    }
}

public enum CatalogueLoader {
    /// Decodes every `.json` pack file in `packsDirectory` (skipping
    /// `manifest.json`, which isn't a pack) into one merged `Catalogue`. A
    /// pack file that fails to decode — corrupted, mid-write, an unexpected
    /// future shape — is skipped rather than aborting the whole load: one
    /// bad file should never make every OTHER already-downloaded sport
    /// unusable, matching PackDownloader's own fail-closed-per-file design.
    public static func load(from packsDirectory: URL, fileManager: FileManager = .default) -> Catalogue {
        let files = (try? fileManager.contentsOfDirectory(
            at: packsDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        )) ?? []
        let packs = files.filter { $0.pathExtension == "json" && $0.lastPathComponent != "manifest.json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        // The packs (~2 MB of JSON) are decoded once and kept until a pack
        // file changes (a pack install, an update): screens ask for the
        // catalogue many times, and decoding it each time was slow.
        let key = packsDirectory.path + "|" + packs.map { file -> String in
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return "\(file.lastPathComponent):\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values?.fileSize ?? 0)"
        }.joined(separator: ",")

        var itemsBySlug: [String: CatalogueItem] = [:]
        var sportsBySlug: [String: SportInfo] = [:]
        if let cached = memo.get(key) {
            itemsBySlug = cached.items
            sportsBySlug = cached.sports
        } else {
            let decoder = JSONDecoder()
            for file in packs {
                guard
                    let data = try? Data(contentsOf: file),
                    let pack = try? decoder.decode(CataloguePack.self, from: data)
                else { continue }

                for item in pack.items {
                    itemsBySlug[item.slug] = item
                }
                if let sport = pack.sport {
                    sportsBySlug[sport.slug] = sport
                }
            }
            memo.set(key, items: itemsBySlug, sports: sportsBySlug)
        }

        // Exercises quarantined by the knowledge release are never offered.
        for slug in KnowledgeReleaseStore.current.quarantinedItems { itemsBySlug[slug] = nil }
        return Catalogue(itemsBySlug: itemsBySlug, sportsBySlug: sportsBySlug)
    }

    /// The last decoded packs, by the packs' names, dates and sizes.
    private final class Memo: @unchecked Sendable {
        private let lock = NSLock()
        private var key: String?
        private var items: [String: CatalogueItem] = [:]
        private var sports: [String: SportInfo] = [:]

        func get(_ key: String) -> (items: [String: CatalogueItem], sports: [String: SportInfo])? {
            lock.lock()
            defer { lock.unlock() }
            return self.key == key ? (items, sports) : nil
        }

        func set(_ key: String, items: [String: CatalogueItem], sports: [String: SportInfo]) {
            lock.lock()
            defer { lock.unlock() }
            self.key = key
            self.items = items
            self.sports = sports
        }
    }

    private static let memo = Memo()
}
