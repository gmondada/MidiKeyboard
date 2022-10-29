//
//  MidiKeyboardApp_macOS.swift
//
//  Created by Gabriele Mondada on October 29, 2022.
//  Copyright (c) 2022 Gabriele Mondada.
//  Distributed under the terms of the MIT License.
//

import SwiftUI

@main
struct MidiKeyboardApp: App {
    var body: some Scene {
        WindowGroup {
            KeyboardView(model: MidiIOKeyboardModel())
        }
    }
}
