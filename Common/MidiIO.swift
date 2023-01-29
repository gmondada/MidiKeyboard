//
//  MidiIO.swift
//
//  Created by Gabriele Mondada on June 20, 2022.
//  Copyright (c) 2022 Gabriele Mondada.
//  Distributed under the terms of the MIT License.
//

import Foundation
import CoreMIDI
import Combine

final class MidiIO {

    struct Message {
        let size: UInt8
        let b0: UInt8
        let b1: UInt8
        let b2: UInt8
        init(_ bytes: UInt8...) {
            size = UInt8(bytes.count)
            switch size {
            case 1:
                b0 = bytes[0]
                b1 = 0
                b2 = 0
            case 2:
                b0 = bytes[0]
                b1 = bytes[1]
                b2 = 0
            case 3:
                b0 = bytes[0]
                b1 = bytes[1]
                b2 = bytes[2]
            default:
                fatalError()
            }
        }
    }

    final class Port {
        /*
         * Each port correspond to a combination of device, entity and extension index.
         * The extension index is needed for accomodating entities having several inputs
         * or outputs, but who knows if they exist.
         * Virtual input and output ports have "VirtualInput" and "VirtualOutput" as device id and
         * their endpoint id as entity id. Their extension index is always 0.
         */

        let io: MidiIO
        let index: Int
        let name: String
        let id: String

        fileprivate let deviceId: String
        fileprivate let entityId: String
        fileprivate let entityExtensionIndex: Int

        // physical or virtual input
        fileprivate var inputEndpointId: String? = nil
        fileprivate var inputEndpoint: MIDIEndpointRef = 0
        fileprivate var inputPort: MIDIPortRef = 0

        // physical output
        fileprivate var outputEndpointId: String? = nil
        fileprivate var outputEndpoint: MIDIEndpointRef = 0
        fileprivate var outputPort: MIDIPortRef = 0

        // virtual output
        fileprivate var virtualOutputEndpoint: MIDIEndpointRef = 0

        init(io: MidiIO, index: Int, deviceId: String, entityId: String, entityExtensionIndex: Int, name: String) {
            self.io = io
            self.index = index
            self.deviceId = deviceId
            self.entityId = entityId
            self.entityExtensionIndex = entityExtensionIndex
            self.name = name
            self.id = entityId + (entityExtensionIndex > 0 ? ".ext\(entityExtensionIndex)" : "")
        }

        fileprivate var isInputEnabled = false {
            didSet {
                if inputPort != 0 && inputEndpoint != 0 {
                    if isInputEnabled && !oldValue {
                        let result = MIDIPortConnectSource(inputPort, inputEndpoint, Unmanaged.passUnretained(self).toOpaque())
                        Util.logError(result)
                    }
                    if !isInputEnabled && oldValue {
                        let result = MIDIPortDisconnectSource(inputPort, inputEndpoint)
                        Util.logError(result)
                    }
                }
            }
        }

        func send(_ msg: Message) {
            var eventList = MIDIEventList()

            if msg.size == 3 {
                eventList.protocol = MIDIProtocolID._1_0
                eventList.numPackets = 1
                eventList.packet.timeStamp = 0 // now
                eventList.packet.wordCount = 1
                eventList.packet.words.0 = 0x20000000 |
                    UInt32(msg.b0) << 16 |
                    UInt32(msg.b1) << 8 |
                    UInt32(msg.b2) << 0
            } else {
                Util.log("output: ignoring unsupported message: ")
                return
            }

            if outputEndpoint != 0 {
                let result = MIDISendEventList(outputPort, outputEndpoint, &eventList)
                Util.logError(result)
            }

            if virtualOutputEndpoint != 0 {
                let result = MIDIReceivedEventList(virtualOutputEndpoint, &eventList)
                Util.logError(result)
            }
        }
    }

    private enum EndpointType {
        case input
        case output
    }

    private let appName: String
    private let controlQueue: DispatchQueue
    private var midiClient: MIDIClientRef = 0
    private let messageSubject = PassthroughSubject<Message, Never>()
    private var badIncomingMessageFormatLogLimit = 10
    private var inputPort: MIDIPortRef = 0
    private let portsSubject = CurrentValueSubject<Array<Port>, Never>([])

    var areInputsEnabled: Bool = false {
        didSet {
            for port in ports {
                if port.inputEndpoint != 0 {
                    port.isInputEnabled = areInputsEnabled
                }
            }
        }
    }

