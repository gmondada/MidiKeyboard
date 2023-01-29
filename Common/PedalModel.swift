//
//  PedalModel.swift
//  MidiKeyboard
//
//  Created by Gabriele Mondada on January 28, 2023.
//  Copyright (c) 2023 Gabriele Mondada.
//  Distributed under the terms of the MIT License.
//

import Foundation
import Combine

struct PedalState: OptionSet {
    let rawValue: Int
    static let damper = PedalState(rawValue: 1 << 0)  // sustain
    static let soft = PedalState(rawValue: 1 << 1)    // una corda
}

protocol PedalModel: AnyObject {
    var pedalStatePublisher: AnyPublisher<PedalState, Never> { get }
    var pedalState: PedalState { get set }
}
