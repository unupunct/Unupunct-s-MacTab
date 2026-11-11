// SPDX-License-Identifier: GPL-3.0-or-later
// Monterey port: SwiftUI shims for APIs that macOS 12 does not have.
//
// Types that exist in newer SDKs (ViewThatFits, Grid, LabeledContent …) are
// redeclared here under the same name. Declarations in the app's own module
// shadow the SDK's, so existing call sites compile unchanged and pick up the
// fallbacks. Modifiers use a `…Compat` name and are applied by the port.
//
// Fallback quality is documented in MONTEREY-COMPATIBILITY.md.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ViewThatFits

/// macOS 13+: the real `ViewThatFits`. macOS 12: the LAST alternative, which
/// by convention is the most compact one, so nothing overflows.
struct ViewThatFits<Content: View>: View {
    private let axes: Axis.Set
    private let content: Content

    init(in axes: Axis.Set = [.horizontal, .vertical], @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.content = content()
    }

    var body: some View {
        if #available(macOS 13.0, *) {
            SwiftUI.ViewThatFits(in: axes) { content }
        } else {
            _VariadicView.Tree(LastChildRoot()) { content }
        }
    }
}

private struct LastChildRoot: _VariadicView_UnaryViewRoot {
    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        if let last = children.last { last }
    }
}

// MARK: - Grid / GridRow

private struct GridHorizontalSpacingKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

private extension EnvironmentValues {
    var compatGridHorizontalSpacing: CGFloat? {
        get { self[GridHorizontalSpacingKey.self] }
        set { self[GridHorizontalSpacingKey.self] = newValue }
    }
}

/// macOS 12 stand-in: rows stacked vertically. Columns are not aligned across
/// rows (documented limitation).
struct Grid<Content: View>: View {
    private let alignment: Alignment
    private let horizontalSpacing: CGFloat?
    private let verticalSpacing: CGFloat?
    private let content: Content

    init(alignment: Alignment = .center, horizontalSpacing: CGFloat? = nil,
         verticalSpacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: alignment.horizontal, spacing: verticalSpacing) { content }
            .environment(\.compatGridHorizontalSpacing, horizontalSpacing)
    }
}

struct GridRow<Content: View>: View {
    @Environment(\.compatGridHorizontalSpacing) private var spacing
    private let alignment: VerticalAlignment
    private let content: Content

    init(alignment: VerticalAlignment? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment ?? .center
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: spacing) { content }
    }
}

extension View {
    /// No column alignment without a real grid.
    func gridColumnAlignment(_ guide: HorizontalAlignment) -> some View { self }
}

// MARK: - LabeledContent

struct LabeledContent<Label: View, Content: View>: View {
    private let label: Label
    private let content: Content

    init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.content = content()
    }

    var body: some View {
        if #available(macOS 13.0, *) {
            SwiftUI.LabeledContent { content } label: { label }
        } else {
            HStack(alignment: .firstTextBaseline) {
                label
                Spacer(minLength: 8)
                content
            }
        }
    }
}

extension LabeledContent where Label == Text {
    init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.init(content: content, label: { Text(title) })
    }
}

// MARK: - ContentUnavailableView

struct ContentUnavailableView: View {
    private let title: String
    private let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 30)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding()
    }
}

// MARK: - UnevenRoundedRectangle

struct RectangleCornerRadii: Equatable {
    var topLeading: CGFloat
    var bottomLeading: CGFloat
    var bottomTrailing: CGFloat
    var topTrailing: CGFloat

    init(topLeading: CGFloat = 0, bottomLeading: CGFloat = 0,
         bottomTrailing: CGFloat = 0, topTrailing: CGFloat = 0) {
        self.topLeading = topLeading
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
        self.topTrailing = topTrailing
    }
}

struct UnevenRoundedRectangle: Shape {
    var cornerRadii: RectangleCornerRadii
    var style: RoundedCornerStyle

    init(cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) {
        self.cornerRadii = cornerRadii
        self.style = style
    }

