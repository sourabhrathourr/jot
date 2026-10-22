import AppKit
import SwiftUI

// A native rebuild of Raycast's menu popover (`menu.namespace` + `standard-list-item` +
// `shortcut` + `popover` CSS), used for the Action Panel (⌘K) and Browse Notes (⌘P).

struct MenuItem: Identifiable {
    var id: String
    var title: String
    var subtitle: String?
    var subtitleDot = false
    var icon: String?
    var shortcut: [String] = []
    var keywords: [String] = []
    var isDisabled = false
    var isDestructive = false
    var isChecked = false
    var submenu: MenuPage?
    var trailingButton: TrailingButton?
    var action: () -> Void = {}

    struct TrailingButton {
        var icon: String
        var tooltip: String
        var run: () -> Void
    }
}

struct MenuSection: Identifiable {
    var id: String
    var title: String?
    var items: [MenuItem]
}

struct MenuPage {
    enum RowStyle { case compact, multiline }

    var placeholder: String
    var headerTitle: String?
    var sections: [MenuSection]
    var rowStyle: RowStyle = .compact
    /// Raycast's action panel separates sections with hairlines; lists use headers.
    var separators = false
    var emptyText = "No Results"
    /// Raycast's ranked search: a query flattens the sections into one untitled list in
    /// score order (`preserveSectionsOnSearch: false`).
    var rankedSearch = false
}

@Observable
final class MenuModel {
    var page: MenuPage
    var query = ""
    var selectedID: String?
    /// Whether ↑ on the first row goes to the last (Raycast's `loop`).
    var wraps = true
    /// Where the pointer was at the last hover. Only an actual move selects a row, not a
    /// row appearing (or scrolling) under a still pointer.
    @ObservationIgnored var pointer = NSEvent.mouseLocation
    var onActivate: (MenuItem) -> Void = { _ in }

    init(page: MenuPage) { self.page = page }

    var filteredSections: [MenuSection] {
        let term = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return page.sections.filter { !$0.items.isEmpty } }
        if page.rankedSearch {
            let items = MenuSearch.rank(page.sections.flatMap(\.items), query: query)
            return items.isEmpty ? [] : [MenuSection(id: "results", items: items)]
        }
        return page.sections.compactMap { section in
            let items = section.items.filter { item in
                ([item.title, item.subtitle ?? ""] + item.keywords).contains { $0.lowercased().contains(term) }
            }
            return items.isEmpty ? nil : MenuSection(id: section.id, title: section.title, items: items)
        }
    }

    var selectableItems: [MenuItem] { filteredSections.flatMap(\.items).filter { !$0.isDisabled } }

    func selectFirst() { selectedID = selectableItems.first?.id }

    func move(_ delta: Int) {
        let items = selectableItems
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == selectedID } ?? -1
        selectedID = wraps
            ? items[(index + delta + items.count) % items.count].id
            : items[min(max(0, index + delta), items.count - 1)].id
    }

    /// ⌘↑ / ⌘↓: the first row of the previous or next section.
    func moveSection(_ delta: Int) {
        let sections = filteredSections.filter { $0.items.contains { !$0.isDisabled } }
        guard !sections.isEmpty else { return }
        let current = sections.firstIndex { $0.items.contains { $0.id == selectedID } } ?? 0
        let target = sections[min(max(0, current + delta), sections.count - 1)]
        selectedID = target.items.first { !$0.isDisabled }?.id
    }

    var selectedItem: MenuItem? { selectableItems.first { $0.id == selectedID } }

    /// The list's height for the current rows (Raycast's virtualised list), before any cap.
    var contentHeight: CGFloat {
        let rowHeight: CGFloat = page.rowStyle == .multiline ? 58 : 36
        var content: CGFloat = 16
        if page.headerTitle != nil { content += 12 + 12 + 8 - 8 }
        let sections = filteredSections
        for (index, section) in sections.enumerated() {
            if index > 0 && page.separators { content += 16.5 }
            if section.title != nil { content += (index == 0 && page.headerTitle == nil ? 4 : page.separators ? 4.5 : 12) + 12 + 8 }
            content += CGFloat(section.items.count) * rowHeight
        }
        if sections.isEmpty { content += 80 }
        return content
    }
}