    var ports: [Port] {
        return portsSubject.value
    }

    var portsPublisher: AnyPublisher<[Port], Never> {
        return portsSubject.eraseToAnyPublisher()
    }

    var outputPorts: [Port] {
        return ports.filter { $0.outputEndpoint != 0 || $0.virtualOutputEndpoint != 0 }
    }

    var incomingMessagePublisher: AnyPublisher<Message, Never> {
        areInputsEnabled = true
        return messageSubject.receive(on: controlQueue).eraseToAnyPublisher()
    }

    init(appName: String, controlQueue: DispatchQueue = .main) {
        self.appName = appName
        self.controlQueue = controlQueue
    }

    func open() {
        dispatchPrecondition(condition: .onQueue(controlQueue))
        precondition(midiClient == 0)

        var midiClient: MIDIClientRef = 0
        var result: OSStatus

        result = MIDIClientCreateWithBlock(appName as CFString, &midiClient) { notificationPoiter in
            let messageId = notificationPoiter.pointee.messageID
            let messageSize = notificationPoiter.pointee.messageSize
            switch messageId {
            case .msgObjectAdded, .msgObjectRemoved:
                assert(messageSize >= MemoryLayout<MIDIObjectAddRemoveNotification>.size)
                notificationPoiter.withMemoryRebound(to: MIDIObjectAddRemoveNotification.self, capacity: 1) { ptr in
                    self.onMidiObjectAddRemoveNotification(notification: ptr.pointee)
                }
            default:
                self.onMidiDefaultNotification(notification: notificationPoiter.pointee)
            }
        }
        Util.logError(result)

        if midiClient != 0 {
            self.midiClient = midiClient
            scanForPhysicalPorts()
            scanForVirtualPorts()
        }
    }

    func close() {
        dispatchPrecondition(condition: .onQueue(controlQueue))
        if midiClient == 0 {
            return
        }
        for port in ports {
            port.isInputEnabled = false
            port.inputPort = 0
            if port.outputPort != 0 {
                let result = MIDIPortDispose(port.outputPort)
                Util.logError(result)
                port.outputPort = 0
            }
            if port.virtualOutputEndpoint != 0 {
                let result = MIDIEndpointDispose(port.virtualOutputEndpoint)
                Util.logError(result)
                port.virtualOutputEndpoint = 0
            }
        }
        if inputPort != 0 {
            let result = MIDIPortDispose(inputPort)
            Util.logError(result)
            inputPort = 0
        }
        let result = MIDIClientDispose(midiClient)
        Util.logError(result)
        midiClient = 0
        portsSubject.value.removeAll()
    }

    func createVirtualOutputPort(name: String, fourcc id: String?) {
        dispatchPrecondition(condition: .onQueue(controlQueue))
        precondition(midiClient != 0)

        var outputEndpoint: MIDIEndpointRef = 0
        var result: OSStatus

        result = MIDISourceCreateWithProtocol(midiClient, name as CFString, MIDIProtocolID._1_0, &outputEndpoint)
        Util.logError(result)
        if outputEndpoint == 0 {
            return
        }

        var outputId: Int32 = 0

        if let id = id {
            outputId = Int32(bitPattern: Util.fourcc(id))
        } else {
            result = MIDIObjectGetIntegerProperty(outputEndpoint, kMIDIPropertyUniqueID, &outputId);
            Util.logError(result)
        }

        result = MIDIObjectSetIntegerProperty(outputEndpoint, kMIDIPropertyUniqueID, outputId);
        Util.logError(result)

        // TODO: store fourcc persistently and reuse the same of each session
        // TODO: manage case where fourcc is not unique

        let port = Port(io: self, index: portsSubject.value.count, deviceId: "VirtualOutput", entityId: String(format: "%08x", outputId), entityExtensionIndex: 0, name: name)
        portsSubject.value.append(port)
        port.virtualOutputEndpoint = outputEndpoint
    }

