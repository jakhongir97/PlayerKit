//
//  CircularGlassIcon.swift
//  PlayerKit
//
//  Created by Jakhongir Nematov on 24/09/25.
//

import SwiftUI

// MARK: - Reusable circular icon + glass effect
private struct CircularGlassIcon: ViewModifier {
    var iconSize: CGFloat = 20
    var frameSize: CGFloat = 30
    var padding: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: frameSize, height: frameSize)
            .padding(padding)
            .contentShape(Circle())
            .clipShape(Circle())
            .modifier(GlassCircle())
    }

    private struct GlassCircle: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content.glassEffect(.clear, in: .circle)
            } else if #available(iOS 15.0, *) {
                // Material-based fallback
                content
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    )
            } else {
                content
            }
        }
    }
}

public extension View {
    func circularGlassIcon(iconSize: CGFloat = 20,
                           frameSize: CGFloat = 30,
                           padding: CGFloat = 10) -> some View {
        modifier(CircularGlassIcon(iconSize: iconSize, frameSize: frameSize, padding: padding))
    }
}
