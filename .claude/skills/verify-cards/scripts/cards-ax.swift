// cards-ax: drives one Cards process through Accessibility, by pid, so it never touches another
// Cards instance (the owner's Xcode run uses the same bundle id). Built by `cards-verify` on first use.
//
//   cards-ax tree PID                    every window and element: index, role, name, value, frame
//   cards-ax press PID NAME [WINDOW]     AXPress the first button whose title, description or help is NAME
//   cards-ax text PID [WINDOW]           the text of each text area (one line per area, JSON-escaped)
//   cards-ax click PID WINDOW FX FY      activate Cards, then a real mouse click at a fraction of the window
//   cards-ax focus PID WINDOW            click the window's text area (puts the caret in that card)
//   cards-ax type PID TEXT               key events to the pid; "\n" is Return
//   cards-ax key PID COMBO               one key, e.g. cmd+b, return, escape, delete, shift+tab
//                                        (a cmd combo first activates Cards: menu shortcuts need it)
//   cards-ax scroll PID WINDOW DX DY     one scroll-wheel event over the window (DX<0 = next card)
//   cards-ax drag PID WINDOW FX FY DX DY press at a fraction of the window and drag by DX,DY points
//   cards-ax windows PID                 CGWindowID and frame of each on-screen window, for screencapture -l
//   cards-ax act PID LABEL ACTION [WINDOW]  run an accessibility action (AXPress, or a custom one such
//                                        as "Move up") on the first element whose title, description or
//                                        help starts with LABEL; `tree` lists custom actions as actions=[…]
//   cards-ax section PID TITLE [WINDOW]  AXPress the Settings sidebar row named exactly TITLE (a cell of the table
//                                        "Settings sections"), which shows that section's pane
//   cards-ax where PID LABEL             screen x y of the center of the first element whose name starts with LABEL
//   cards-ax mouse PID down|drag|up|move X Y  one raw mouse event at screen point X,Y (no activation)
//   cards-ax dragat PID X Y DX DY        press at screen point X,Y, drag by DX,DY points, release
//   cards-ax listen PID SECONDS          print each VoiceOver announcement the app posts for SECONDS
//
//   cards-ax idle REFFILE LABEL          no PID: HID idle seconds (hidSystemState), and the time since REFFILE's mtime
//                                        (the last event this helper posted, or the launch); flags an event after it
//
// Every event this helper posts touches the file named by $CARDS_AX_STAMP, if set.
//
// WINDOW is `stack`, `card=<title>` (the card's first line), or an index `tree` prints (w0, w1;
// indices follow the z-order and change after any click, so prefer the names). Frames are screen
// points with the origin top-left, the same space screencapture -R uses.
import AppKit
import ApplicationServices

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("cards-ax: \(message)\n".utf8))
    exit(1)
}

func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
    return value as? T
}

func frame(_ el: AXUIElement) -> CGRect? {
    guard let p: AXValue = attr(el, kAXPositionAttribute), let s: AXValue = attr(el, kAXSizeAttribute) else { return nil }
    var point = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(p, .cgPoint, &point)
    AXValueGetValue(s, .cgSize, &size)
    return CGRect(origin: point, size: size)
}

func children(_ el: AXUIElement) -> [AXUIElement] { attr(el, kAXChildrenAttribute) ?? [] }

func actionNames(_ el: AXUIElement) -> [String] {
    var list: CFArray?
    guard AXUIElementCopyActionNames(el, &list) == .success else { return [] }
    return list as? [String] ?? []
}

/// A custom action is reported as "Name:Move up\nTarget:0x0\nSelector:(null)"; built-in ones keep their AX name.
func shortAction(_ raw: String) -> String {
    raw.hasPrefix("Name:") ? String(raw.dropFirst(5).prefix { $0 != "\n" }) : raw
}

func names(_ el: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].compactMap { attr(el, $0) as String? }.filter { !$0.isEmpty }
}

