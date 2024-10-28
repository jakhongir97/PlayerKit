//
//  ViewRenderingProtocol.swift
//
//
//  Created by Jakhongir Nematov on 28/10/24.
//

import UIKit

public protocol ViewRenderingProtocol: AnyObject {
    func getPlayerView() -> UIView
    func setupPiP()
    func startPiP()
    func stopPiP()
}
