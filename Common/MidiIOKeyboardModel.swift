//
//  MidiIOKeyboardModel.swift
//
//  Created by Gabriele Mondada on October 29, 2022.
//  Copyright (c) 2022 Gabriele Mondada.
//  Distributed under the terms of the MIT License.
//

import Foundation
import Combine

class MidiIOKeyboardModel: KeyboardModel, PedalModel {
    private let io: MidiIO
    private let states: [CurrentValueSubject<Bool, Never>] = (0..<88).map { _ in CurrentValueSubject<Bool, Never>(false) }
    private let pedalStateSubject = CurrentValueSubject<PedalState, Never>([])
    private var cancellables: [Cancellable] = []

    init() {
        io = MidiIO(appName: "Midi Keyboard App")
        io.open()
        #if os(macOS)
        io.createVirtualOutputPort(name: "Midi Keyboard App", fourcc: "oilu")
        #endif
        let cancellable = io.incomingMessagePublisher.sink { [weak self] message in
            self?.onIncomingMidiMessage(message)
        }
        cancellables.append(cancellable)
    }

    deinit {
        let io = self.io
        DispatchQueue.main.async {
            io.close()
        }
    }

    private func onIncomingMidiMessage(_ message: MidiIO.Message) {
        if message.size == 3 {
            let cmd = (message.b0 >> 4) & 0x0F
            // let channel = message.b0 & 0x0F
            let note = message.b1 & 0x7F
            let vel = message.b2
            let noteOn = ((cmd == 9) && (vel != 0))
            let noteOff = ((cmd == 8) || ((cmd == 9) && (vel == 0)))
            let controlChange = cmd == 11
            let keyIndex = Int(note) + 3 - 24

            if noteOn && keyIndex >= 0 && keyIndex < 88 && !self.states[keyIndex].value {
                self.states[keyIndex].value = true
            }
            if noteOff && keyIndex >= 0 && keyIndex < 88 && self.states[keyIndex].value {
                self.states[keyIndex].value = false
            }

            if controlChange && note == 0x40 {
                let damper = vel != 0
                if pedalStateSubject.value.contains(.damper) {
                    if !damper {
                        pedalStateSubject.value.remove(.damper)
                    }
                } else {
                    if damper {
                        pedalStateSubject.value.insert(.damper)
                    }
                }
            }
            if controlChange && note == 0x43 {
                let soft = vel != 0
                if pedalStateSubject.value.contains(.soft) {
                    if !soft {
                        pedalStateSubject.value.remove(.soft)
                    }
                } else {
                    if soft {
                        pedalStateSubject.value.insert(.soft)
                    }
                }
            }
        }
    }

    // MARK: - KeyboardModel

    var glissandoKeyIndex: Int = -1

    func keyStatePublisher(keyIndex: Int) -> AnyPublisher<Bool, Never> {
        return states[keyIndex].eraseToAnyPublisher()
    }

    func isKeyPressed(keyIndex: Int) -> Bool {
        return states[keyIndex].value
    }

    func setKeyPressed(keyIndex: Int, isPressed: Bool) {
        if states[keyIndex].value != isPressed {
            states[keyIndex].value = isPressed
            let midiNote = keyIndex - 3 + 24
            let msg = MidiIO.Message(0x90, UInt8(midiNote), isPressed ? 0x40 : 0)
            for port in io.outputPorts {
                port.send(msg)
            }
        }
    }

    // MARK: - PedalModel

    var pedalStatePublisher: AnyPublisher<PedalState, Never> {
        return pedalStateSubject.eraseToAnyPublisher()
    }

    var pedalState: PedalState {
        get {
            return pedalStateSubject.value
        }
        set {
            setPedalState(newValue)
        }
    }

    private func setPedalState(_ state: PedalState) {
        let damper = state.contains(.damper)
        let soft = state.contains(.soft)
        if pedalStateSubject.value.contains(.damper) {
            if !damper {
                pedalStateSubject.value.remove(.damper)
                let msg = MidiIO.Message(0xb0, 0x40, 0)
                for port in io.outputPorts {
                    port.send(msg)
                }
            }
        } else {
            if damper {
                pedalStateSubject.value.insert(.damper)
                let msg = MidiIO.Message(0xb0, 0x40, 127)
                for port in io.outputPorts {
                    port.send(msg)
                }
            }
        }
        if pedalStateSubject.value.contains(.soft) {
            if !soft {
                pedalStateSubject.value.remove(.soft)
                let msg = MidiIO.Message(0xb0, 0x43, 0)
                for port in io.outputPorts {
                    port.send(msg)
                }
            }
        } else {
            if soft {
                pedalStateSubject.value.insert(.soft)
                let msg = MidiIO.Message(0xb0, 0x43, 127)
                for port in io.outputPorts {
                    port.send(msg)
                }
            }
        }
    }
}