    func path(in rect: CGRect) -> Path {
        let maxRadius = min(rect.width, rect.height) / 2
        let tl = min(cornerRadii.topLeading, maxRadius), bl = min(cornerRadii.bottomLeading, maxRadius)
        let br = min(cornerRadii.bottomTrailing, maxRadius), tr = min(cornerRadii.topTrailing, maxRadius)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr,
                    startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - Modifiers

enum ScrollIndicatorCompat {
    case automatic, visible, hidden, never
}

extension View {
    @ViewBuilder
    func formStyleGroupedCompat() -> some View {
        if #available(macOS 13.0, *) {
            self.formStyle(.grouped)
        } else {
            // No grouped form on macOS 12: keep the content off the window edges.
            self.padding(EdgeInsets(top: 14, leading: 22, bottom: 14, trailing: 22))
        }
    }

    @ViewBuilder
    func formStyleColumnsCompat() -> some View {
        if #available(macOS 13.0, *) { self.formStyle(.columns) } else { self }
    }

    /// macOS 12 cannot hide SwiftUI scroll indicators: no-op there.
    @ViewBuilder
    func scrollIndicatorsCompat(_ visibility: ScrollIndicatorCompat,
                                axes: Axis.Set = [.vertical, .horizontal]) -> some View {
        if #available(macOS 13.0, *) {
            switch visibility {
            case .automatic: self.scrollIndicators(.automatic, axes: axes)
            case .visible: self.scrollIndicators(.visible, axes: axes)
            case .hidden: self.scrollIndicators(.hidden, axes: axes)
            case .never: self.scrollIndicators(.never, axes: axes)
            }
        } else {
            self
        }
    }

    /// macOS 12 cannot disable a ScrollView's scrolling: no-op there.
    @ViewBuilder
    func scrollDisabledCompat(_ disabled: Bool) -> some View {
        if #available(macOS 13.0, *) { self.scrollDisabled(disabled) } else { self }
    }

    @ViewBuilder
    func scrollContentBackgroundHiddenCompat() -> some View {
        if #available(macOS 13.0, *) { self.scrollContentBackground(.hidden) } else { self }
    }

    @ViewBuilder
    func contentTransitionNumericCompat(countsDown: Bool = false) -> some View {
        if #available(macOS 13.0, *) { self.contentTransition(.numericText(countsDown: countsDown)) } else { self }
    }

    @ViewBuilder
    func contentTransitionSymbolReplaceCompat() -> some View {
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) { self.contentTransition(.symbolEffect(.replace)) } else { self }
        #else
        self
        #endif
    }

    @ViewBuilder
    func trackingCompat(_ tracking: CGFloat) -> some View {
        if #available(macOS 13.0, *) { self.tracking(tracking) } else { self }
    }

    @ViewBuilder
    func kerningCompat(_ kerning: CGFloat) -> some View {
        if #available(macOS 13.0, *) { self.kerning(kerning) } else { self }
    }

    @ViewBuilder
    func fontWeightCompat(_ weight: Font.Weight?) -> some View {
        if #available(macOS 13.0, *) { self.fontWeight(weight) } else { self }
    }

    @ViewBuilder
    func lineLimitCompat(_ limit: Int, reservesSpace: Bool) -> some View {
        if #available(macOS 13.0, *) { self.lineLimit(limit, reservesSpace: reservesSpace) } else { self.lineLimit(limit) }
    }

    /// `onGeometryChange` (macOS 14): a preference-based equivalent.
    func onGeometryChange<T: Equatable>(for type: T.Type,
                                        of transform: @escaping (GeometryProxy) -> T,
                                        action: @escaping (T) -> Void) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: GeometryChangeKey<T>.self, value: transform(proxy))
        })
        .onPreferenceChange(GeometryChangeKey<T>.self) { value in
            if let value { action(value) }
        }
    }
}

private struct GeometryChangeKey<T: Equatable>: PreferenceKey {
    static var defaultValue: T? { nil }
    static func reduce(value: inout T?, nextValue: () -> T?) { value = nextValue() ?? value }
}

extension Text {
    func trackingCompat(_ tracking: CGFloat) -> Text {
        if #available(macOS 13.0, *) { return self.tracking(tracking) }
        return self
    }

    func kerningCompat(_ kerning: CGFloat) -> Text {
        if #available(macOS 13.0, *) { return self.kerning(kerning) }
        return self
    }

