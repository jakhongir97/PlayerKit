import SwiftUI

/// Every session-level action behind one disc.
///
/// The top bar used to carry five of them in a row — Cast, AirPlay, playback
/// information, the debug engine picker and the host's overflow — plus the
/// lock. Six controls is more than the bar can hold on a phone: they left the
/// title about fifty points to render in, and they are all things a viewer
/// reaches for occasionally rather than during playback. They now live in one
/// panel behind a single control.
///
/// The lock deliberately stays outside it. It is the only way out of a locked
/// player, so it can never be behind a menu that the lock itself would hide.
@MainActor
struct PlayerOptionsMenuView: View {
    @ObservedObject var playerManager: PlayerManager
    @State private var isPresented = false

    init(playerManager: PlayerManager = .shared) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
    }

    var body: some View {
        Button {
            playerManager.userInteracted()
            isPresented = true
        } label: {
            Image(systemName: "ellipsis")
                .playerControlIcon(appearance: playerManager.appearance)
        }
        .buttonStyle(PlayerControlButtonStyle())
        .accessibilityLabel(playerManager.strings.moreActions)
        .accessibilityHint(playerManager.strings.moreActionsHint)
        .accessibilityIdentifier("player.options")
        // `.top` is the edge of the *panel* the arrow sits on, which is the one
        // that hangs it below a control already against the top of the screen.
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            PlayerOptionsPanel(playerManager: playerManager) {
                isPresented = false
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
            .popoverCompactAdaptationCompat()
        }
    }
}

// MARK: - The panel

@MainActor
private struct PlayerOptionsPanel: View {
    @ObservedObject var playerManager: PlayerManager
    @StateObject private var engine: PlayerMenuViewModel
    @State private var showsStreamingInfo = false
    @State private var showsEngines = false
    @State private var expandedHostActionID: String?
    /// Closes the popover before an action presents anything of its own.
    private let dismiss: () -> Void

    init(playerManager: PlayerManager, dismiss: @escaping () -> Void) {
        _playerManager = ObservedObject(wrappedValue: playerManager)
        _engine = StateObject(wrappedValue: PlayerMenuViewModel(playerManager: playerManager))
        self.dismiss = dismiss
    }

    /// Runs an action that presents something — a share sheet, the Cast dialog,
    /// a pushed screen — with the panel already out of the way.
    ///
    /// Presenting from inside a live popover either fails outright or leaves
    /// the popover stranded over the thing it presented, and a stranded panel
    /// also never runs `onDisappear`, so the chrome hold below would never be
    /// released and the bar would stop auto-hiding for the rest of the session.
    private func dismissThen(_ action: @escaping @MainActor () -> Void) {
        playerManager.userInteracted()
        dismiss()
        DispatchQueue.main.async(execute: action)
    }

    private var hostActions: [PlayerHostAction] { playerManager.hostActions.presentable }

    private var showsCast: Bool {
        #if canImport(UIKit) && canImport(GoogleCast)
        true
        #else
        false
        #endif
    }

    private var showsEngineRow: Bool {
        #if DEBUG
        PlayerType.supportedCases.count > 1
        #else
        false
        #endif
    }

    var body: some View {
        // Scrollable: two expandable sections plus however many rows the host
        // contributes can easily exceed the height a popover is given —
        // notably an iPhone in landscape — and a plain stack simply clips the
        // rows past the edge, with no way to reach them.
        ScrollView {
            panelRows
        }
        // Only as tall as it needs to be, up to what a compact landscape
        // presentation can actually show.
        .frame(maxHeight: 420)
        .padding(.vertical, PlayerChromeMetrics.spacingS)
        .glassBackgroundCompat(cornerRadius: PlayerChromeMetrics.cardCornerRadius)
        // The rows are white-on-dark like the rest of the chrome, and the
        // material behind them follows the presentation's colour scheme, not
        // the video's. Pinning it dark keeps the panel legible in Light Mode.
        .environment(\.colorScheme, .dark)
        .onAppear {
            // Hold the chrome for as long as the panel is up, the way the
            // desktop diagnostics window does. Otherwise the bar auto-hides
            // underneath an open panel and takes its anchor with it.
            playerManager.userInteracting = true
            playerManager.userInteracted()
            #if canImport(UIKit) && canImport(GoogleCast)
            // The Cast button used to do this when the bar drew it: it installs
            // the session callbacks that keep the row's state truthful.
            _ = playerManager.prepareChromecastButton()
            #endif
        }
        .onDisappear {
            playerManager.userInteracting = false
            playerManager.userInteracted()
        }
    }