    private func scanForPhysicalPorts() {
        dispatchPrecondition(condition: .onQueue(controlQueue))

        let numOfDevices = MIDIGetNumberOfDevices()
        for deviceIndex in 0 ..< numOfDevices {
            let device = MIDIGetDevice(deviceIndex)
            Util.log("device \(deviceIndex):")
            Util.log("  properties:")
            Util.logObjectProperties(device, "    ");

            guard !device.isIAC else {
                // not yet supported (IAC acts as a loopback)
                continue
            }
            guard let deviceId = device.uniqueId else {
                continue
            }

            let deviceName = device.name ?? "Device \(deviceId)"

            let numOfEntities = MIDIDeviceGetNumberOfEntities(device)
            for entityIndex in 0 ..< numOfEntities {
                let entity = MIDIDeviceGetEntity(device, entityIndex)
                Util.log("  entity \(entityIndex):")
                Util.log("    properties:")
                Util.logObjectProperties(entity, "      ");

                guard let entityId = entity.uniqueId else {
                    continue
                }

                let entityName = entity.name ?? "Entity \(entityId)"

                let numOfSources = MIDIEntityGetNumberOfSources(entity)
                for sourceIndex in 0 ..< numOfSources {
                    let endpoint = MIDIEntityGetSource(entity, sourceIndex)
                    Util.log("    source \(sourceIndex):")
                    Util.log("      properties:")
                    Util.logObjectProperties(endpoint, "        ");

                    guard let endpointId = endpoint.uniqueId else {
                        continue
                    }

                    addOrUpdatePort(deviceId: deviceId, deviceName: deviceName, entityId: entityId, entityName: entityName, endpointId: endpointId, endpointType: .input, endpoint: endpoint)
                }
                let numOfDestinations = MIDIEntityGetNumberOfDestinations(entity)
                for destinationIndex in 0 ..< numOfDestinations {
                    let endpoint = MIDIEntityGetDestination(entity, destinationIndex)
                    Util.log("    destination \(destinationIndex):");
                    Util.log("      properties:");
                    Util.logObjectProperties(endpoint, "        ");

                    guard let endpointId = endpoint.uniqueId else {
                        continue
                    }

                    addOrUpdatePort(deviceId: deviceId, deviceName: deviceName, entityId: entityId, entityName: entityName, endpointId: endpointId, endpointType: .output, endpoint: endpoint)
                }
            }
        }
    }

    private func scanForVirtualPorts() {
        let numOfSources = MIDIGetNumberOfSources()
        for sourceIndex in 0 ..< numOfSources {
            let sourceEndpoint = MIDIGetSource(sourceIndex)
            Util.log("source \(sourceIndex):")
            Util.log("  properties:")
            Util.logObjectProperties(sourceEndpoint, "    ");

            guard let entityId = sourceEndpoint.uniqueId else {
                continue
            }

            let entityName = sourceEndpoint.name ?? "Source \(entityId)"

            guard !ports.contains(where: { $0.deviceId == "VirtualOutput" && $0.entityId == entityId }) else {
                continue
            }

            let port: Port
            if let foundPort = ports.first(where: { $0.deviceId == "VirtualInput" && $0.entityId == entityId }) {
                if foundPort.inputEndpoint != sourceEndpoint {
                    port = foundPort
                    // disabling previous endpoint results in an error
                    // MIDIPortDisconnectSource(port.inputPort, port.inputEndpoint)
                    port.inputEndpoint = 0
                    port.isInputEnabled = false
                    port.inputEndpoint = sourceEndpoint
                    if areInputsEnabled {
                        port.isInputEnabled = true
                    }
                }
            } else {
                port = Port(io: self, index: portsSubject.value.count, deviceId: "VirtualInput", entityId: entityId, entityExtensionIndex: 0, name: entityName)
                portsSubject.value.append(port)
                port.inputEndpointId = entityId
                port.inputEndpoint = sourceEndpoint
                createInputPort()
                port.inputPort = self.inputPort
                if areInputsEnabled {
                    port.isInputEnabled = true
                }
            }
        }
    }

    private func createInputPort() {
        dispatchPrecondition(condition: .onQueue(controlQueue))

        if inputPort != 0 {
            return
        }

        let result = MIDIInputPortCreateWithProtocol(midiClient, "Input" as CFString, MIDIProtocolID._1_0, &inputPort) {
            (eventList: UnsafePointer<MIDIEventList>, srcConnRefCon: UnsafeMutableRawPointer?) in
            // called on a separate high-priority thread owned by CoreMIDI

            let port = Unmanaged<Port>.fromOpaque(srcConnRefCon!).takeUnretainedValue()
            var packet = withUnsafeMutablePointer(to: &UnsafeMutablePointer(mutating: eventList).pointee.packet) { $0 }

            for _ in 0..<eventList.pointee.numPackets {

                if packet.pointee.wordCount == 1 && (packet.pointee.words.0 >> 24) == 0x20 {
                    let word: UInt32 = packet.pointee.words.0
                    let message = MidiIO.Message(
                        UInt8(truncatingIfNeeded: word >> 16),
                        UInt8(truncatingIfNeeded: word >> 8),
                        UInt8(truncatingIfNeeded: word >> 0)
                    )

                    port.io.messageSubject.send(message)

                } else {
                    if port.io.badIncomingMessageFormatLogLimit > 0 {
                        port.io.badIncomingMessageFormatLogLimit -= 1
                        var msg = "unsupported message format: wordCount=\(packet.pointee.wordCount)"
                        if packet.pointee.wordCount > 0 {
                            msg += String(format: "word[0]=0x%x", UInt(packet.pointee.words.0))
                        }
                        Util.log(msg)
                    }
                }

                packet = MIDIEventPacketNext(packet)
            }
        }
        Util.logError(result)
    }

