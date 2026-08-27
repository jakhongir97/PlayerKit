import Foundation

/// User-visible copy rendered by PlayerKit.
///
/// PlayerKit deliberately does not select a locale or read a resource bundle.
/// A host that localizes its UI can mutate a value, then assign it to
/// ``PlayerManager/strings``. English defaults preserve the existing UI for
/// hosts that do not inject copy.
///
/// Sentence formatters receive semantic values instead of a prebuilt English
/// sentence so languages can choose their own word order and plural forms.
public struct PlayerStrings {
    // MARK: Transport controls

    public var closePlayer = "Close player"
    public var closePlayerHint = "Dismisses the player screen"
    public var play = "Play"
    public var pause = "Pause"
    public var togglePlaybackHint = "Toggles playback"
    public var nextEpisodeAccessibilityLabel = "Next episode"
    public var nextEpisodeHint = "Plays the next episode"
    public var previousEpisodeAccessibilityLabel = "Previous episode"
    public var previousEpisodeHint = "Plays the previous episode"
    public var rotatePlayer = "Rotate player"
    public var rotatePlayerHint = "Toggles between portrait and landscape"
    public var lockControls = "Lock controls"
    public var unlockControls = "Unlock controls"
    public var lockControlsHint = "Prevents accidental control interactions"
    public var startPictureInPicture = "Start Picture in Picture"
    public var stopPictureInPicture = "Stop Picture in Picture"
    public var pictureInPictureHint = "Toggles Picture in Picture mode"
    public var buffering = "Buffering"
    public var bufferingHint = "Media is loading"
    public var playbackPosition = "Playback position"
    public var seekThroughMediaHint = "Drag to seek through the media"
    public var live = "LIVE"
    public var goLive = "Go Live"
    public var goLiveHint = "Jumps to the live edge"
    public var playbackPositionValue: (_ current: String, _ total: String) -> String = {
        "\($0) of \($1)"
    }
    public var skipIntervalValue: (_ seconds: Double) -> String = {
        Self.decimalLabel(max($0.isFinite ? $0 : 0, 0))
    }
    public var skipForwardSeconds: (_ seconds: Double) -> String = {
        "Skip forward \(Self.intervalLabel($0)) seconds"
    }
    public var skipBackSeconds: (_ seconds: Double) -> String = {
        "Skip back \(Self.intervalLabel($0)) seconds"
    }
    public var heuristicSkipButtonTitles = HeuristicSkipButtonTitles()
    public var skipIntroHint = "Skips the opening section of this episode"
    public var skipOutroHint = "Skips the ending section of this episode"

    // MARK: Media menus and streaming information

    public var audioTracksTitle = "Audio Tracks"
    public var audioTracksAccessibilityLabel = "Audio tracks"
    public var audioTracksHint = "Opens audio track options"
    public var subtitles = "Subtitles"
    public var turnOffSubtitles = "Turn Off"
    public var subtitlesHint = "Opens subtitle options"
    public var playbackSpeedTitle = "Playback Speed"
    public var playbackSpeedAccessibilityLabel = "Playback speed"
    public var playbackSpeedHint = "Opens playback speed options"
    public var playbackSpeedOption: (_ speed: Float, _ isNormal: Bool) -> String = { speed, isNormal in
        isNormal ? "1.0x (Normal)" : "\(speed)x"
    }
    public var playbackQualityTitle = "Quality"
    public var playbackQualityAccessibilityLabel = "Playback quality"
    public var playbackQualityHint = "Opens video quality options"
    public var automaticQuality = "Auto"
    public var maximumQuality = "Maximum"
    public var optimalQuality = "Optimal"
    public var minimumQuality = "Minimum"
    public var streamingInformation = "Streaming information"
    public var streamingInformationHint = "Shows bitrate, buffer, frame rate and resolution"
    public var moreActions = "More"
    public var moreActionsHint = "Shows more actions for this content"
    public var bitrate = "Bitrate"
    public var buffer = "Buffer"
    public var frameRate = "Frame Rate"
    public var resolution = "Resolution"
    public var streamingUnknownValue = "Unknown"
    /// Formats a nonnegative duration in seconds.
    public var streamingBufferDurationValue: (_ seconds: Double) -> String = {
        "\(Self.intervalLabel(max($0.isFinite ? $0 : 0, 0))) sec"
    }
    /// Formats a nonnegative bitrate whose input unit is megabits per second.
    public var streamingVideoBitrateValue: (_ megabitsPerSecond: Double) -> String = {
        let value = max($0.isFinite ? $0 : 0, 0)
        return value == 0 ? "0 Mbps" : String(format: "%.2f Mbps", value)
    }
    public var streamingFrameRateValue: (_ framesPerSecond: Double) -> String = {
        "\(Self.decimalLabel(max($0.isFinite ? $0 : 0, 0))) fps"
    }
    public var streamingResolutionValue: (_ width: Int, _ height: Int) -> String = {
        guard $0 > 0, $1 > 0 else { return "Unknown" }
        return "\($0)x\($1)"
    }

    // MARK: Empty, protected, recovery, and ended states

    public var noVideoLoaded = "No video loaded"
    public var chooseVideoToBegin = "Choose a video to begin playback."
    public var videoHiddenDuringScreenSharing = "Video hidden while screen sharing is active"
    public var refreshing = "Refreshing…"
    public var retry = "Retry"
    public var close = "Close"
    public var dismiss = "Dismiss"
    public var playbackFinished = "Playback finished"
    public var replay = "Replay"