/// The app's windows. AX builds an app's tree lazily, so the first read after launch can be
/// empty; retry briefly.
func windows(_ app: AXUIElement) -> [AXUIElement] {
    for _ in 0..<20 {
        let list: [AXUIElement] = attr(app, kAXWindowsAttribute) ?? []
        if !list.isEmpty, list.contains(where: { !children($0).isEmpty }) { return list }
        usleep(150_000)
    }
    return attr(app, kAXWindowsAttribute) ?? []
}

/// `stack` (the window with the New button), `card=<first line>` (a popped card whose text starts
/// with it), or an index from `tree`. Indices follow the z-order and change, so prefer the names.
func window(_ app: AXUIElement, _ arg: String) -> AXUIElement {
    let list = windows(app)
    func has(_ w: AXUIElement, _ match: (AXUIElement) -> Bool) -> Bool {
        var found = false
        walk(w) { el, _ in if !found, match(el) { found = true } }
        return found
    }
    func isStack(_ w: AXUIElement) -> Bool { has(w) { names($0).contains("New") } }
    if arg == "stack", let w = list.first(where: isStack) { return w }
    if arg.hasPrefix("card=") {
        let title = String(arg.dropFirst(5))
        if let w = list.first(where: { w in !isStack(w) && has(w) { el in
            (attr(el, kAXRoleAttribute) as String?) == "AXTextArea"
                && ((attr(el, kAXValueAttribute) as String?) ?? "").hasPrefix(title) } }) { return w }
        // A collapsed card has no text area; its header is a static text.
        if let w = list.first(where: { w in !isStack(w) && has(w) { (attr($0, kAXValueAttribute) as String?) == title } }) { return w }
    }
    if let i = Int(arg.hasPrefix("w") ? String(arg.dropFirst()) : arg), list.indices.contains(i) { return list[i] }
    fail("no window \(arg); the app has \(list.count) (run `tree`)")
}

func walk(_ el: AXUIElement, _ visit: (AXUIElement, Int) -> Void, depth: Int = 0) {
    visit(el, depth)
    for child in children(el) { walk(child, visit, depth: depth + 1) }
}

func describe(_ r: CGRect?) -> String {
    guard let r else { return "" }
    return "@\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))"
}

func json(_ s: String) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed), encoding: .utf8)!
}

func activate(_ pid: pid_t) {
    NSRunningApplication(processIdentifier: pid)?.activate()
    usleep(250_000)
}

func stampPostedEvent() {
    guard let path = ProcessInfo.processInfo.environment["CARDS_AX_STAMP"] else { return }
    let fm = FileManager.default
    if !fm.fileExists(atPath: path) { fm.createFile(atPath: path, contents: nil) }
    try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: path)
}

func mouse(_ type: CGEventType, _ at: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: at, mouseButton: .left)?.post(tap: .cghidEventTap)
    stampPostedEvent()
    usleep(40_000)
}

func click(_ at: CGPoint) {
    mouse(.mouseMoved, at)
    mouse(.leftMouseDown, at)
    mouse(.leftMouseUp, at)
    usleep(200_000)
}

let keyCodes: [String: CGKeyCode] = ["return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
                                     "left": 123, "right": 124, "down": 125, "up": 126,
                                     "a": 0, "b": 11, "c": 8, "h": 4, "i": 34, "k": 40, "q": 12, "v": 9, "w": 13, "x": 7, "z": 6, ",": 43]

func post(_ pid: pid_t, key: CGKeyCode, flags: CGEventFlags = [], unicode: String? = nil) {
    for down in [true, false] {
        guard let e = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else { continue }
        e.flags = flags
        if let unicode {
            let utf16 = Array(unicode.utf16)
            e.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        }
        e.postToPid(pid)
        stampPostedEvent()
        usleep(12_000)
    }
}

