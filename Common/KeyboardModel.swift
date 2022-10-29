//
//  KeyboardModel.swift
//
//  Created by Gabriele Mondada on October 29, 2022.
//  Copyright (c) 2022 Gabriele Mondada.
//  Distributed under the terms of the MIT License.
//

import Foundation
import Combine

protocol KeyboardModel: AnyObject {
    var glissandoKeyIndex: Int { get set }
    func keyStatePublisher(keyIndex: Int) -> AnyPublisher<Bool, Never>
    func isKeyPressed(keyIndex: Int) -> Bool
    func setKeyPressed(keyIndex: Int, isPressed: Bool)
}

class EchoKeyboardModel: KeyboardModel {

    private let states: [CurrentValueSubject<Bool, Never>] = (0..<88).map { _ in CurrentValueSubject<Bool, Never>(false) }

    var glissandoKeyIndex: Int = -1

    func keyStatePublisher(keyIndex: Int) -> AnyPublisher<Bool, Never> {
        return states[keyIndex].eraseToAnyPublisher()
    }

    func isKeyPressed(keyIndex: Int) -> Bool {
        return states[keyIndex].value
    }

    func setKeyPressed(keyIndex: Int, isPressed: Bool) {
        states[keyIndex].value = isPressed
    }
}

class GeneratedScaleKeyboardModel: KeyboardModel {

    private let states: [CurrentValueSubject<Bool, Never>] = (0..<88).map { _ in CurrentValueSubject<Bool, Never>(false) }
    private var timer: Timer!
    private var keyIndex = 0

    var glissandoKeyIndex: Int = -1

    func keyStatePublisher(keyIndex: Int) -> AnyPublisher<Bool, Never> {
        return states[keyIndex].eraseToAnyPublisher()
    }

    func isKeyPressed(keyIndex: Int) -> Bool {
        return states[keyIndex].value
    }

    func setKeyPressed(keyIndex: Int, isPressed: Bool) {
        states[keyIndex].value = isPressed
    }

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true, block: { [weak self] _ in
            self?.tick()
        })
    }

    deinit {
        let timer: Timer = self.timer
        DispatchQueue.main.async {
            timer.invalidate()
        }
    }

    func tick() {
        let previousIndex = (keyIndex + 87) % 88
        states[previousIndex].value = false
        states[keyIndex].value = true
        keyIndex = (keyIndex + 1) % 88
    }
}
