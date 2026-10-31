/// Shared order calculations for the two PDF editors. Item identity is kept
/// separate from its current position, including when a selection has gaps.
enum PDFReordering {
    static func positionRange<Element>(in items: [Element], selection: Set<Int>,
                                       id: KeyPath<Element, Int>, anchor: Int) -> ClosedRange<Int>? {
        let moving = items.filter { selection.contains($0[keyPath: id]) }
        guard let offset = moving.firstIndex(where: { $0[keyPath: id] == anchor }) else { return nil }
        return (offset + 1)...(items.count - moving.count + offset + 1)
    }

    /// The entered number is the anchor item's final, one-based position.
    /// Other selected items move with it in their existing relative order.
    static func move<Element>(_ items: [Element], selection: Set<Int>,
                              id: KeyPath<Element, Int>, anchor: Int, to position: Int) -> [Element]? {
        guard let range = positionRange(in: items, selection: selection, id: id, anchor: anchor),
              range.contains(position) else { return nil }
        let moving = items.filter { selection.contains($0[keyPath: id]) }
        guard let offset = moving.firstIndex(where: { $0[keyPath: id] == anchor }) else { return nil }
        var remaining = items.filter { !selection.contains($0[keyPath: id]) }
        remaining.insert(contentsOf: moving, at: position - 1 - offset)
        return remaining
    }

    /// A drop targets a boundary in the original list, not an unselected item.
    /// This also permits dropping beside an item inside a disjoint selection.
    static func drop<Element>(_ items: [Element], selection: Set<Int>,
                              id: KeyPath<Element, Int>, at boundary: Int) -> [Element]? {
        guard !selection.isEmpty, (0...items.count).contains(boundary) else { return nil }
        let moving = items.filter { selection.contains($0[keyPath: id]) }
        guard !moving.isEmpty else { return nil }
        let insertion = items.prefix(boundary).filter { !selection.contains($0[keyPath: id]) }.count
        var remaining = items.filter { !selection.contains($0[keyPath: id]) }
        remaining.insert(contentsOf: moving, at: insertion)
        return remaining
    }
}
