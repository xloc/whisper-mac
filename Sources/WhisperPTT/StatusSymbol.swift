import AppKit
import Symbols
import WhisperPTTCore

@MainActor
final class StatusSymbol: NSImageView {
    private var displayedStatus: PTTStatus?
    private var reducedMotion = false

    init() {
        super.init(frame: .zero)
        symbolConfiguration = .init(pointSize: 16, weight: .regular)
        imageScaling = .scaleProportionallyDown
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Let the status-bar button receive clicks through the animated image.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(_ status: PTTStatus, reduceMotion: Bool) {
        guard status != displayedStatus || reduceMotion != reducedMotion else { return }
        displayedStatus = status
        reducedMotion = reduceMotion
        removeAllSymbolEffects(animated: false)
        image = NSImage(systemSymbolName: status.symbolName, accessibilityDescription: status.title)
        image?.isTemplate = true
        guard !reduceMotion else { return }
        switch status {
        case .loading, .recording:
            var options = SymbolEffectOptions.repeating
            if #available(macOS 15, *) { options = .repeat(.continuous) }
            addSymbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing, options: options)
        case .transcribing:
            var options = SymbolEffectOptions.repeating
            if #available(macOS 15, *) { options = .repeat(.periodic(delay: 1.0)) }
            // Keep the glyph intact at menu-bar size instead of redrawing its individual layers.
            addSymbolEffect(.pulse.wholeSymbol, options: options)
        case .error:
            if #available(macOS 26, *) {
                addSymbolEffect(.drawOn.individually, options: .nonRepeating)
            }
        default: break
        }
    }
}