    public var playbackUnavailableTitle = "Playback unavailable"
    public var playbackUnavailableMessage = "We couldn’t load this video. Check your connection and try again."
    public var actionUnavailableTitle = "Action unavailable"
    public var actionUnavailableMessage = "That action couldn’t be completed. You can keep watching here."
    public var pictureInPictureUnavailableTitle = "Picture in Picture unavailable"
    public var pictureInPictureUnavailableMessage = "Picture in Picture couldn’t start. You can keep watching here."
    public var castingUnavailableTitle = "Casting unavailable"
    public var castingUnavailableMessage = "Casting isn’t available right now. You can keep watching on this device."
    public var externalPlaybackUnavailableTitle = "External playback unavailable"
    public var externalPlaybackUnavailableMessage = "This video can’t play on the selected device. You can keep watching here."

    /// Short safe messages returned by `PlayerKitError.userFacingDescription(using:)`.
    public var mediaLoadFailedDescription = "The video couldn’t be loaded. Check your connection and try again."
    public var pictureInPictureFailedDescription = "Picture in Picture couldn’t start."
    public var castingFailedDescription = "Casting isn’t available right now."
    public var externalPlaybackFailedDescription = "External playback isn’t available right now."
    public var actionFailedDescription = "The action couldn’t be completed."

    // MARK: Routes and fallback metadata

    public var airPlay = "AirPlay"
    public var airPlayHint = "Opens the AirPlay device picker"
    public var chromecast = "Chromecast"
    public var chromecastHint = "Opens the Chromecast device picker"
    public var defaultStreamTitle = "PlayerKit Stream"
    public var vlcPlaybackEngineName = "VLC Player"
    public var avPlaybackEngineName = "AV Player"
    public var playbackEngineAccessibilityLabel = "Playback engine"
    public var selectPlaybackEngineHint = "Selects a playback engine"
    public var activePlaybackEngineHint = "Shows the active playback engine"

    // MARK: Gesture UI and accessibility

    public var seconds = "SECONDS"
    public var forwardSeconds: (_ seconds: Double) -> String = {
        "Forward \(Self.intervalLabel($0)) seconds"
    }
    public var backSeconds: (_ seconds: Double) -> String = {
        "Back \(Self.intervalLabel($0)) seconds"
    }
    public var lockedVideoHint = "Controls are locked. Use Unlock controls to make playback actions available."
    public var videoControlsHint = "Shows the playback controls. Playback speed is in the controls; seeking, volume, brightness and zoom are available in Actions when supported."
    public var video = "Video"
    public var playOrPause = "Play or pause"
    public var fitVideoToScreen = "Fit video to screen"
    public var fillScreen = "Fill screen"
    public var increaseVolume = "Increase volume"
    public var decreaseVolume = "Decrease volume"
    public var increaseBrightness = "Increase brightness"
    public var decreaseBrightness = "Decrease brightness"
    public var fill = "Fill"
    public var fit = "Fit"
    public var deviceVolumeIsLow = "Device volume is low"
    public var locked = "Locked"
    public var volume = "Volume"
    public var brightness = "Brightness"
    public var controlsAreLocked = "Controls are locked"
    public var halfSpeedScrubbing = "Half-Speed Scrubbing"
    public var quarterSpeedScrubbing = "Quarter-Speed Scrubbing"
    public var fineScrubbing = "Fine Scrubbing"
    public var swipeForBrightness = "Swipe up or down for brightness"
    public var swipeForVolume = "Swipe up or down for volume"
    public var swipeHereForBrightness = "Swipe here for brightness"
    public var swipeHereForVolume = "Swipe here for volume"
    public var swipeUpAndDownHereForBrightness = "Swipe up and down here for brightness"
    public var swipeUpAndDownHereForVolume = "Swipe up and down here for volume"
    public var skipGestureTips = "Skip gesture tips"
    public var levelPercentage: (_ unitValue: Double) -> String = {
        guard $0.isFinite else { return "0%" }
        return "\(Int(($0 * 100).rounded()))%"
    }
    public var gestureSpeedValue: (_ speed: Float) -> String = { speed in
        guard speed.isFinite, speed > 0 else { return "1×" }
        let rounded = (speed * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return "\(Int(rounded))×"
        }
        return String(format: "%.1f×", rounded)
    }
    public var volumeAnnouncement: (_ value: String) -> String = { "Volume \($0)" }
    public var brightnessAnnouncement: (_ value: String) -> String = { "Brightness \($0)" }
    public var playbackSpeedAnnouncement: (_ value: String) -> String = { "Playback speed \($0)" }
    public var scrubAnnouncement: (_ position: String, _ detail: String?) -> String = { position, detail in
        detail.map { "\(position), \($0)" } ?? position
    }

    public init() {}

    private static func intervalLabel(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0" }
        let rounded = seconds.rounded()
        return rounded == seconds ? String(Int(rounded)) : String(format: "%.1f", seconds)
    }

    private static func decimalLabel(_ value: Double) -> String {
        var label = String(format: "%.2f", value)
        while label.last == "0" { label.removeLast() }
        if label.last == "." { label.removeLast() }
        return label
    }
}