    func fontWeightCompat(_ weight: Font.Weight?) -> Text {
        if #available(macOS 13.0, *) { return self.fontWeight(weight) }
        return self
    }
}

// MARK: - Continuous hover

enum ContinuousHoverPhaseCompat {
    case active(CGPoint)
    case ended
}

extension View {
    /// `onContinuousHover` (macOS 13): a tracking-area overlay on macOS 12.
    /// Locations are in the view's own coordinate space, top-left origin.
    @ViewBuilder
    func onContinuousHoverCompat(perform action: @escaping (ContinuousHoverPhaseCompat) -> Void) -> some View {
        if #available(macOS 13.0, *) {
            self.onContinuousHover { phase in
                switch phase {
                case .active(let location): action(.active(location))
                case .ended: action(.ended)
                }
            }
        } else {
            self.overlay(ContinuousHoverTracker(action: action))
        }
    }
}

private struct ContinuousHoverTracker: NSViewRepresentable {
    let action: (ContinuousHoverPhaseCompat) -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.action = action
        return view
    }

    func updateNSView(_ view: TrackerView, context: Context) { view.action = action }

    final class TrackerView: NSView {
        var action: ((ContinuousHoverPhaseCompat) -> Void)?
        private var area: NSTrackingArea?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let new = NSTrackingArea(rect: bounds,
                                     options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                     owner: self, userInfo: nil)
            addTrackingArea(new)
            area = new
        }

        override func mouseEntered(with event: NSEvent) { report(event) }
        override func mouseMoved(with event: NSEvent) { report(event) }
        override func mouseExited(with event: NSEvent) { action?(.ended) }

        private func report(_ event: NSEvent) {
            action?(.active(convert(event.locationInWindow, from: nil)))
        }
    }
}

// MARK: - File drop

extension View {
    /// `dropDestination(for: URL.self)` (macOS 13): `onDrop` with file URLs.
    /// The drop is always reported as accepted; `perform` runs on the main queue.
    func dropURLsCompat(isTargeted: @escaping (Bool) -> Void,
                        perform: @escaping ([URL]) -> Bool) -> some View {
        let binding = Binding<Bool>(get: { false }, set: { isTargeted($0) })
        return onDrop(of: [UTType.fileURL], isTargeted: binding) { providers in
            let group = DispatchGroup()
            var urls: [URL] = []
            let lock = NSLock()
            for provider in providers {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    var url: URL?
                    if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                    else if let nsURL = item as? URL { url = nsURL }
                    if let url { lock.lock(); urls.append(url); lock.unlock() }
                }
            }
            group.notify(queue: .main) { _ = perform(urls) }
            return true
        }
    }
}

// MARK: - Animation

#if !compiler(>=5.9)
extension Animation {
    /// `Animation.spring(duration:bounce:)` (macOS 14) mapped to response/damping.
    static func spring(duration: Double = 0.5, bounce: Double = 0.0, blendDuration: Double = 0) -> Animation {
        spring(response: max(0.05, duration), dampingFraction: max(0.05, min(1, 1 - bounce)),
               blendDuration: blendDuration)
    }
}
#endif

/// `withAnimation(_:completionCriteria:_:completion:)` (macOS 14). On older
/// systems the completion runs after `approximateDuration`.
func withAnimationCompat(_ animation: Animation?, approximateDuration: TimeInterval,
                         _ body: () -> Void, completion: @escaping () -> Void) {
    withAnimation(animation, body)
    DispatchQueue.main.asyncAfter(deadline: .now() + max(0, approximateDuration), execute: completion)
}

// MARK: - NavigationSplitView

enum NavigationSplitViewVisibility: Equatable {
    case automatic, all, doubleColumn, detailOnly
}

struct NavigationSplitViewStyleCompat {
    static let balanced = NavigationSplitViewStyleCompat()
    static let automatic = NavigationSplitViewStyleCompat()
    static let prominentDetail = NavigationSplitViewStyleCompat()
}

extension View {
    @ViewBuilder
    func navigationSplitViewColumnWidthCompat(min: CGFloat? = nil, ideal: CGFloat, max: CGFloat? = nil) -> some View {
        if #available(macOS 13.0, *) {
            self.navigationSplitViewColumnWidth(min: min, ideal: ideal, max: max)
        } else {
            self.frame(minWidth: min, idealWidth: ideal, maxWidth: max)
        }
    }

    /// The real style cannot reach the NavigationSplitView inside the shim;
    /// the system's default (balanced on the Mac) applies.
    func navigationSplitViewStyleCompat(_ style: NavigationSplitViewStyleCompat) -> some View { self }
}

