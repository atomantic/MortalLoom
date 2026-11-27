import CryptoKit
import Foundation

/// The native model deliberately models only the fields it owns. This layer
/// overlays native edits onto the original document so that an unrelated save
/// never encodes away PortOS extensions or fields from a newer native app.
enum SharedStoreDocument: Codable, Equatable {
    case boolean(Bool)
    case string(String)
    case number(Decimal)
    case null
    case array([Self])
    case object([String: Self])

    static let replacementKey = "_mortalLoomSync"

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode([String: Self].self) { self = .object(value) }
        else if let value = try? c.decode([Self].self) { self = .array(value) }
        else if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else { self = .number(try c.decode(Decimal.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .boolean(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .null: try c.encodeNil()
        case .array(let value): try c.encode(value)
        case .object(let value): try c.encode(value)
        }
    }

    private var fields: [String: Self]? {
        guard case .object(let fields) = self else { return nil }
        return fields
    }

    private var rows: [Self]? {
        guard case .array(let rows) = self else { return nil }
        return rows
    }

    private var string: String? {
        guard case .string(let string) = self else { return nil }
        return string
    }

    static func encoded<T: Encodable>(_ object: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(object)
    }

    static func parse(_ bytes: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: bytes)
        guard value.fields != nil else { throw Conflict() }
        return value
    }

    struct Conflict: Error {}

    static func signature(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func explicitReplacement(_ bytes: Data, predecessor: Data?) throws -> Data {
        guard var fields = try parse(bytes).fields else { throw Conflict() }
        fields.removeValue(forKey: replacementKey)
        if let predecessor {
            fields[replacementKey] = .object([
                "version": .number(1),
                "parentSHA256": .string(signature(predecessor)),
                "kind": .string("replace")
            ])
        }
        return try encoded(Self.object(fields))
    }

    static func isExplicitReplacement(_ incoming: Data, of predecessor: Data) -> Bool {
        guard let marker = (try? parse(incoming))?.fields?[replacementKey]?.fields else { return false }
        return marker["version"] == .number(1) &&
               marker["kind"] == .string("replace") &&
               marker["parentSHA256"] == .string(signature(predecessor))
    }

    /// Apply only the semantic native change. If the writer did not edit a
    /// field, keep its original raw representation (including an omitted key).
    static func applyingNativeChange(from before: Data, to after: Data, over raw: Data) throws -> Data {
        guard var result = try overlay(parse(raw), parse(before), parse(after), key: nil)?.fields else {
            throw Conflict()
        }
        // A previous explicit marker must not authorize the contraction of
        // a later unrelated revision.
        result.removeValue(forKey: replacementKey)
        return try encoded(Self.object(result))
    }

    static func withoutReplacementMarker(_ bytes: Data) throws -> Data {
        guard var fields = try parse(bytes).fields else { throw Conflict() }
        fields.removeValue(forKey: replacementKey)
        return try encoded(Self.object(fields))
    }

    /// A definite deletion wins over an unchanged copy, not an independently
    /// edited one. Differences in separate fields/rows can be combined.
    static func merge(base: Data, local: Data, cloud: Data) throws -> Data {
        let rawRemote = try parse(cloud)
        var b = try parse(base).fields ?? [:]
        var l = try parse(local).fields ?? [:]
        var r = rawRemote.fields ?? [:]
        b.removeValue(forKey: replacementKey)
        l.removeValue(forKey: replacementKey)
        r.removeValue(forKey: replacementKey)
        guard var result = try mergeValue(.object(b), .object(l), .object(r), key: nil)?.fields else {
            throw Conflict()
        }
        // The remote marker describes an actual remote replacement. It is not
        // manufactured by combining local and remote user data.
        result[replacementKey] = rawRemote.fields?[replacementKey]
        return try encoded(Self.object(result))
    }

    private static func identity(_ row: Self, by key: String?) -> String? {
        if key == "healthMetrics" { return row.fields?["date"]?.string }
        guard let id = row.fields?["id"]?.string, let uuid = UUID(uuidString: id) else { return nil }
        return uuid.uuidString
    }

    /// Only arrays with unique, stable identities may be merged item by item.
    /// Positional arrays, duplicates and unknown shapes are handled atomically.
    private static func indexed(_ rows: [Self], by key: String?) -> (order: [String], rows: [String: Self])? {
        var order: [String] = []
        var index: [String: Self] = [:]
        for row in rows {
            guard let id = identity(row, by: key), index[id] == nil else { return nil }
            index[id] = row
            order.append(id)
        }
        return (order, index)
    }

    private static func overlay(_ raw: Self?, _ before: Self?, _ after: Self?, key: String?) throws -> Self? {
        if before == after { return raw }
        guard let after else { return nil }
        if let now = after.fields, let old = before?.fields {
            var result = raw?.fields ?? [:]
            for field in Set(old.keys).union(now.keys) {
                result[field] = try overlay(result[field], old[field], now[field], key: field)
            }
            return .object(result)
        }
        if let a = after.rows, let b = before?.rows, let raw = raw?.rows,
           let ai = indexed(a, by: key), let bi = indexed(b, by: key) {
            // Don't normalize away ambiguous loaded identities on a save.
            guard let ri = indexed(raw, by: key) else { throw Conflict() }
            // Retain extensions on matching rows but don't resurrect deleted
            // rows. New native rows use the typed encoder's representation.
            return .array(try ai.order.compactMap { try overlay(ri.rows[$0], bi.rows[$0], ai.rows[$0], key: nil) })
        }
        return after
    }

    private static func mergeValue(_ base: Self?, _ local: Self?, _ remote: Self?, key: String?) throws -> Self? {
        if local == base { return remote }
        if remote == base || local == remote { return local }
        if let left = local?.fields, let right = remote?.fields, base == nil || base?.fields != nil {
            let previous = base?.fields ?? [:]
            var merged: [String: Self] = [:]
            for field in Set(previous.keys).union(left.keys).union(right.keys) {
                merged[field] = try mergeValue(previous[field], left[field], right[field], key: field)
            }
            return .object(merged)
        }
        if let l = local?.rows, let r = remote?.rows, base == nil || base?.rows != nil,
           let li = indexed(l, by: key), let ri = indexed(r, by: key), let bi = indexed(base?.rows ?? [], by: key) {
            let common = Set(bi.order).intersection(li.order).intersection(ri.order)
            let baseOrder = bi.order.filter { common.contains($0) }
            let localOrder = li.order.filter { common.contains($0) }
            let cloudOrder = ri.order.filter { common.contains($0) }
            if localOrder != baseOrder && cloudOrder != baseOrder && localOrder != cloudOrder {
                throw Conflict()
            }
            let order = localOrder != baseOrder && cloudOrder == baseOrder
                ? li.order + ri.order.filter { li.rows[$0] == nil }
                : ri.order + li.order.filter { ri.rows[$0] == nil }
            let merged = try order.compactMap { try mergeValue(bi.rows[$0], li.rows[$0], ri.rows[$0], key: nil) }
            // A goal's latest check-in is consumed via .last, not just a set.
            if key == "checkIns" {
                return .array(merged.enumerated().sorted { lhs, rhs in
                    let a = lhs.element.fields?["date"]?.string ?? ""
                    let b = rhs.element.fields?["date"]?.string ?? ""
                    return a == b ? lhs.offset < rhs.offset : a < b
                }.map(\.element))
            }
            return .array(merged)
        }
        throw Conflict()
    }

    /// A suspicious legacy contraction is blocked, not automatically filled
    /// by union (which would revive legitimate deletions). Narrow deletions
    /// still merge normally. A confirmed replacement can carry its exact parent.
    static func suspiciousContraction(previous: AppData, incoming: AppData) -> Bool {
        let p = [previous.goals.count, previous.habits.count, previous.bodyEntries.count,
                 previous.healthMetrics.count, previous.alcoholDrinks.count, previous.nicotineEntries.count,
                 previous.bloodTests.count, previous.bloodDonations.count, previous.saunaSessions.count,
                 previous.eyeExams.count, previous.epigeneticTests.count, previous.genomeVisitNotes.count]
        let i = [incoming.goals.count, incoming.habits.count, incoming.bodyEntries.count,
                 incoming.healthMetrics.count, incoming.alcoholDrinks.count, incoming.nicotineEntries.count,
                 incoming.bloodTests.count, incoming.bloodDonations.count, incoming.saunaSessions.count,
                 incoming.eyeExams.count, incoming.epigeneticTests.count, incoming.genomeVisitNotes.count]
        let erased = zip(p, i).filter { $0.0 >= 2 && $0.1 == 0 }.count
        let reductions = zip(p, i).reduce(0) { $0 + max(0, $1.0 - $1.1) }
        let total = p.reduce(0, +)
        return erased >= 2 || (total >= 3 && !incoming.hasUserData) ||
               (reductions >= 10 && reductions * 2 >= total) ||
               (previous.goals.count >= 3 && incoming.goals.isEmpty)
    }
}
