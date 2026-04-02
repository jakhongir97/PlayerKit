import Foundation

enum DubberVisualState: Equatable {
    case idle
    case loading
    case settling
    case live
    case error
}

extension PlayerManager {
    var dubberVisualState: DubberVisualState {
        if hasDubberIssue {
            return .error
        }
        if isDubbedPlaybackActive {
            return .live
        }
        if isDubSettling {
            return .settling
        }
        if isDubLoading {
            return .loading
        }
        return .idle
    }

    var isDubSettling: Bool {
        guard dubSessionID != nil else { return false }

        if isCompletionLabel(dubStatus) {
            return true
        }

        guard let progress = normalizedDubberStatus(dubProgressMessage) else {
            return false
        }

        return progress.contains("finalizing")
            || progress.contains("waiting for dubbed audio track")
            || progress.contains("loading dubbed stream")
    }
}

private func normalizedDubberStatus(_ value: String?) -> String? {
    guard let value else { return nil }

    let normalized = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

    return normalized.isEmpty ? nil : normalized
}

private func isCompletionLabel(_ value: String?) -> Bool {
    guard let normalized = normalizedDubberStatus(value) else { return false }
    return normalized == "complete"
        || normalized == "completed"
        || normalized == "ready"
}