/// macOS 13+: the real `NavigationSplitView`. macOS 12: sidebar | divider |
/// detail in a plain `HStack`, the sidebar hidden for `.detailOnly`.
struct NavigationSplitView<Sidebar: View, Detail: View>: View {
    private let columnVisibility: Binding<NavigationSplitViewVisibility>
    private let sidebar: Sidebar
    private let detail: Detail

    init(columnVisibility: Binding<NavigationSplitViewVisibility>,
         @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) {
        self.columnVisibility = columnVisibility
        self.sidebar = sidebar()
        self.detail = detail()
    }

    var body: some View {
        if #available(macOS 13.0, *) {
            SwiftUI.NavigationSplitView(columnVisibility: realVisibility) { sidebar } detail: { detail }
        } else {
            HStack(spacing: 0) {
                if columnVisibility.wrappedValue != .detailOnly {
                    sidebar.frame(width: 210)
                    Divider()
                }
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @available(macOS 13.0, *)
    private var realVisibility: Binding<SwiftUI.NavigationSplitViewVisibility> {
        Binding(
            get: {
                switch columnVisibility.wrappedValue {
                case .automatic: return .automatic
                case .all: return .all
                case .doubleColumn: return .doubleColumn
                case .detailOnly: return .detailOnly
                }
            },
            set: { newValue in
                switch newValue {
                case .all: columnVisibility.wrappedValue = .all
                case .doubleColumn: columnVisibility.wrappedValue = .doubleColumn
                case .detailOnly: columnVisibility.wrappedValue = .detailOnly
                default: columnVisibility.wrappedValue = .automatic
                }
            })
    }
}

// MARK: - Layout-based flow layout

/// A wrapping row layout. macOS 13+: a custom `Layout`. macOS 12: an adaptive
/// grid (items share a column width instead of keeping their own).
struct FlowLayoutLite<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 6, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(macOS 13.0, *) {
            FlowLayoutLiteImpl(spacing: spacing) { content }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: spacing, alignment: .leading)],
                      alignment: .leading, spacing: spacing) { content }
        }
    }
}

// MARK: - SF Symbol effects (macOS 14)

extension View {
    /// Pulsing variable-colour symbol while `isActive`. macOS 12/13: static symbol.
    @ViewBuilder
    func symbolVariableColorCompat(reversing: Bool, isActive: Bool) -> some View {
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) {
            if reversing {
                self.symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: isActive)
            } else {
                self.symbolEffect(.variableColor.iterative, options: .repeating, isActive: isActive)
            }
        } else { self }
        #else
        self
        #endif
    }

    /// Bounce when `value` changes. macOS 12/13: no effect.
    @ViewBuilder
    func symbolBounceCompat<V: Equatable>(speed: Double = 1, value: V) -> some View {
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) { self.symbolEffect(.bounce, options: .speed(speed), value: value) } else { self }
        #else
        self
        #endif
    }
}

// MARK: - GeometryProxy

extension GeometryProxy {
    /// Height of the visible part of a named coordinate space (`bounds(of:)`,
    /// macOS 15). Older systems cannot tell; `nil` makes callers use their own default.
    func visibleHeightCompat(inSpace name: String) -> CGFloat? {
        #if compiler(>=6.0)
        if #available(macOS 15.0, *) { return bounds(of: .named(name))?.height }
        #endif
        return nil
    }
}

extension View {
    /// Hides the keyboard-focus ring (macOS 14). Older systems keep their ring.
    @ViewBuilder
    func focusEffectDisabledCompat(_ disabled: Bool = true) -> some View {
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) { self.focusEffectDisabled(disabled) } else { self }
        #else
        self
        #endif
    }
}

// MARK: - Keyboard focus and key presses (macOS 14)

