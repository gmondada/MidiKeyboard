//
//  MidiKeyboardApp_iOS.swift
//
//  Created by Gabriele Mondada on October 29, 2022.
//  Copyright (c) 2022 Gabriele Mondada.
//  Distributed under the terms of the MIT License.
//

import SwiftUI

@main
struct MidiKeyboardApp: App {

    let keyboardModel = MidiIOKeyboardModel()

    var body: some Scene {
        WindowGroup {
            VStack {
                PedalView(model: keyboardModel)
                KeyboardView(model: keyboardModel)
            }
        }
    }
}
