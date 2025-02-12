//
//  VLCPlayerDrawableProxy.swift
//  PlayerKit
//
//  Created by Jakhongir Nematov on 12/02/25.
//

import UIKit
import VLCKit

class VLCPlayerDrawableProxy: NSObject {
    weak var wrapper: VLCPlayerWrapper?

    init(wrapper: VLCPlayerWrapper) {
        self.wrapper = wrapper
        super.init()
    }
}

extension VLCPlayerDrawableProxy: VLCDrawable {
    func addSubview(_ view: UIView) {
        wrapper?.getPlayerView().addSubview(view)
    }

    func bounds() -> CGRect {
        return wrapper?.getPlayerView().bounds ?? .zero
    }
}

extension VLCPlayerDrawableProxy: VLCPictureInPictureDrawable {
    func mediaController() -> (any VLCPictureInPictureMediaControlling)! {
        return self
    }

    func pictureInPictureReady() -> (((any VLCPictureInPictureWindowControlling)?) -> Void)! {
        return { [weak self] controller in
            self?.wrapper?.pipController = controller
        }
    }
}

extension VLCPlayerDrawableProxy: VLCPictureInPictureMediaControlling {
    func play() {
        wrapper?.player.play()
    }
    
    func pause() {
        wrapper?.player.pause()
    }
    
    func mediaTime() -> Int64 {
        return wrapper?.player.time.value?.int64Value ?? 0
    }

    func mediaLength() -> Int64 {
        return wrapper?.player.media?.length.value?.int64Value ?? 0
    }

    func seek(by offset: Int64) async {
        guard let wrapper = wrapper else { return }
        let current = wrapper.player.time.value?.int64Value ?? 0
        let newPosition = current + offset
        wrapper.player.time = VLCTime(number: NSNumber(value: newPosition))
    }

    func isMediaSeekable() -> Bool {
        return false
    }

    func isMediaPlaying() -> Bool {
        return wrapper?.player.isPlaying ?? false
    }
}