/// Every event the helper posts, keys included, resets the HID idle counter, so idle alone cannot
/// tell the helper from the owner. The counter moves in half-second steps and never reads less than
/// the time since the helper's last event, so a smaller reading means someone else's event came later.
func idleReport(reference: String?, label: String) {
    let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
    var line = String(format: "hid idle %.1fs", idle)
    if let reference, let touched = (try? FileManager.default.attributesOfItem(atPath: reference))?[.modificationDate] as? Date {
        let quiet = Date().timeIntervalSince(touched)
        line += String(format: "; %.1fs since %@", quiet, label)
        if idle + 0.5 < quiet { line += "; INPUT after the \(label)" }
    }
    print(line)
}

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "idle" {
    idleReport(reference: args.count > 1 ? args[1] : nil, label: args.count > 2 ? args[2] : "reference")
    exit(0)
}
guard args.count >= 2, let pid = pid_t(args[1]) else { fail("usage: cards-ax COMMAND PID ... (see the header of cards-ax.swift)") }
guard AXIsProcessTrusted() else { fail("this terminal has no Accessibility permission (System Settings › Privacy & Security › Accessibility)") }
guard NSRunningApplication(processIdentifier: pid) != nil else { fail("no running app with pid \(pid)") }
let app = AXUIElementCreateApplication(pid)

