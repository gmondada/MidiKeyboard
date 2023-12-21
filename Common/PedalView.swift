//
//  PedalView.swift
//  MidiKeyboard
//
//  Created by Gabriele Mondada on January 28, 2023.
//  Copyright (c) 2023 Gabriele Mondada.
//  Distributed under the terms of the MIT License.
//

import Foundation
import SwiftUI
import Combine

struct PedalView: View {
    @ObservedObject var model: PedalViewModel

    init(model: PedalModel) {
        self.model = PedalViewModel(model: model)
    }

    var body: some View {
        HStack {
            Toggle("Soft", isOn: $model.softPedal)
            Toggle("Damper", isOn: $model.damperPedal)
        }
        .toggleStyle(.button)
    }
}

class PedalViewModel: ObservableObject {

    private let model: PedalModel
    private var modelSubscription: Cancellable?
    private var beingSetByModel = false

    @Published var damperPedal: Bool = false {
        didSet {
            if !beingSetByModel {
                if damperPedal {
                    model.pedalState.insert(.damper)
                } else {
                    model.pedalState.remove(.damper)
                }
            }
        }
    }

    @Published var softPedal: Bool = false {
        didSet {
            if !beingSetByModel {
                if softPedal {
                    model.pedalState.insert(.soft)
                } else {
                    model.pedalState.remove(.soft)
                }
            }
        }
    }

    init(model: PedalModel) {
        self.model = model
        modelSubscription = model.pedalStatePublisher.sink { [weak self] state in
            if let self {
                self.beingSetByModel = true
                if self.damperPedal != state.contains(.damper) {
                    self.damperPedal = state.contains(.damper)
                }
                if self.softPedal != state.contains(.soft) {
                    self.softPedal = state.contains(.soft)
                }
                self.beingSetByModel = false
            }
        }
    }
}