    private func addOrUpdatePort(deviceId: String, deviceName: String, entityId: String, entityName: String, endpointId: String, endpointType: EndpointType, endpoint: MIDIEndpointRef) {
        dispatchPrecondition(condition: .onQueue(controlQueue))

        let entityExtensions = portsSubject.value.compactMap {
            if $0.deviceId == deviceId && $0.entityId == entityId {
                return $0
            } else {
                return nil
            }
        }

        if entityExtensions.contains(where: { $0.inputEndpointId == endpointId || $0.outputEndpointId == endpointId }) {
            // endpoint already present - do nothing
        } else if endpointType == .input, let index = entityExtensions.firstIndex(where: { $0.inputEndpointId == nil }) {
            // add the input endpoint to an existing port
            let port = entityExtensions[index]
            port.inputEndpointId = endpointId
            port.inputEndpoint = endpoint
            createInputPort()
            port.inputPort = self.inputPort
            if areInputsEnabled {
                port.isInputEnabled = true
            }
        } else if endpointType == .output, let index = entityExtensions.firstIndex(where: { $0.outputEndpointId == nil }) {
            // add the output endpoint to an existing port
            let port = entityExtensions[index]
            port.outputEndpointId = endpointId
            port.outputEndpoint = endpoint
            var outputPort: MIDIPortRef = 0
            let result = MIDIOutputPortCreate(midiClient, "Output" as CFString, &outputPort);
            Util.logError(result)
            port.outputPort = outputPort
        } else {
            // create a new port (entity extension)
            var name = deviceName
            if entityName != deviceName {
                name += " - " + entityName
            }
            if entityExtensions.count > 0 {
                name += " - " + "Extension \(entityExtensions.count)"
            }
            let port = Port(io: self, index: portsSubject.value.count, deviceId: deviceId, entityId: entityId, entityExtensionIndex: entityExtensions.count, name: name)
            portsSubject.value.append(port)
            addOrUpdatePort(deviceId: deviceId, deviceName: deviceName, entityId: entityId, entityName: entityName, endpointId: endpointId, endpointType: endpointType, endpoint: endpoint)
        }
    }

    private func onMidiDefaultNotification(notification: MIDINotification) {
        Util.log("notification: type=\(Util.midiNotificationMessageIDToString(notification.messageID))")
        controlQueue.async {
            self.requestPortRefresh()
        }
    }

    private func onMidiObjectAddRemoveNotification(notification: MIDIObjectAddRemoveNotification) {
        Util.log("notification:")
        Util.log("  type: \(Util.midiNotificationMessageIDToString(notification.messageID))")
        Util.log("  parentType: \(Util.midiObjectTypeToString(notification.parentType))")
        Util.log("  parentRef: \(notification.parent)")
        Util.log("  parentUniqueId: \(notification.parent.uniqueId ?? "<nil>")")
        Util.log("  childType: \(Util.midiObjectTypeToString(notification.childType))")
        Util.log("  childRef: \(notification.child)")
        Util.log("  childUniqueId: \(notification.child.uniqueId ?? "<nil>")")
        controlQueue.async {
            self.requestPortRefresh()
        }
    }

    private var portRefreshRequestCount = 0

    private func requestPortRefresh() {
        dispatchPrecondition(condition: .onQueue(controlQueue))
        portRefreshRequestCount += 1
        controlQueue.asyncAfter(deadline: .now() + 0.5) {
            self.portRefreshRequestCount -= 1
            if self.portRefreshRequestCount == 0 && self.midiClient != 0 {
                self.scanForPhysicalPorts()
                self.scanForVirtualPorts()
                for port in self.ports {
                    Util.log("port index=\(port.index) id=\(port.id) name=\"\(port.name)\"")
                }
            }
        }
    }
}