switch args[0] {
case "tree":
    for (i, w) in windows(app).enumerated() {
        print("w\(i) \(describe(frame(w)))")
        walk(w, { el, depth in
            guard depth > 0 else { return }
            let role: String = attr(el, kAXRoleAttribute) ?? "?"
            var line = String(repeating: "  ", count: depth) + role
            let n = names(el)
            if !n.isEmpty { line += " " + n.map(json).joined(separator: " | ") }
            if let v: String = attr(el, kAXValueAttribute), !v.isEmpty {
                line += " value=" + json(String(v.prefix(120)))
            }
            if let enabled: Bool = attr(el, kAXEnabledAttribute), !enabled { line += " [disabled]" }
            if let focused: Bool = attr(el, kAXFocusedAttribute), focused { line += " [focused]" }
            if let selected: Bool = attr(el, kAXSelectedAttribute), selected { line += " [selected]" }
            let custom = actionNames(el).filter { $0.hasPrefix("Name:") }.map(shortAction)
            if !custom.isEmpty { line += " actions=[" + custom.joined(separator: ", ") + "]" }
            print(line + " " + describe(frame(el)))
        })
    }

case "press":
    guard args.count >= 3 else { fail("press PID NAME [WINDOW]") }
    let scope = args.count >= 4 ? [window(app, args[3])] : windows(app)
    var target: AXUIElement?
    for w in scope where target == nil {
        walk(w) { el, _ in
            guard target == nil, (attr(el, kAXRoleAttribute) as String?) == "AXButton", names(el).contains(args[2]) else { return }
            target = el
        }
    }
    guard let target else { fail("no button named \(json(args[2])) (run `tree`)") }
    if let enabled: Bool = attr(target, kAXEnabledAttribute), !enabled { fail("button \(json(args[2])) is disabled") }
    let result = AXUIElementPerformAction(target, kAXPressAction as CFString)
    guard result == .success else { fail("AXPress failed: \(result.rawValue)") }
    usleep(300_000)

case "text":
    let scope = args.count >= 3 ? [window(app, args[2])] : windows(app)
    for w in scope {
        walk(w) { el, _ in
            guard (attr(el, kAXRoleAttribute) as String?) == "AXTextArea" else { return }
            print(json(attr(el, kAXValueAttribute) ?? ""))
        }
    }

case "click":
    guard args.count == 5, let fx = Double(args[3]), let fy = Double(args[4]),
          let f = frame(window(app, args[2])) else { fail("click PID WINDOW FX FY") }
    activate(pid)
    click(CGPoint(x: f.minX + f.width * fx, y: f.minY + f.height * fy))

case "focus":
    guard args.count == 3 else { fail("focus PID WINDOW") }
    var area: AXUIElement?
    walk(window(app, args[2])) { el, _ in
        if area == nil, (attr(el, kAXRoleAttribute) as String?) == "AXTextArea" { area = el }
    }
    guard let area, let f = frame(area) else { fail("window \(args[2]) has no text area (collapsed card?)") }
    activate(pid)
    // Low in the text so the click lands in the body, never on a header drag.
    click(CGPoint(x: f.midX, y: f.minY + min(f.height - 4, max(30, f.height * 0.6))))

case "type":
    guard args.count == 3 else { fail("type PID TEXT") }
    for ch in args[2].replacingOccurrences(of: "\\n", with: "\n") {
        if ch == "\n" { post(pid, key: 36) } else { post(pid, key: 0, unicode: String(ch)) }
    }
    usleep(200_000)

case "key":
    guard args.count == 3 else { fail("key PID COMBO") }
    var flags: CGEventFlags = []
    var name = ""
    for part in args[2].lowercased().split(separator: "+") {
        switch part {
        case "cmd": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "opt", "alt": flags.insert(.maskAlternate)
        case "ctrl": flags.insert(.maskControl)
        default: name = String(part)
        }
    }
    guard let code = keyCodes[name] else { fail("unknown key \(name); known: \(keyCodes.keys.sorted().joined(separator: " "))") }
    if flags.contains(.maskCommand) { activate(pid) }
    post(pid, key: code, flags: flags)
    usleep(200_000)

case "scroll":
    guard args.count == 5, let dx = Int32(args[3]), let dy = Int32(args[4]),
          let f = frame(window(app, args[2])) else { fail("scroll PID WINDOW DX DY") }
    activate(pid)
    let at = CGPoint(x: f.midX, y: f.midY)
    mouse(.mouseMoved, at)
    let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
    e?.location = at
    e?.post(tap: .cghidEventTap)
    stampPostedEvent()
    usleep(400_000)

case "drag":
    guard args.count == 7, let fx = Double(args[3]), let fy = Double(args[4]), let dx = Double(args[5]), let dy = Double(args[6]),
          let f = frame(window(app, args[2])) else { fail("drag PID WINDOW FX FY DX DY") }
    activate(pid)
    let start = CGPoint(x: f.minX + f.width * fx, y: f.minY + f.height * fy)
    mouse(.mouseMoved, start)
    mouse(.leftMouseDown, start)
    let steps = 20
    for s in 1...steps {
        let t = Double(s) / Double(steps)
        mouse(.leftMouseDragged, CGPoint(x: start.x + dx * t, y: start.y + dy * t))
    }
    mouse(.leftMouseUp, CGPoint(x: start.x + dx, y: start.y + dy))
    usleep(600_000)

case "windows":
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in info where (w[kCGWindowOwnerPID as String] as? pid_t) == pid {
        guard let id = w[kCGWindowNumber as String] as? Int,
              let b = w[kCGWindowBounds as String] as? [String: Double], (w[kCGWindowLayer as String] as? Int) == 0 else { continue }
        print("\(id) @\(Int(b["X"]!)),\(Int(b["Y"]!)) \(Int(b["Width"]!))x\(Int(b["Height"]!))")
    }

case "act":
    guard args.count >= 4 else { fail("act PID LABEL ACTION [WINDOW]") }
    let scope = args.count >= 5 ? [window(app, args[4])] : windows(app)
    var target: (element: AXUIElement, action: String)?
    for w in scope where target == nil {
        walk(w) { el, _ in
            guard target == nil, names(el).contains(where: { $0.hasPrefix(args[2]) }),
                  let raw = actionNames(el).first(where: { shortAction($0) == args[3] }) else { return }
            target = (el, raw)
        }
    }
    guard let target else { fail("no element named \(json(args[2])) with the action \(json(args[3])) (run `tree`)") }
    let result = AXUIElementPerformAction(target.element, target.action as CFString)
    guard result == .success else { fail("action failed: \(result.rawValue)") }
    usleep(300_000)

case "section":
    guard args.count >= 3 else { fail("section PID TITLE [WINDOW]") }
    let scope = args.count >= 4 ? [window(app, args[3])] : windows(app)
    func role(_ el: AXUIElement) -> String? { attr(el, kAXRoleAttribute) }
    var target: AXUIElement?
    for w in scope where target == nil {
        walk(w) { table, _ in
            guard target == nil, role(table) == "AXTable", names(table).contains("Settings sections") else { return }
            walk(table) { cell, _ in
                if target == nil, role(cell) == "AXCell", names(cell).contains(args[2]) { target = cell }
            }
        }
    }
    guard let target else { fail("no Settings section named \(json(args[2])); open Settings first (run `tree`)") }
    // AppKit runs a table cell's press and still answers -25205, so the proof is the row it selected.
    let result = AXUIElementPerformAction(target, kAXPressAction as CFString)
    for _ in 0..<10 where (attr(target, kAXSelectedAttribute) as Bool?) != true { usleep(100_000) }
    guard (attr(target, kAXSelectedAttribute) as Bool?) == true else {
        fail("pressing section \(json(args[2])) did not select it (AXPress answered \(result.rawValue))")
    }
    usleep(300_000)

case "where":
    guard args.count == 3 else { fail("where PID LABEL") }
    var found: CGRect?
    for w in windows(app) where found == nil {
        walk(w) { el, _ in
            if found == nil, names(el).contains(where: { $0.hasPrefix(args[2]) }) { found = frame(el) }
        }
    }
    guard let found else { fail("no element named \(json(args[2])) (run `tree`)") }
    print("\(Int(found.midX)) \(Int(found.midY))")

case "mouse":
    guard args.count == 5, let x = Double(args[3]), let y = Double(args[4]) else { fail("mouse PID down|drag|up|move X Y") }
    let types: [String: CGEventType] = ["down": .leftMouseDown, "drag": .leftMouseDragged, "up": .leftMouseUp, "move": .mouseMoved]
    guard let type = types[args[2]] else { fail("unknown mouse event \(args[2])") }
    mouse(type, CGPoint(x: x, y: y))

case "dragat":
    guard args.count == 6, let x = Double(args[2]), let y = Double(args[3]), let dx = Double(args[4]), let dy = Double(args[5]) else {
        fail("dragat PID X Y DX DY")
    }
    let start = CGPoint(x: x, y: y)
    mouse(.mouseMoved, start)
    mouse(.leftMouseDown, start)
    let steps = 30
    for s in 1...steps {
        let t = Double(s) / Double(steps)
        mouse(.leftMouseDragged, CGPoint(x: start.x + dx * t, y: start.y + dy * t))
        usleep(15_000)
    }
    usleep(150_000)
    mouse(.leftMouseUp, CGPoint(x: start.x + dx, y: start.y + dy))
    usleep(600_000)

case "listen":
    guard args.count == 3, let seconds = Double(args[2]) else { fail("listen PID SECONDS") }
    var observer: AXObserver?
    let callback: AXObserverCallbackWithInfo = { _, _, notification, info, _ in
        let text = (info as NSDictionary)["AXAnnouncementKey"] as? String ?? "\(info)"
        print("\(notification as String): \(json(text))")
        fflush(stdout)
    }
    guard AXObserverCreateWithInfoCallback(pid, callback, &observer) == .success, let observer else { fail("cannot observe pid \(pid)") }
    // An announcement is posted on one element (the arranger's table), and an observer on the app does
    // not see it, so watch every element that exists now: open the popover before listening.
    for w in windows(app) {
        walk(w) { el, _ in _ = AXObserverAddNotification(observer, el, "AXAnnouncementRequested" as CFString, nil) }
    }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
    CFRunLoopRunInMode(.defaultMode, seconds, false)

default:
    fail("unknown command \(args[0])")
}
