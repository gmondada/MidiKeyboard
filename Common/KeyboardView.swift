//
//  KeyboardView.swift
//
//  Created by Gabriele Mondada on October 29, 2022.
//  Copyright (c) 2022 Gabriele Mondada.
//  Distributed under the terms of the MIT License.
//

import Foundation
import SwiftUI
import Combine

struct KeyboardView: View {
    @Environment(\.pixelLength) private var pixelLength: CGFloat

    var model: KeyboardModel

    func glissandoGesture(keyboardGeometry: KeyboardGeometry) -> some Gesture {
        return DragGesture(minimumDistance: 0)
            .onChanged { action in
                let keyIndex = keyboardGeometry.keyIndex(at: action.location)
                if keyIndex != model.glissandoKeyIndex {
                    if model.glissandoKeyIndex != -1 {
                        model.setKeyPressed(keyIndex: model.glissandoKeyIndex, isPressed: false)
                    }
                    model.setKeyPressed(keyIndex: keyIndex, isPressed: true)
                    model.glissandoKeyIndex = keyIndex
                }
            }
            .onEnded { _ in
                if model.glissandoKeyIndex != -1 {
                    model.setKeyPressed(keyIndex: model.glissandoKeyIndex, isPressed: false)
                    model.glissandoKeyIndex = -1
                }
            }
    }

    var body: some View {
        KeyboardLayout {
            GeometryReader { geo in
                let keyboardGeometry = KeyboardGeometry(size: geo.size, pixelLength: pixelLength)
                ZStack {
                    ForEach(keyboardGeometry.whiteKeyIndicies, id: \.self) { i in
                        let keyGeometry = keyboardGeometry.keyGeometries[i]
                        WhiteKeyView(keyboardGeometry: keyboardGeometry, model: model, keyIndex: i)
                            .frame(width: keyGeometry.bottomRight - keyGeometry.bottomLeft, height: keyboardGeometry.whiteKeyLength)
                            .position(x: (keyGeometry.bottomRight + keyGeometry.bottomLeft) / 2, y: keyboardGeometry.gap + keyboardGeometry.whiteKeyLength / 2)
                    }
                    ForEach(keyboardGeometry.blackKeyIndicies, id: \.self) { i in
                        let keyGeometry = keyboardGeometry.keyGeometries[i]
                        BlackKeyView(keyboardGeometry: keyboardGeometry, model: model, keyIndex: i)
                            .frame(width: keyGeometry.bottomRight - keyGeometry.bottomLeft, height: keyboardGeometry.blackKeyLength)
                            .position(x: (keyGeometry.bottomRight + keyGeometry.bottomLeft) / 2, y: keyboardGeometry.gap + keyboardGeometry.blackKeyLength / 2)
                    }
                }
                .background(Color(white: 0.3))
                .gesture(glissandoGesture(keyboardGeometry: keyboardGeometry))
                .frame(width: keyboardGeometry.size.width, height: keyboardGeometry.size.height)
            }
        }
    }
}

private struct KeyboardLayout: Layout {
    @Environment(\.pixelLength) private var pixelLength: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = max(320, proposal.width ?? 0)
        return CGSize(width: width, height: width * KeyboardGeometry.keyboardAspectRatio)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let proposal = ProposedViewSize(width: bounds.size.width, height: bounds.size.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for subview in subviews {
            subview.place(at: center, anchor: .center, proposal: proposal)
        }
    }
}

private struct WhiteKeyShape: Shape {
    let leftNotch: CGFloat
    let rightNotch: CGFloat
    let notchHeight: CGFloat
    let bottomRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()

        if leftNotch > 0 {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + notchHeight))
            path.addLine(to: CGPoint(x: rect.minX + leftNotch, y: rect.minY + notchHeight))
            path.addLine(to: CGPoint(x: rect.minX + leftNotch, y: rect.minY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        }
        if rightNotch > 0 {
            path.addLine(to: CGPoint(x: rect.maxX - rightNotch, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - rightNotch, y: rect.minY + notchHeight))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + notchHeight))
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: bottomRadius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: bottomRadius)
        path.closeSubpath()

        return path
    }
}

private struct WhiteKeyView: View {
    let keyboardGeometry: KeyboardGeometry
    let model: KeyboardModel
    let keyIndex: Int
    @State var state: Bool = false
    var body: some View {
        let keyGeometry = keyboardGeometry.keyGeometries[keyIndex]
        WhiteKeyShape(leftNotch: keyGeometry.topLeft - keyGeometry.bottomLeft, rightNotch: keyGeometry.bottomRight - keyGeometry.topRight, notchHeight: keyboardGeometry.blackKeyLength + keyboardGeometry.gap, bottomRadius: keyboardGeometry.whiteKeyRadius)
            .fill(state ? whiteKeySelectionColor : Color.white)
            .onReceive(model.keyStatePublisher(keyIndex: keyIndex)) { state in
                self.state = state
            }
    }
}

private struct BlackKeyShape: Shape {
    let bottomRadius: CGFloat
    func path(in rect: CGRect) -> Path {
            var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: bottomRadius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: bottomRadius)
        path.closeSubpath()

        return path
    }
}

private struct BlackKeyView: View {
    let keyboardGeometry: KeyboardGeometry
    let model: KeyboardModel
    let keyIndex: Int
    @State var state: Bool = false
    var body: some View {
        BlackKeyShape(bottomRadius: keyboardGeometry.blackKeyRadius)
            .fill(state ? blackKeySelectionColor : Color.black)
            .onReceive(model.keyStatePublisher(keyIndex: keyIndex)) { state in
                self.state = state
            }
    }
}

private let whiteKeySelectionColor = Color(red: 1, green: 0.55, blue: 0.1)
private let blackKeySelectionColor = Color(red: 0.9, green: 0.45, blue: 0)

struct KeyboardView_Previews: PreviewProvider {
    static var previews: some View {
        KeyboardView(model: EchoKeyboardModel())
    }
}
