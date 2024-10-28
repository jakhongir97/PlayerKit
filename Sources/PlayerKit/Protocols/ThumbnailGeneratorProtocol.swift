//
//  ThumbnailGeneratorProtocol.swift
//
//
//  Created by Jakhongir Nematov on 28/10/24.
//

import UIKit

public protocol ThumbnailGeneratorProtocol: AnyObject {
    func generateThumbnail(at time: Double, completion: @escaping (UIImage?) -> Void)
}