    private var panelRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsCast {
                castRow
            }

            if playerManager.canUseAirPlay {
                airPlayRow
            }

            if showsCast || playerManager.canUseAirPlay {
                separator
            }

            streamingInfoRow

            if showsEngineRow {
                separator
                engineRow
            }

            if !hostActions.isEmpty {
                separator
                ForEach(hostActions) { action in
                    hostActionRow(action)
                }
            }
        }
    }

    // MARK: Routes

    /// Cast needs no view of its own: `presentChromecastDevicePicker()`
    /// initialises the SDK on first intent and opens Google's own dialog.
    private var castRow: some View {
        Button {
            dismissThen { playerManager.presentChromecastDevicePicker() }
        } label: {
            PlayerOptionRow(
                systemImage: "airplayaudio",
                title: playerManager.strings.chromecast,
                isSelected: playerManager.isCasting
            )
        }
        .buttonStyle(PlayerOptionRowStyle())
        .accessibilityLabel(playerManager.strings.chromecast)
        .accessibilityHint(playerManager.strings.chromecastHint)
        .accessibilityIdentifier("player.cast")
    }

    /// AirPlay has no programmatic entry point — `AVRoutePickerView` opens the
    /// system picker only when the real control is touched. So the real control
    /// is laid over the row, invisible but hit-testable, and the row underneath
    /// is drawn purely for looks.
    private var airPlayRow: some View {
        PlayerOptionRow(
            systemImage: "airplayvideo",
            title: playerManager.strings.airPlay,
            isSelected: false
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .overlay(
            // `colorMultiply`, not `opacity`: the picker has to stay opaque to
            // UIKit's hit-testing — which ignores views under 1% alpha — while
            // rendering nothing, otherwise its own glyph ghosts across the
            // middle of the row on top of the row's own.
            airPlayPicker.colorMultiply(.clear)
        )
    }

    @ViewBuilder
    private var airPlayPicker: some View {
        #if canImport(UIKit)
        AirPlayRoutePickerView(
            accessibilityLabel: playerManager.strings.airPlay,
            accessibilityHint: playerManager.strings.airPlayHint
        )
        #else
        // The AppKit picker labels itself.
        AirPlayRoutePickerView()
        #endif
    }

    // MARK: Playback information

    private var streamingInfoRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                playerManager.userInteracted()
                withAnimation(PlayerChromeMotion.hover) {
                    showsStreamingInfo.toggle()
                }
            } label: {
                PlayerOptionRow(
                    systemImage: "info.circle",
                    title: playerManager.strings.streamingInformation,
                    disclosure: showsStreamingInfo ? .expanded : .collapsed
                )
            }
            .buttonStyle(PlayerOptionRowStyle())
            .accessibilityLabel(playerManager.strings.streamingInformation)
            .accessibilityHint(playerManager.strings.streamingInformationHint)
            .accessibilityIdentifier("player.info")

            if showsStreamingInfo {
                StreamingInfoView(playerManager: playerManager)
                    .padding(.horizontal, PlayerChromeMetrics.spacingL)
                    .padding(.bottom, PlayerChromeMetrics.spacingS)
            }
        }
    }

    // MARK: Playback engine (DEBUG)

    private var engineRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                engine.userInteracted()
                withAnimation(PlayerChromeMotion.hover) {
                    showsEngines.toggle()
                }
            } label: {
                PlayerOptionRow(
                    systemImage: "wrench.and.screwdriver.fill",
                    title: playerManager.strings.playbackEngineAccessibilityLabel,
                    disclosure: showsEngines ? .expanded : .collapsed
                )
            }
            .buttonStyle(PlayerOptionRowStyle())
            .accessibilityLabel(playerManager.strings.playbackEngineAccessibilityLabel)
            .accessibilityHint(playerManager.strings.selectPlaybackEngineHint)
            .accessibilityIdentifier("player.debug.backendMenu")

            if showsEngines {
                ForEach(PlayerType.supportedCases) { playerType in
                    Button {
                        engine.switchPlayer(to: playerType)
                    } label: {
                        PlayerOptionRow(
                            systemImage: nil,
                            title: playerType.title(using: playerManager.strings),
                            isSelected: engine.selectedPlayerType == playerType,
                            isIndented: true
                        )
                    }
                    .buttonStyle(PlayerOptionRowStyle())
                }
            }
        }
    }

    // MARK: Host actions

    @ViewBuilder
    private func hostActionRow(_ action: PlayerHostAction) -> some View {
        switch action.kind {
        case .action(let handler):
            Button {
                dismissThen(handler)
            } label: {
                PlayerOptionRow(image: action.image, title: action.title)
            }
            .buttonStyle(PlayerOptionRowStyle())
            .disabled(!action.isEnabled)

        case .submenu(let children):
            let isExpanded = expandedHostActionID == action.id
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    playerManager.userInteracted()
                    withAnimation(PlayerChromeMotion.hover) {
                        expandedHostActionID = isExpanded ? nil : action.id
                    }
                } label: {
                    PlayerOptionRow(
                        image: action.image,
                        title: action.title,
                        disclosure: isExpanded ? .expanded : .collapsed
                    )
                }
                .buttonStyle(PlayerOptionRowStyle())
                .disabled(!action.isEnabled)

                if isExpanded {
                    ForEach(children.presentable) { child in
                        Button {
                            if case .action(let handler) = child.kind {
                                dismissThen(handler)
                            }
                        } label: {
                            PlayerOptionRow(
                                image: child.image,
                                title: child.title,
                                isIndented: true
                            )
                        }
                        .buttonStyle(PlayerOptionRowStyle())
                        .disabled(!child.isEnabled)
                    }
                }
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 1)
            .padding(.vertical, PlayerChromeMetrics.spacingXS)
            .accessibilityHidden(true)
    }
}