extension View {
    /// Runs `perform` for `key` while the view has keyboard focus (macOS 14).
    /// macOS 12/13: the keys are not handled here; the controls stay mouse-driven.
    @ViewBuilder
    func onKeyPressCompat(_ key: KeyEquivalent, perform: @escaping () -> Void) -> some View {
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) {
            self.onKeyPress(key) { perform(); return .handled }
        } else { self }
        #else
        self
        #endif
    }

    /// A focusable editing control (macOS 14); a plain `focusable` view before.
    @ViewBuilder
    func focusableEditCompat() -> some View {
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) { self.focusable(interactions: .edit) } else { self }
        #else
        self
        #endif
    }
}

/// A text field that wraps over 1...`maxLines` lines (macOS 13); one line before.
struct MultilineTextFieldCompat: View {
    let title: String
    @Binding var text: String
    let maxLines: Int

    var body: some View {
        if #available(macOS 13.0, *) {
            TextField(title, text: $text, axis: .vertical).lineLimit(1...maxLines)
        } else {
            TextField(title, text: $text)
        }
    }
}

// MARK: - More macOS 13/14 modifiers

extension AnyTransition {
    /// `blurReplace` (macOS 14): a plain cross-fade here.
    static var blurReplaceCompat: AnyTransition { .opacity }
}

extension View {
    @ViewBuilder
    func buttonBorderShapeCapsuleCompat() -> some View {
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) { self.buttonBorderShape(.capsule) } else { self }
        #else
        self
        #endif
    }

    /// `transaction(value:_:)` (macOS 14). Older systems skip the adjustment.
    @ViewBuilder
    func transactionCompat<V: Equatable>(value: V, _ body: @escaping (inout Transaction) -> Void) -> some View {
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) { self.transaction(value: value, body) } else { self }
        #else
        self
        #endif
    }

    /// Hiding the sidebar toggle (macOS 14) is not possible earlier.
    func toolbarRemovingSidebarToggleCompat() -> some View { self }

    @ViewBuilder
    func listRowSeparatorHiddenCompat() -> some View {
        if #available(macOS 13.0, *) { self.listRowSeparator(.hidden) } else { self }
    }

    /// `onTapGesture { location in }` (macOS 13): a zero-distance drag on macOS 12.
    @ViewBuilder
    func onTapLocationCompat(perform action: @escaping (CGPoint) -> Void) -> some View {
        if #available(macOS 13.0, *) {
            self.onTapGesture { location in action(location) }
        } else {
            self.gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local).onEnded { value in
                action(value.location)
            })
        }
    }
}

// MARK: - Colours

extension Color {
    /// `.quaternary.opacity(x)` needs macOS 14 (`ShapeStyle.opacity`); this is
    /// the same faint system fill as a plain `Color`.
    static func quaternaryFill(_ opacity: Double) -> Color {
        Color(nsColor: .quaternaryLabelColor).opacity(opacity)
    }
}

extension View {
    /// A fixed sidebar width.
    @ViewBuilder
    func navigationSplitViewColumnWidthCompat(_ width: CGFloat) -> some View {
        if #available(macOS 13.0, *) {
            self.navigationSplitViewColumnWidth(width)
        } else {
            self.frame(width: width)
        }
    }
}

// MARK: - What this system can do

/// Capabilities the Monterey port cannot provide on older systems. Features
/// that depend on them are hidden or disabled instead of shown as working.
enum MontereyCapabilities {
    /// Recording the Mac's sound needs ScreenCaptureKit audio (macOS 13) or
    /// Core Audio process taps (macOS 14.2).
    static var systemAudioRecording: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    /// Per-app audio (the volume mixer, the live equalizer bars) needs Core
    /// Audio process taps: macOS 14.2.
    static var processAudioTaps: Bool {
        #if compiler(>=5.9)
        if #available(macOS 14.2, *) { return true }
        #endif
        return false
    }

    /// The fan-control helper is installed through `SMAppService` daemons (macOS 13).
    static var privilegedHelperService: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }
}

extension AppFeature {
    /// Features this system cannot run at all. They report unavailable, whatever
    /// the user's visibility setting says.
    var isUnsupportedOnThisSystem: Bool {
        switch self {
        case .mixer, .notchLiveEqualizer: return !MontereyCapabilities.processAudioTaps
        case .fanControl: return !MontereyCapabilities.privilegedHelperService
        default: return false
        }
    }
}