/// Raycast's `PortalWindow : NSPanel`, the native window its popovers render in: a titled
/// panel with a transparent title bar whose theme frame takes the panel's corner radius
/// (`WindowCornerRadius`), so the system border and shadow follow the glass like the
/// notes window's. A borderless window instead gets a dark outline around its shadow.
class MenuPanel: NSPanel, CornerRadiusProviding {
    let glass = NSGlassEffectView()
    let customCornerRadius: CGFloat

    init(cornerRadius: CGFloat, size: NSSize, nonactivating: Bool = false) {
        customCornerRadius = cornerRadius
        var style: NSWindow.StyleMask = [.titled, .fullSizeContentView]
        if nonactivating { style.insert(.nonactivatingPanel) }
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        // Only the frame is wanted: hide the (invisible) title bar so it doesn't take the
        // clicks meant for the search field or the first rows.
        standardWindowButton(.closeButton)?.superview?.superview?.isHidden = true
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .modalPanel
        isReleasedWhenClosed = false
        animationBehavior = .none
        hidesOnDeactivate = false
        GlassRecipe.apply(to: glass, cornerRadius: cornerRadius)
        contentView = glass
        WindowCornerRadius.install(on: self)
        ScreenSharing.apply(to: self)
    }
}

/// The floating glass panel. `present` positions it over the notes window like Raycast.
final class CommandMenuPanel: MenuPanel, NSTextFieldDelegate {
    let model: MenuModel
    private let field = NSTextField()
    private var stack: [MenuPage] = []
    var onDismiss: () -> Void = {}
    /// Clicking elsewhere closes the panel, like Raycast's popover (off for screenshot runs).
    var dismissesOnResignKey = ProcessInfo.processInfo.environment["JOT_OPEN_MENU"] == nil

    static let width: CGFloat = 320
    static let maxHeight: CGFloat = 420
    static let searchHeight: CGFloat = 40

    init(page: MenuPage) {
        model = MenuModel(page: page)
        super.init(cornerRadius: 16, size: NSSize(width: Self.width, height: 300))

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Fonts.ui(size: 13)
        field.textColor = Theme.textPrimary
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false

        let separator = SeparatorView()
        separator.translatesAutoresizingMaskIntoConstraints = false

        let list = NSHostingView(rootView: MenuList(model: model))
        list.translatesAutoresizingMaskIntoConstraints = false
        // The panel is titled (for its frame), but the list shouldn't inset for a title bar.
        list.safeAreaRegions = []

        let container = NSView()
        container.addSubview(field)
        container.addSubview(separator)
        container.addSubview(list)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            field.centerYAnchor.constraint(equalTo: container.topAnchor, constant: Self.searchHeight / 2),
            separator.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.searchHeight),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 1),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -1),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
            list.topAnchor.constraint(equalTo: separator.bottomAnchor),
            list.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        glass.contentView = container

        model.onActivate = { [weak self] item in self?.activate(item) }
        setPage(page)
    }

    override var canBecomeKey: Bool { true }

    private func setPage(_ page: MenuPage) {
        model.page = page
        model.query = ""
        field.stringValue = ""
        field.placeholderAttributedString = NSAttributedString(string: page.placeholder, attributes: [
            .font: Fonts.ui(size: 13), .foregroundColor: Theme.textTertiary,
        ])
        model.selectFirst()
        resize()
    }

    /// Height follows the content (Raycast's virtualised list), capped like the web popover.
    private func resize() {
        let height = min(Self.maxHeight, Self.searchHeight + 0.5 + model.contentHeight)
        var frame = self.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        setFrame(frame, display: true)
    }

    func present(over parent: NSWindow) {
        let width = Self.width
        let x = parent.frame.midX - width / 2
        let top = parent.frame.maxY - 100
        setFrame(NSRect(x: x, y: top - frame.height, width: width, height: frame.height), display: false)
        resize()
        parent.addChildWindow(self, ordered: .above)
        alphaValue = 0.6
        glass.wantsLayer = true
        model.pointer = NSEvent.mouseLocation
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
        // `popover__open`: .25s cubic-bezier(.3,.7,0,1.26), opacity .6→1, scale .97→1.
        animateScale(from: 0.97, to: 1, duration: 0.25, timing: CAMediaTimingFunction(controlPoints: 0.3, 0.7, 0, 1.26))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard isVisible else { return }
        // `popover__close`: .15s ease-out, opacity → 0, scale → .97.
        animateScale(from: 1, to: 0.97, duration: 0.15, timing: CAMediaTimingFunction(name: .easeOut))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            parent?.removeChildWindow(self)
            orderOut(nil)
            onDismiss()
        }
    }

    private func animateScale(from: CGFloat, to: CGFloat, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        guard let layer = glass.layer else { return }
        let bounds = glass.bounds
        layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        layer.position = CGPoint(x: bounds.midX, y: bounds.maxY)
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = timing
        layer.add(animation, forKey: "popover")
    }

    override func resignKey() {
        super.resignKey()
        if dismissesOnResignKey { dismiss() }
    }

    private func activate(_ item: MenuItem) {
        guard !item.isDisabled else { return }
        if let submenu = item.submenu {
            stack.append(model.page)
            setPage(submenu)
            return
        }
        dismiss()
        item.action()
    }

    // MARK: Search field

    func controlTextDidChange(_ notification: Notification) {
        model.query = field.stringValue
        if model.selectedItem == nil { model.selectFirst() }
        resize()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): model.move(1)
        case #selector(NSResponder.moveUp(_:)): model.move(-1)
        case #selector(NSResponder.insertNewline(_:)):
            if let item = model.selectedItem { activate(item) }
        case #selector(NSResponder.cancelOperation(_:)):
            if !field.stringValue.isEmpty { field.stringValue = ""; controlTextDidChange(Notification(name: NSControl.textDidChangeNotification)) }
            else if let previous = stack.popLast() { setPage(previous) }
            else { dismiss() }
        case #selector(NSResponder.deleteBackward(_:)):
            if field.stringValue.isEmpty, let previous = stack.popLast() { setPage(previous); return true }
            return false
        default: return false
        }
        return true
    }
}

