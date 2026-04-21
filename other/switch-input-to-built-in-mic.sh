#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Switch Input to Built-in Mic
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🎙️

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Switches the default input from a Bluetooth device to the built-in microphone

swift - <<'SWIFT'
import Foundation
import CoreAudio

struct InputDevice {
    let id: AudioDeviceID
    let name: String
    let transportType: UInt32
}

func fail(_ message: String, status: OSStatus? = nil) -> Never {
    if let status {
        fputs("\(message) (\(status))\n", stderr)
    } else {
        fputs("\(message)\n", stderr)
    }
    exit(1)
}

func check(_ status: OSStatus, _ message: String) {
    if status != noErr {
        fail(message, status: status)
    }
}

func transportName(for transportType: UInt32) -> String {
    switch transportType {
    case kAudioDeviceTransportTypeBuiltIn:
        return "Built-in"
    case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
        return "Bluetooth"
    case kAudioDeviceTransportTypeUSB:
        return "USB"
    case kAudioDeviceTransportTypeAirPlay:
        return "AirPlay"
    case kAudioDeviceTransportTypeContinuityCaptureWired,
         kAudioDeviceTransportTypeContinuityCaptureWireless:
        return "Continuity"
    default:
        return "Other"
    }
}

func propertyDataSize(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> UInt32 {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    check(AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size), "Could not read audio property size")
    return size
}

func stringProperty(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
    let pointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
    pointer.initialize(to: nil)
    defer {
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }

    var size = UInt32(MemoryLayout<CFString?>.size)
    check(AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer), "Could not read audio string property")
    return (pointer.pointee as String?) ?? "Unknown"
}

func uint32Property(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> UInt32 {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    check(AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value), "Could not read audio integer property")
    return value
}

func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )

    guard AudioObjectHasProperty(deviceID, &address) else {
        return false
    }

    let size = propertyDataSize(
        objectID: deviceID,
        selector: kAudioDevicePropertyStreams,
        scope: kAudioObjectPropertyScopeInput
    )

    return size >= UInt32(MemoryLayout<AudioStreamID>.size)
}

func inputDevices() -> [InputDevice] {
    let size = propertyDataSize(
        objectID: AudioObjectID(kAudioObjectSystemObject),
        selector: kAudioHardwarePropertyDevices
    )

    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)
    var mutableSize = size
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    check(
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &mutableSize,
            &deviceIDs
        ),
        "Could not read audio devices"
    )

    return deviceIDs.compactMap { deviceID in
        guard hasInputStreams(deviceID) else {
            return nil
        }

        return InputDevice(
            id: deviceID,
            name: stringProperty(objectID: deviceID, selector: kAudioObjectPropertyName),
            transportType: uint32Property(objectID: deviceID, selector: kAudioDevicePropertyTransportType)
        )
    }
}

func defaultInputDevice() -> InputDevice {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)

    check(
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ),
        "Could not read current input device"
    )

    return InputDevice(
        id: deviceID,
        name: stringProperty(objectID: deviceID, selector: kAudioObjectPropertyName),
        transportType: uint32Property(objectID: deviceID, selector: kAudioDevicePropertyTransportType)
    )
}

func targetScore(for device: InputDevice) -> Int {
    let lowercasedName = device.name.lowercased()
    var score = 0

    if lowercasedName.contains("microphone") {
        score += 4
    }
    if lowercasedName.contains("macbook") {
        score += 2
    }
    if lowercasedName.contains("built-in") {
        score += 1
    }

    return score
}

func preferredBuiltInInput(from devices: [InputDevice]) -> InputDevice? {
    return devices
        .filter { $0.transportType == kAudioDeviceTransportTypeBuiltIn }
        .sorted {
            let leftScore = targetScore(for: $0)
            let rightScore = targetScore(for: $1)

            if leftScore == rightScore {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            return leftScore > rightScore
        }
        .first
}

func setDefaultInputDevice(_ deviceID: AudioDeviceID) {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var mutableDeviceID = deviceID
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)

    check(
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &mutableDeviceID
        ),
        "Could not switch input device"
    )
}

let currentInput = defaultInputDevice()
let devices = inputDevices()

guard let targetInput = preferredBuiltInInput(from: devices) else {
    fail("No built-in input device was found")
}

if currentInput.id == targetInput.id {
    print("Input is already \(targetInput.name) (\(transportName(for: targetInput.transportType)))")
    exit(0)
}

setDefaultInputDevice(targetInput.id)

print(
    "Switched input from \(currentInput.name) (\(transportName(for: currentInput.transportType))) " +
    "to \(targetInput.name) (\(transportName(for: targetInput.transportType)))"
)
SWIFT
