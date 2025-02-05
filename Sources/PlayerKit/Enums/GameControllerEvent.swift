
enum GameControllerEvent {
    case playPause
    case fastForward
    case rewind
    case fastForwardAmount(Double)
    case rewindAmount(Double)
    case nextVideo
    case previousVideo
    case scrubStarted
    case scrubEnded
    case closePlayer
    case focusUp
    case focusDown
    case focusSelect
}

enum ScrubDirection {
    case forward
    case backward
}

