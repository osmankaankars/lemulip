#if os(macOS)
import AppKit

/// Reads public accessibility getters on the actual objects returned by this
/// test's own window. Formal protocol conformance is diagnostic, not admission.
@MainActor
enum NativeAccessibilityReview {
    struct Node {
        // Retain visited objects so ObjectIdentifier cannot be reused mid-walk.
        let object: AnyObject
        let role: NSAccessibility.Role?
        let label: String?
        let title: String?
        let help: String?
        let value: Any?
        let valueDescription: String?
        let enabled: Bool?
        let frame: NSRect?
        let identifier: String?
        let diagnostics: [String: Any]
    }

    struct Walk {
        let nodes: [Node]
        let truncated: Bool
        let remainingQueued: Int

        func first(role: NSAccessibility.Role, label: String) -> Node? {
            nodes.first { $0.role == role && ($0.label == label || $0.title == label) }
        }
    }

    static func walk(_ view: NSView) -> Walk {
        var pending: [AnyObject] = [view]
        if let window = view.window { pending.append(window) }
        var visited = Set<ObjectIdentifier>()
        var nodes: [Node] = []
        while nodes.count < 512, let object = pending.popLast() {
            guard visited.insert(ObjectIdentifier(object)).inserted else { continue }
            let (node, children) = inspect(object)
            nodes.append(node)
            pending.append(contentsOf: children)
            if let native = object as? NSView { pending.append(contentsOf: native.subviews) }
        }
        return Walk(nodes: nodes, truncated: !pending.isEmpty, remainingQueued: pending.count)
    }

    private static func inspect(_ object: AnyObject) -> (Node, [AnyObject]) {
        // Explicit result types select the public Objective-C getter signature.
        // Missing getters stay nil; no default name/value/enabled state is invented.
        let role: NSAccessibility.Role? = object.accessibilityRole?()
        let label: String? = object.accessibilityLabel?()
        let title: String? = object.accessibilityTitle?()
        let help: String? = object.accessibilityHelp?()
        let value: Any? = object.accessibilityValue?()
        let valueDescription: String? = object.accessibilityValueDescription?()
        let enabled: Bool? = object.isAccessibilityEnabled?()
        let frame: NSRect? = object.accessibilityFrame?()
        let identifier: String? = object.accessibilityIdentifier?()
        let ordinaryChildren: [Any]? = object.accessibilityChildren?()
        let navigation = navigationChildren(of: object)

        var support: [String: Any] = [:]
        let responder = object as? NSObjectProtocol
        for name in ["accessibilityRole", "accessibilityLabel", "accessibilityTitle", "accessibilityHelp", "accessibilityValue",
                     "accessibilityValueDescription", "isAccessibilityEnabled", "accessibilityFrame",
                     "accessibilityIdentifier", "accessibilityChildren", "accessibilityChildrenInNavigationOrder"] {
            if let responder { support[name] = responder.responds(to: NSSelectorFromString(name)) }
            else { support[name] = NSNull() }
        }
        var diagnostics: [String: Any] = [:]
        diagnostics["class"] = String(reflecting: type(of: object))
        diagnostics["conformsToAccessibilityProtocol"] = object is NSAccessibilityProtocol
        diagnostics["conformsToAccessibilityElementProtocol"] = object is NSAccessibilityElementProtocol
        diagnostics["conformsToAccessibilitySlider"] = object is NSAccessibilitySlider
        diagnostics["selectorSupport"] = support
        diagnostics["role"] = role?.rawValue ?? "missing"
        diagnostics["identifier"] = identifier ?? "missing"
        diagnostics["label"] = label ?? "missing"
        diagnostics["title"] = title ?? "missing"
        diagnostics["help"] = help ?? "missing"
        diagnostics["value"] = value.map { String(describing: $0) } ?? "missing"
        diagnostics["valueDescription"] = valueDescription ?? "missing"
        if let enabled { diagnostics["enabled"] = enabled }
        else { diagnostics["enabled"] = NSNull() }
        if let frame { diagnostics["screenFrame"] = [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)] }
        else { diagnostics["screenFrame"] = NSNull() }
        if let ordinaryChildren { diagnostics["childCount"] = ordinaryChildren.count }
        else { diagnostics["childCount"] = NSNull() }
        if let children = navigation.children { diagnostics["navigationChildCount"] = children.count }
        else { diagnostics["navigationChildCount"] = NSNull() }
        diagnostics["navigationGetterStatus"] = navigation.status
        diagnostics["navigationResultClass"] = navigation.resultClass ?? "none"
        let node = Node(object: object, role: role, label: label, title: title, help: help, value: value,
                        valueDescription: valueDescription, enabled: enabled, frame: frame,
                        identifier: identifier, diagnostics: diagnostics)
        let children = (ordinaryChildren ?? []).map { $0 as AnyObject } + (navigation.children ?? [])
        return (node, children)
    }

    private struct Navigation {
        let children: [AnyObject]?
        let status: String
        let resultClass: String?
    }

    private static func navigationChildren(of object: AnyObject) -> Navigation {
        let selector = NSSelectorFromString("accessibilityChildrenInNavigationOrder")
        guard let responder = object as? NSObjectProtocol, responder.responds(to: selector) else {
            return Navigation(children: nil, status: "unsupported", resultClass: nil)
        }
        guard let result = responder.perform(selector)?.takeUnretainedValue() else {
            return Navigation(children: nil, status: "nil", resultClass: nil)
        }
        let resultClass = String(reflecting: type(of: result))
        guard let array = result as? NSArray else {
            return Navigation(children: nil, status: "unexpected-non-array", resultClass: resultClass)
        }
        // The documented getter returns an object. Keep its NSArray elements
        // untyped: the SDK's [NSAccessibilityElementProtocol] bridge traps on
        // real window proxies observed in CI. No struct/scalar uses perform.
        var children: [AnyObject] = []
        for child in array { children.append(child as AnyObject) }
        return Navigation(children: children, status: "returned-nsarray", resultClass: resultClass)
    }
}
#endif
