//
//  KeyboardGeometry.swift
//
//  Created by Gabriele Mondada on October 29, 2022.
//  Copyright (c) 2022 Gabriele Mondada.
//  Distributed under the terms of the MIT License.
//

import Foundation

class KeyboardGeometry {

    struct KeyGeometry {
        var isBlack: Bool = false
        var topLeft: CGFloat = 0
        var topRight: CGFloat = 0
        var bottomLeft: CGFloat = 0
        var bottomRight: CGFloat = 0
    }

    private let rawWhiteKeyWidth: CGFloat

    let keyCount = 88
    let whiteKeyCount = 7 * 7 + 3
    let blackKeyCount = 7 * 5 + 1
    let pixelLength: CGFloat
    let gap: CGFloat
    let size: CGSize  // gaps included
    let whiteKeyLength: CGFloat // gaps not included
    let blackKeyLength: CGFloat // gaps not included
    let whiteKeyRadius: CGFloat
    let blackKeyRadius: CGFloat

    let keyGeometries: [KeyGeometry]
    let whiteKeyIndicies: [Int]
    let blackKeyIndicies: [Int]

    init(keyboardWidth width: CGFloat, pixelLength: CGFloat) {
        // see: https://datagenetics.com/blog/may32016/index.html
        // see: http://www.quadibloc.com/other/cnv05.htm

        assert(keyCount == whiteKeyCount + blackKeyCount)

        self.pixelLength = pixelLength
        let align = {(x: CGFloat) -> CGFloat in
            if pixelLength == 0 {
                return x
            } else {
                return round(x / pixelLength) * pixelLength
            }
        }

        let keyboardWidth = max(CGFloat(keyCount) * 5 * pixelLength, width)
        gap = max(pixelLength, align(keyboardWidth / 1000))
        rawWhiteKeyWidth = (keyboardWidth - gap) / CGFloat(whiteKeyCount)
        let rawBlackKeyWidth = rawWhiteKeyWidth * 14.0 / 24.0
        let rawBlackKeyDistance = rawBlackKeyWidth
        let rawWhiteKeyLength = rawWhiteKeyWidth * 5.25
        let rawBlackKeyLength = rawWhiteKeyLength * 0.65
        let blackKeyWidth = align(rawBlackKeyWidth)
        let blackKeyDistance = align(rawBlackKeyDistance)
        whiteKeyLength = align(rawWhiteKeyLength)
        blackKeyLength = align(rawBlackKeyLength)
        size = CGSize(width: align(keyboardWidth), height: whiteKeyLength + 2 * gap)

        var keyGeometries: [KeyGeometry] = .init(repeating: KeyGeometry(), count: 88)

        for i in 0..<7 {
            let mid2 = 0.5 * gap + rawWhiteKeyWidth * (3.5 + 7 * CGFloat(i))
            let left2 = align(mid2 - 0.5 * blackKeyDistance - blackKeyWidth)
            keyGeometries[4 + 12 * i].isBlack = true
            keyGeometries[4 + 12 * i].topLeft = left2
            keyGeometries[4 + 12 * i].bottomLeft = left2
            keyGeometries[4 + 12 * i].topRight = left2 + blackKeyWidth
            keyGeometries[4 + 12 * i].bottomRight = left2 + blackKeyWidth
            keyGeometries[6 + 12 * i].isBlack = true
            keyGeometries[6 + 12 * i].topLeft = left2 + blackKeyWidth + blackKeyDistance
            keyGeometries[6 + 12 * i].bottomLeft = left2 + blackKeyWidth + blackKeyDistance
            keyGeometries[6 + 12 * i].topRight = left2 + 2 * blackKeyWidth + blackKeyDistance
            keyGeometries[6 + 12 * i].bottomRight = left2 + 2 * blackKeyWidth + blackKeyDistance
        }

        for i in -1..<7 {
            let mid3 = 0.5 * gap + rawWhiteKeyWidth * (7 + 7 * CGFloat(i))
            let left3 = align(mid3 - 1.5 * blackKeyWidth - blackKeyDistance)
            if i >= 0 {
                keyGeometries[9 + 12 * i].isBlack = true
                keyGeometries[9 + 12 * i].topLeft = left3
                keyGeometries[9 + 12 * i].bottomLeft = left3
                keyGeometries[9 + 12 * i].topRight = left3 + blackKeyWidth
                keyGeometries[9 + 12 * i].bottomRight = left3 + blackKeyWidth
                keyGeometries[11 + 12 * i].isBlack = true
                keyGeometries[11 + 12 * i].topLeft = left3 + blackKeyWidth + blackKeyDistance
                keyGeometries[11 + 12 * i].bottomLeft = left3 + blackKeyWidth + blackKeyDistance
                keyGeometries[11 + 12 * i].topRight = left3 + 2 * blackKeyWidth + blackKeyDistance
                keyGeometries[11 + 12 * i].bottomRight = left3 + 2 * blackKeyWidth + blackKeyDistance
            }
            keyGeometries[13 + 12 * i].isBlack = true
            keyGeometries[13 + 12 * i].topLeft = left3 + 2 * blackKeyWidth + 2 * blackKeyDistance
            keyGeometries[13 + 12 * i].bottomLeft = left3 + 2 * blackKeyWidth + 2 * blackKeyDistance
            keyGeometries[13 + 12 * i].topRight = left3 + 3 * blackKeyWidth + 2 * blackKeyDistance
            keyGeometries[13 + 12 * i].bottomRight = left3 + 3 * blackKeyWidth + 2 * blackKeyDistance
        }

        let whiteKeyIndicies: [Int] = keyGeometries.enumerated().compactMap { !$0.element.isBlack ? $0.offset : nil }
        let blackKeyIndicies: [Int] = keyGeometries.enumerated().compactMap { $0.element.isBlack ? $0.offset : nil }

        for (whiteIndex, index) in whiteKeyIndicies.enumerated() {
            let left = align(gap + rawWhiteKeyWidth * CGFloat(whiteIndex))
            let right = align(gap + rawWhiteKeyWidth * CGFloat(whiteIndex + 1)) - gap
            keyGeometries[index].bottomLeft = left
            keyGeometries[index].bottomRight = right
        }

        for index in 0..<keyCount {
            if !keyGeometries[index].isBlack && index - 1 >= 0 && keyGeometries[index - 1].isBlack {
                keyGeometries[index].topLeft = keyGeometries[index - 1].topRight + gap
            } else {
                keyGeometries[index].topLeft = keyGeometries[index].bottomLeft
            }
            if !keyGeometries[index].isBlack && index + 1 < keyCount && keyGeometries[index + 1].isBlack {
                keyGeometries[index].topRight = keyGeometries[index + 1].topLeft - gap
            } else {
                keyGeometries[index].topRight = keyGeometries[index].bottomRight
            }
        }

        self.keyGeometries = keyGeometries
        self.whiteKeyIndicies = whiteKeyIndicies
        self.blackKeyIndicies = blackKeyIndicies
        self.whiteKeyRadius = rawWhiteKeyWidth * 0.1
        self.blackKeyRadius = rawBlackKeyWidth * 0.18
    }

    func keyIndex(at location: CGPoint) -> Int {
        if location.y >= 1.5 * gap + blackKeyLength {
            // bottom side - it's a white key
            let whiteKeyIndex = Int(floor((location.x - gap) / rawWhiteKeyWidth))
            return whiteKeyIndicies[max(0, min(whiteKeyIndicies.count - 1, whiteKeyIndex))]
        } else {
            // top side - dichotomous search across all keys
            var min = 0
            var max = keyCount - 1 // included
            // min could become greather than max if there is some gap between key boundaries due to rounding errors
            while min < max {
                let mid = (min + max) / 2
                let geometry = keyGeometries[mid]
                let left = geometry.topLeft - 0.5 * gap
                let right = geometry.topRight + 0.5 * gap
                if location.x < left {
                    max = mid - 1
                } else if location.x >= right {
                    min = mid + 1
                } else {
                    min = mid
                    max = mid
                }
            }
            return min
        }
    }
}
