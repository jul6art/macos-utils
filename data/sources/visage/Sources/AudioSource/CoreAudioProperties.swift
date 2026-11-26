import CoreAudio
import Foundation

/// A Core Audio call that did not return `noErr`.
public struct CoreAudioError: Error, CustomStringConvertible, Sendable {
    public let operation: String
    public let status: OSStatus

    public var description: String { "\(operation) failed: \(fourCharacterCode(status))" }
}

/// An OSStatus as its four-character code when it has one ('!dev', 'nope'…), as a number otherwise.
func fourCharacterCode(_ status: OSStatus) -> String {
    let value = UInt32(bitPattern: status)
    let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
    guard bytes.allSatisfy({ (32..<127).contains($0) }) else { return String(status) }
    return "'" + String(decoding: bytes, as: UTF8.self) + "'"
}

func check(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
    guard status == noErr else { throw CoreAudioError(operation: operation(), status: status) }
}

func propertyAddress(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

private func selectorName(_ selector: AudioObjectPropertySelector) -> String {
    fourCharacterCode(OSStatus(bitPattern: selector))
}

/// Reads a fixed-size property.
func readProperty<Value>(
    _ object: AudioObjectID,
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    initial: Value
) throws -> Value {
    var address = propertyAddress(selector, scope: scope)
    var value = initial
    var size = UInt32(MemoryLayout<Value>.size)
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
    }
    try check(status, "reading \(selectorName(selector))")
    return value
}

/// Reads a variable-size array property.
func readArrayProperty<Element>(
    _ object: AudioObjectID,
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    filler: Element
) throws -> [Element] {
    var address = propertyAddress(selector, scope: scope)
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size), "sizing \(selectorName(selector))")
    var elements = [Element](repeating: filler, count: Int(size) / MemoryLayout<Element>.stride)
    guard !elements.isEmpty else { return [] }
    let status = elements.withUnsafeMutableBufferPointer { buffer in
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer.baseAddress!)
    }
    try check(status, "reading \(selectorName(selector))")
    return Array(elements.prefix(Int(size) / MemoryLayout<Element>.stride))
}

/// Reads a CFString property. Core Audio hands over a retained reference.
func readStringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
    var address = propertyAddress(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value), "reading \(selectorName(selector))")
    return value.map { $0.takeRetainedValue() as String } ?? ""
}

let systemObject = AudioObjectID(kAudioObjectSystemObject)

func defaultOutputDevice() throws -> AudioObjectID {
    try readProperty(
        systemObject, kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(kAudioObjectUnknown))
}