private extension MIDIObjectRef {

    var uniqueId: String? {
        var id: Int32 = 0
        let result = MIDIObjectGetIntegerProperty(self, kMIDIPropertyUniqueID, &id);
        if result == noErr {
            return String(format: "%08x", id)
        } else {
            return nil
        }
    }

    var name: String? {
        var unmanagedProperties: Unmanaged<CFPropertyList>? = nil
        MIDIObjectGetProperties(self, &unmanagedProperties, false)
        let properties = unmanagedProperties?.takeRetainedValue()
        if let dictionary = properties as? [String:Any?],
            let name = dictionary[kMIDIPropertyName as String] as? String {
            return name
        } else {
            return nil
        }
    }

    var isIAC: Bool {
        var unmanagedProperties: Unmanaged<CFPropertyList>? = nil
        MIDIObjectGetProperties(self, &unmanagedProperties, false)
        let properties = unmanagedProperties?.takeRetainedValue()
        if let dictionary = properties as? [String:Any?],
            let name = dictionary[kMIDIPropertyDriverOwner as String] as? String {
            return name == "com.apple.AppleMIDIIACDriver"
        } else {
            return false
        }
    }
}

private struct Util {
    static func log(_ msg: String) {
        print("MidiIO: \(msg)")
    }

    static func logObjectProperties(_ object: MIDIObjectRef, _ indent: String) {
        Util.log("\(indent)<ref>: \(object)")
        var unmanagedProperties: Unmanaged<CFPropertyList>? = nil
        MIDIObjectGetProperties(object, &unmanagedProperties, false)
        let properties = unmanagedProperties?.takeRetainedValue()
        if let dictionary = properties as? [String:Any?] {
            for (key, value) in dictionary {
                if let value = value {
                    if let intValue = value as? Int32, key == (kMIDIPropertyUniqueID as String) {
                        Util.log("\(indent)\(key): \(value) (\(String(format: "%08x", intValue)))")
                    } else {
                        Util.log("\(indent)\(key): \(value)")
                    }
                } else {
                    Util.log("\(indent)\(key): <nil>")
                }
            }
        }
    }

    static func logError(_ result: OSStatus, file: String = #fileID, line: Int = #line, message: String? = nil) {
        if result != noErr {
            Util.log("ERROR: result=\(result) location=\(file):\(line) message=\(message == nil ? "<nil>" : "\"\(message!)\"")")
            assertionFailure()
        }
    }

    static func fourcc(_ string: String) -> UInt32 {
        let utf8 = string.utf8
        precondition(utf8.count == 4)
        let i1 = utf8.startIndex
        let i2 = utf8.index(after: i1)
        let i3 = utf8.index(after: i2)
        let i4 = utf8.index(after: i3)
        let c1: UInt8 = utf8[i1]
        let c2: UInt8 = utf8[i2]
        let c3: UInt8 = utf8[i3]
        let c4: UInt8 = utf8[i4]
        return UInt32(c1) << 24
             | UInt32(c2) << 16
             | UInt32(c3) << 8
             | UInt32(c4) << 0
    }

    static func midiNotificationMessageIDToString(_ id: MIDINotificationMessageID) -> String {
        switch id {
        case .msgSetupChanged:           return "msgSetupChanged"
        case .msgObjectAdded:            return "msgObjectAdded"
        case .msgObjectRemoved:          return "msgObjectRemoved"
        case .msgPropertyChanged:        return "msgPropertyChanged"
        case .msgThruConnectionsChanged: return "msgThruConnectionsChanged"
        case .msgSerialPortOwnerChanged: return "msgSerialPortOwnerChanged"
        case .msgIOError:                return "msgIOError"
        default:                         return "<unknown-msg-id-\(id)>"
        }
    }

    static func midiObjectTypeToString(_ type: MIDIObjectType) -> String {
        switch type {
        case .other:               return "other"
        case .device:              return "device"
        case .entity:              return "entity"
        case .source:              return "source"
        case .destination:         return "destination"
        case .externalDevice:      return "externalDevice"
        case .externalEntity:      return "externalEntity"
        case .externalSource:      return "externalSource"
        case .externalDestination: return "externalDestination"
        default:                   return "<unknown-type-\(type)>"
        }
    }
}
