//
//  VLCPlayerDrawableProxy.swift
//  PlayerKit
//
//  Created by Jakhongir Nematov on 12/02/25.
//

#if canImport(VLCKit) && canImport(UIKit)
import UIKit
import VLCKit

/// VLCKit owns and calls this bridge from its media threads. Its only mutable
/// state is a runtime-managed weak reference; all player/UI access is relayed
/// to MainActor below.
final class VLCPlayerDrawableProxy: NSObject, @unchecked Sendable {
    weak var wrapper: VLCPlayerWrapper?

    init(wrapper: VLCPlayerWrapper) {
        self.wrapper = wrapper
        super.init()
    }
}

private struct VLCUncheckedPiPController: @unchecked Sendable {
    let value: (any VLCPictureInPictureWindowControlling)?
}

extension VLCPlayerDrawableProxy: VLCDrawable {
    nonisolated func addSubview(_ view: UIView) {
        // VLCKit invokes drawable UI callbacks on the main thread. Keep the
        // Objective-C protocol witness nonisolated, then make that SDK contract
        // explicit at the UIKit boundary.
        MainActor.assumeIsolated {
            wrapper?.getPlayerView().addSubview(view)
        }
    }

    nonisolated func bounds() -> CGRect {
        MainActor.assumeIsolated {
            wrapper?.getPlayerView().bounds ?? .zero
        }
    }
}

extension VLCPlayerDrawableProxy: VLCPictureInPictureDrawable {
    nonisolated func mediaController() -> (any VLCPictureInPictureMediaControlling)! {
        return self
    }

    nonisolated func pictureInPictureReady() -> (((any VLCPictureInPictureWindowControlling)?) -> Void)! {
        return { [weak self] controller in
            let target = self?.wrapper
            let transferredController = VLCUncheckedPiPController(value: controller)
            MainActor.assumeIsolated {
                target?.pipController = transferredController.value
            }
        }
    }
}

extension VLCPlayerDrawableProxy: VLCPictureInPictureMediaControlling {
    nonisolated func play() {
        let target = wrapper
        Task { @MainActor in
            target?.player.play()
        }
    }
    
    nonisolated func pause() {
        let target = wrapper
        Task { @MainActor in
            target?.player.pause()
        }
    }
    
    nonisolated func mediaTime() -> Int64 {
        MainActor.assumeIsolated {
            wrapper?.player.time.value?.int64Value ?? 0
        }
    }

    nonisolated func mediaLength() -> Int64 {
        MainActor.assumeIsolated {
            let length = wrapper?.player.media?.length.value?.int64Value ?? 0
            return max(length, 0)
        }
    }

    nonisolated func seek(by offset: Int64) async {
        let target = wrapper
        await MainActor.run {
            guard let target else { return }
            let length = target.player.media?.length.value?.int64Value ?? 0
            guard Self.isFiniteSeekableMedia(
                isSeekable: target.player.isSeekable,
                durationMilliseconds: length
            ) else { return }
            let current = target.player.time.value?.int64Value ?? 0
            let (sum, overflow) = current.addingReportingOverflow(offset)
            let candidate = overflow ? (offset >= 0 ? length : 0) : sum
            let newPosition = min(max(candidate, 0), length)
            target.player.time = VLCTime(number: NSNumber(value: newPosition))
        }
    }

    nonisolated func isMediaSeekable() -> Bool {
        MainActor.assumeIsolated {
            guard let wrapper else { return false }
            return Self.isFiniteSeekableMedia(
                isSeekable: wrapper.player.isSeekable,
                durationMilliseconds: wrapper.player.media?.length.value?.int64Value ?? 0
            )
        }
    }

    nonisolated func isMediaPlaying() -> Bool {
        MainActor.assumeIsolated {
            wrapper?.player.isPlaying ?? false
        }
    }

    nonisolated static func isFiniteSeekableMedia(
        isSeekable: Bool,
        durationMilliseconds: Int64
    ) -> Bool {
        isSeekable && durationMilliseconds > 0
    }
}
#endif