// MARK: - SwiftUI list

struct MenuList: View {
    @Bindable var model: MenuModel
    @State private var position = ScrollPosition()
    @State private var geometry = ListGeometry()

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let header = model.page.headerTitle {
                        Text(header)
                            .font(Font(Fonts.ui(size: 13) as CTFont))
                            .foregroundStyle(Color(nsColor: Theme.textSecondary))
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                    }
                    let sections = model.filteredSections
                    if sections.isEmpty {
                        Text(model.page.emptyText)
                            .font(Font(Fonts.ui(size: 13) as CTFont))
                            .foregroundStyle(Color(nsColor: Theme.textTertiary))
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        if index > 0, model.page.separators {
                            Separator()
                        }
                        if let title = section.title {
                            // `List.SectionHeader`: `small-text`, secondary. After a separator the
                            // gap is `wr`'s section end (8) + separator (1) + section start (12).
                            Text(title)
                                .font(Font(Fonts.ui(size: 11) as CTFont))
                                .foregroundStyle(Color(nsColor: Theme.textSecondary))
                                .frame(height: 12, alignment: .bottomLeading)
                                .padding(.horizontal, 8)
                                .padding(.top, index == 0 && model.page.headerTitle == nil ? 4 : model.page.separators ? 4.5 : 12)
                                .padding(.bottom, 8)
                        }
                        ForEach(section.items) { item in
                            MenuRow(item: item, style: model.page.rowStyle, isSelected: model.selectedID == item.id)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ListGeometry.space)) } action: { frame in
                                    geometry.rows[item.id] = frame
                                }
                                .onHover { inside in
                                    let location = NSEvent.mouseLocation
                                    guard inside, !item.isDisabled, location != model.pointer else { return }
                                    model.pointer = location
                                    model.selectedID = item.id
                                }
                                .onTapGesture { model.onActivate(item) }
                        }
                    }
                }
                .padding(8)
                .coordinateSpace(.named(ListGeometry.space))
        }
        .scrollIndicators(.automatic)
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, visible in
            geometry.visible = visible
        }
        .onChange(of: model.selectedID) { _, id in
            guard let id, let y = geometry.offset(revealing: id, isFirst: id == model.selectableItems.first?.id) else { return }
            position.scrollTo(y: y)
        }
    }
}

