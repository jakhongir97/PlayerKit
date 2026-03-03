//
//  ViewRenderingProtocol.swift
//
//
//  Created by Jakhongir Nematov on 28/10/24.
//

public protocol ViewRenderingProtocol: AnyObject {
    func getPlayerView() -> PKView
    func setupPiP()
    func startPiP()
    func stopPiP()
}
