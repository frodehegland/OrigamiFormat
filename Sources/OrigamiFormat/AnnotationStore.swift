import Foundation

// Ported from Origami Text's AnnotationStore.swift so both apps read the same
// sidecars — keep synced; a fix here should be carried back.

/// A reader's web annotations live beside the cards in the Record Store: one
/// JSON-LD sidecar per annotated document, `<id>.annotations.jsonld`, holding
/// a W3C AnnotationCollection.
///
/// They are never written into the document itself — the PDF (or EPUB, or
/// Origami file) is the author's; the annotations are the reader's, and the
/// library folder may be read-only or an iCloud folder we must not touch.
/// Because the sidecar is a standard AnnotationCollection in a folder other
/// apps can see, any system that reads Web Annotations can read a reader's
/// notes without knowing anything about Reader.
public nonisolated enum AnnotationStore {

    public static let fileSuffix = ".annotations.jsonld"

    public static func fileName(for documentID: String) -> String {
        documentID + fileSuffix
    }

    public static func fileURL(for documentID: String, in folder: URL) -> URL {
        folder.appendingPathComponent(fileName(for: documentID))
    }

    /// Every annotation in the document's sidecar, oldest first. A missing or
    /// unreadable sidecar is an empty list, never an error.
    public static func load(for documentID: String, in folder: URL?) -> [WebAnnotation] {
        guard let folder else { return [] }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: fileURL(for: documentID, in: folder)),
              let collection = try? JSONDecoder().decode(CollectionFile.self, from: data)
        else { return [] }
        return collection.items.sorted { $0.created < $1.created }
    }

    /// Every sidecar in the folder, keyed by the annotated document's id — the
    /// cross-document view of a reader's notes. One folder scan; unreadable
    /// sidecars simply contribute nothing.
    public static func loadAll(in folder: URL?) -> [String: [WebAnnotation]] {
        guard let folder else { return [:] }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        else { return [:] }
        var all: [String: [WebAnnotation]] = [:]
        for name in names where name.hasSuffix(fileSuffix) {
            let documentID = String(name.dropLast(fileSuffix.count))
            let annotations = load(for: documentID, in: folder)
            if !annotations.isEmpty { all[documentID] = annotations }
        }
        return all
    }

    /// The sidecar's bytes as they stand — a W3C AnnotationCollection — for
    /// Share / Export Annotations, and for anything outside Reader that wants
    /// them whole.
    public static func exportData(for documentID: String, in folder: URL?) -> Data? {
        guard let folder else { return nil }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: fileURL(for: documentID, in: folder))
    }

    /// Writes the sidecar, or removes it when the last annotation is gone.
    /// False when the notes did not reach the disk — the caller owes the
    /// reader that truth.
    @discardableResult
    public static func save(_ annotations: [WebAnnotation],
                            for documentID: String, in folder: URL?) -> Bool {
        guard let folder else { return false }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = fileURL(for: documentID, in: folder)
            guard !annotations.isEmpty else {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                return true
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(CollectionFile(items: annotations))
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Adds one annotation to a document's sidecar. Returns false when the
    /// write failed.
    @discardableResult
    public static func append(_ annotation: WebAnnotation,
                              for documentID: String, in folder: URL?) -> Bool {
        var all = load(for: documentID, in: folder)
        all.append(annotation)
        return save(all, for: documentID, in: folder)
    }

    /// Replaces an annotation with the same id, or adds it when it is new.
    @discardableResult
    public static func update(_ annotation: WebAnnotation,
                              for documentID: String, in folder: URL?) -> Bool {
        var all = load(for: documentID, in: folder)
        if let index = all.firstIndex(where: { $0.id == annotation.id }) {
            var revised = annotation
            revised.modified = Date()
            all[index] = revised
        } else {
            all.append(annotation)
        }
        return save(all, for: documentID, in: folder)
    }

    @discardableResult
    public static func remove(id: String, for documentID: String, in folder: URL?) -> Bool {
        var all = load(for: documentID, in: folder)
        all.removeAll { $0.id == id }
        return save(all, for: documentID, in: folder)
    }

    /// The sidecar's shape: a W3C AnnotationCollection with its items inline
    /// (no paging — a reader's notes on one document stay small).
    private nonisolated struct CollectionFile: Codable {
        var items: [WebAnnotation]

        enum CodingKeys: String, CodingKey {
            case context = "@context"
            case type, total, items
        }

        init(items: [WebAnnotation]) { self.items = items }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(WebAnnotation.context, forKey: .context)
            try container.encode("AnnotationCollection", forKey: .type)
            try container.encode(items.count, forKey: .total)
            try container.encode(items, forKey: .items)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decodeIfPresent([Lossy].self, forKey: .items)?
                .compactMap(\.annotation) ?? []
        }

        /// One unreadable annotation never sinks the sidecar.
        private nonisolated struct Lossy: Decodable {
            let annotation: WebAnnotation?
            init(from decoder: Decoder) throws {
                annotation = try? WebAnnotation(from: decoder)
            }
        }
    }
}