/// Where the rows are and what's visible, kept out of SwiftUI state so scrolling doesn't
/// re-render the list.
private final class ListGeometry {
    static let space = "menu-list"
    var rows: [String: CGRect] = [:]
    var visible: CGRect = .zero

    /// Raycast's list scrolling: the selected row keeps 8pt from either edge
    /// (`scrollPaddingStart/End`), and the first item scrolls back to the top. `nil` when
    /// the row is already in view.
    func offset(revealing id: String, isFirst: Bool) -> CGFloat? {
        guard let row = rows[id], visible.height > 0 else { return nil }
        let padding: CGFloat = 8
        var y = visible.minY
        if isFirst { y = 0 }
        else if row.minY - padding < visible.minY { y = row.minY - padding }
        else if row.maxY + padding > visible.maxY { y = row.maxY + padding - visible.height }
        return abs(y - visible.minY) > 0.5 ? max(0, y) : nil
    }
}

/// `.list__separator`: a hairline in `--color-border-separator`, faded at both ends.
private struct Separator: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: Theme.separator))
            .frame(height: 0.5)
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                .init(color: .black, location: 0.9), .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing))
            .padding(.horizontal, 1)
            .padding(.vertical, 8)
    }
}

/// `List.Item` + `standard-list-item`: radius 10, `--selection-10` when selected,
/// 16pt icon in `--color-text-primary`, 8pt gap, `text` title, keycap accessories.
private struct MenuRow: View {
    let item: MenuItem
    let style: MenuPage.RowStyle
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let icon = item.icon, let image = RaycastIcon.image(icon, size: 16) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .foregroundStyle(Color(nsColor: item.isDestructive ? Theme.red : Theme.textPrimary))
                    .frame(width: 16, height: 16)
            }
            if style == .multiline {
                VStack(alignment: .leading, spacing: 4) {
                    title
                    HStack(spacing: 4) {
                        if item.subtitleDot {
                            Circle().fill(Color(nsColor: Theme.accent)).frame(width: 5, height: 5)
                        }
                        Text(item.subtitle ?? "")
                            .font(Font(Fonts.ui(size: 13) as CTFont))
                            .foregroundStyle(Color(nsColor: Theme.textSecondary))
                            .lineLimit(1)
                    }
                }
            } else {
                title
            }
            Spacer(minLength: 8)
            if item.isChecked, let check = RaycastIcon.image("checkmark", size: 14) {
                Image(nsImage: check).renderingMode(.template).foregroundStyle(Color(nsColor: Theme.textPrimary))
            }
            if !item.shortcut.isEmpty {
                HStack(spacing: 2) {
                    ForEach(Array(item.shortcut.enumerated()), id: \.offset) { _, key in Keycap(key: key) }
                }
            }
            if let button = item.trailingButton, isSelected {
                TrailingIconButton(button: button)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: style == .multiline ? 58 : 36)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: isSelected ? Theme.fg(0.1) : .clear))
        )
        .opacity(item.isDisabled ? 0.3 : 1)
        .contentShape(Rectangle())
    }

    private var title: some View {
        Text(item.title)
            .font(Font(Fonts.ui(size: 13, contextualAlternates: false) as CTFont))
            .foregroundStyle(Color(nsColor: item.isDestructive ? Theme.red : Theme.textPrimary))
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// `.shortcut__kbd[data-size=small][data-variant=default]`: 18pt, 10px text in
/// `--color-text-secondary`, 1px inset `--color-border-token` (fg 20%).
private struct Keycap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(Font(Fonts.ui(size: 10) as CTFont))
            .foregroundStyle(Color(nsColor: Theme.textSecondary))
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 18, maxHeight: 18)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: Theme.fg(0.2)), lineWidth: 1))
    }
}

private struct TrailingIconButton: View {
    let button: MenuItem.TrailingButton
    @State private var isHovered = false

    var body: some View {
        if let image = RaycastIcon.image(button.icon, size: 16) {
            Image(nsImage: image)
                .renderingMode(.template)
                .foregroundStyle(Color(nsColor: Theme.textSecondary))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color(nsColor: isHovered ? Theme.fg(0.1) : .clear)))
                .onHover { isHovered = $0 }
                .onTapGesture { button.run() }
                .help(button.tooltip)
        }
    }
}