// MARK: - One row

enum PlayerOptionDisclosure {
    case none
    case collapsed
    case expanded
}

/// A row in the options panel: leading glyph, title, trailing state.
///
/// Every row is at least ``PlayerChromeMetrics/minimumHitTarget`` tall, so a
/// panel of them is as tappable as the discs it replaced.
@MainActor
struct PlayerOptionRow: View {
    var systemImage: String?
    var image: Image?
    let title: String
    var isSelected: Bool = false
    var disclosure: PlayerOptionDisclosure = .none
    var isIndented: Bool = false

    init(
        systemImage: String?,
        title: String,
        isSelected: Bool = false,
        disclosure: PlayerOptionDisclosure = .none,
        isIndented: Bool = false
    ) {
        self.systemImage = systemImage
        self.title = title
        self.isSelected = isSelected
        self.disclosure = disclosure
        self.isIndented = isIndented
    }

    init(
        image: Image?,
        title: String,
        isSelected: Bool = false,
        disclosure: PlayerOptionDisclosure = .none,
        isIndented: Bool = false
    ) {
        self.image = image
        self.title = title
        self.isSelected = isSelected
        self.disclosure = disclosure
        self.isIndented = isIndented
    }

    var body: some View {
        HStack(spacing: PlayerChromeMetrics.spacingM) {
            glyph
                .frame(width: 22, alignment: .center)

            Text(title)
                .playerChromeFont(.action)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: PlayerChromeMetrics.spacingS)

            trailing
        }
        .padding(.leading, isIndented
                 ? PlayerChromeMetrics.spacingL + PlayerChromeMetrics.spacingXL
                 : PlayerChromeMetrics.spacingL)
        .padding(.trailing, PlayerChromeMetrics.spacingL)
        .frame(minHeight: PlayerChromeMetrics.minimumHitTarget)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var glyph: some View {
        if let image {
            // `.resizable()` first: a host's PNG is not a symbol, so without it
            // the asset renders at its own pixel size and blows the row apart.
            image
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundColor(.white.opacity(0.9))
        } else if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch disclosure {
        case .none:
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
        case .collapsed, .expanded:
            Image(systemName: disclosure == .expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

/// Rows highlight on press rather than scaling: a list item that shrinks under
/// the finger reads as a button that moved away from it.
struct PlayerOptionRowStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.14 : 0))
            .animation(PlayerChromeMotion.hover, value: configuration.isPressed)
            // The one dimming value the chrome uses for "present but cannot act".
            .playerControlEnabled(isEnabled)
    }
}
