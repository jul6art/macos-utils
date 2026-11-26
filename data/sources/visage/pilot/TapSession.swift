import CoreAudio
import Foundation
import Synchronization

/// What the tap captures.
struct TapTarget: Sendable {
    /// The process objects to tap, as they exist now.
    var processObjects: [AudioObjectID] = []
    /// macOS 26: the bundle IDs to tap. Core Audio restores them when the app quits and comes back.
    var bundleIDs: [String] = []
}

/// One capture: a muted tap on the target, an aggregate device that pairs the tap with the default
/// output, and a single IOProc that writes the captured audio into a ring buffer and plays it back
/// `delay` later. Capture and playback run on the aggregate device's clock: they cannot drift apart.
///
/// The IOProc runs on a real-time thread: it never allocates, never locks, and only talks to the
/// rest of the app through the atomics and the two buffers allocated once in `init`.
final class TapSession: @unchecked Sendable {
    private(set) var tapUID = ""
    private(set) var tapFormat = AudioStreamBasicDescription()
    private(set) var sampleRate: Double = 48_000
    private(set) var bufferFrames: UInt32 = 0
    private(set) var outputDeviceName = ""
    /// Device latency + safety offset + stream latency of the output: the time between the IOProc
    /// handing a frame over and the speaker playing it.
    private(set) var outputLatencyFrames: UInt32 = 0

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var overloadListener: AudioObjectPropertyListenerBlock?

    // Real-time state.
    private static let ringSeconds = 2.0
    private static let maximumSampleRate = 192_000.0
    private let ringCapacity = Int(TapSession.ringSeconds * TapSession.maximumSampleRate)
    private let ring: UnsafeMutablePointer<Float>
    private var ringFrames = 0
    private(set) var hopFrames = 480
    private let energySlots = 4096
    private let energies: UnsafeMutablePointer<Float>
    private var hopSum: Float = 0
    private var hopFill = 0

    private let delayFrames = Atomic<Int>(0)
    private let writtenFrames = Atomic<Int>(0)
    private let completedHops = Atomic<Int>(0)
    private let outputStartFrame = Atomic<Int>(0)
    private let outputHostTime = Atomic<UInt64>(0)
    let callbacks = Atomic<Int>(0)
    let overloads = Atomic<Int>(0)
    let frameMismatches = Atomic<Int>(0)
    /// Recorded on the first callback: buffers × 100 + channels of the last input buffer / first output buffer.
    let inputLayout = Atomic<Int>(-1)
    let outputLayout = Atomic<Int>(-1)
    let framesPerCallback = Atomic<Int>(0)

    init() {
        ring = .allocate(capacity: 2 * ringCapacity)
        ring.initialize(repeating: 0, count: 2 * ringCapacity)
        energies = .allocate(capacity: energySlots)
        energies.initialize(repeating: 0, count: energySlots)
    }

    deinit {
        stop()
        ring.deallocate()
        energies.deallocate()
    }

    // MARK: - Setup

    func start(target: TapTarget, privateTap: Bool, delayMilliseconds: Int) throws {
        do {
            try createTap(target: target, privateTap: privateTap)
            try createAggregateDevice()
            setDelay(milliseconds: delayMilliseconds)
            try startIO()
        } catch {
            stop()
            throw error
        }
    }

    private func createTap(target: TapTarget, privateTap: Bool) throws {
        let description = CATapDescription(__stereoMixdownOfProcesses: target.processObjects.map { NSNumber(value: $0) })
        if !target.bundleIDs.isEmpty {
            description.bundleIDs = target.bundleIDs
            description.isProcessRestoreEnabled = true
        }
        description.name = "Visage pilot"
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = privateTap

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "creating the process tap")
        tapID = tap
        tapUID = try readStringProperty(tap, kAudioTapPropertyUID)
        tapFormat = try readProperty(tap, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
    }

    private func createAggregateDevice() throws {
        let output = try defaultOutputDevice()
        let outputUID = try readStringProperty(output, kAudioDevicePropertyDeviceUID)
        outputDeviceName = (try? readStringProperty(output, kAudioObjectPropertyName)) ?? outputUID

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Visage pilot",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tapUID]],
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate), "creating the aggregate device")
        aggregateID = aggregate

        sampleRate = try readProperty(aggregate, kAudioDevicePropertyNominalSampleRate, initial: Float64(0))
        guard sampleRate > 0, sampleRate <= Self.maximumSampleRate else {
            throw CoreAudioError(operation: "unsupported sample rate \(sampleRate)", status: kAudioHardwareUnsupportedOperationError)
        }
        ringFrames = Int(Self.ringSeconds * sampleRate)
        hopFrames = Int(sampleRate / 100)
        bufferFrames = (try? readProperty(aggregate, kAudioDevicePropertyBufferFrameSize, initial: UInt32(0))) ?? 0

        let scope = kAudioObjectPropertyScopeOutput
        let deviceLatency = (try? readProperty(output, kAudioDevicePropertyLatency, scope: scope, initial: UInt32(0))) ?? 0
        let safetyOffset = (try? readProperty(output, kAudioDevicePropertySafetyOffset, scope: scope, initial: UInt32(0))) ?? 0
        let streams = (try? readArrayProperty(output, kAudioDevicePropertyStreams, scope: scope, filler: AudioObjectID(0))) ?? []
        let streamLatency = streams.first.flatMap { try? readProperty($0, kAudioStreamPropertyLatency, initial: UInt32(0)) } ?? 0
        outputLatencyFrames = deviceLatency + safetyOffset + streamLatency
    }

    private func startIO() throws {
        var procID: AudioDeviceIOProcID?
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, output, outputTime in
                self.render(input: input, output: output, outputTime: outputTime)
            },
            "creating the IOProc"
        )
        ioProcID = procID

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.overloads.wrappingAdd(1, ordering: .relaxed)
        }
        var address = propertyAddress(kAudioDeviceProcessorOverload)
        if AudioObjectAddPropertyListenerBlock(aggregateID, &address, DispatchQueue.main, listener) == noErr {
            overloadListener = listener
        }

        try check(AudioDeviceStart(aggregateID, procID), "starting the aggregate device")
    }

    /// Stops the IO, then destroys the aggregate device and the tap. Once the tap is gone, the target
    /// plays through the speakers again.
    func stop() {
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if let overloadListener {
            var address = propertyAddress(kAudioDeviceProcessorOverload)
            AudioObjectRemovePropertyListenerBlock(aggregateID, &address, DispatchQueue.main, overloadListener)
            self.overloadListener = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    func setDelay(milliseconds: Int) {
        let frames = Int(Double(milliseconds) / 1000 * sampleRate)
        // Leave room for a whole callback inside the ring.
        delayFrames.store(min(max(frames, 0), ringFrames / 2), ordering: .relaxed)
    }

    // MARK: - Real-time thread

    private struct StereoSource {
        let left: UnsafeMutablePointer<Float>
        let leftStride: Int
        let right: UnsafeMutablePointer<Float>
        let rightStride: Int
        let frames: Int
    }

    /// The tap's channels come last in the aggregate's input: the output sub-device's own inputs,
    /// when it has any (a headset microphone), come first.
    private static func stereoSource(_ inputs: UnsafeMutableAudioBufferListPointer) -> StereoSource? {
        guard let last = inputs.last, last.mNumberChannels > 0,
              let data = last.mData?.assumingMemoryBound(to: Float.self) else { return nil }
        let channels = Int(last.mNumberChannels)
        let frames = Int(last.mDataByteSize) / (MemoryLayout<Float>.size * channels)
        if channels >= 2 {
            return StereoSource(left: data + (channels - 2), leftStride: channels, right: data + (channels - 1), rightStride: channels, frames: frames)
        }
        if inputs.count >= 2, inputs[inputs.count - 2].mNumberChannels == 1,
           let previous = inputs[inputs.count - 2].mData?.assumingMemoryBound(to: Float.self) {
            return StereoSource(left: previous, leftStride: 1, right: data, rightStride: 1, frames: frames)
        }
        return StereoSource(left: data, leftStride: 1, right: data, rightStride: 1, frames: frames)
    }

    private func render(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>,
        outputTime: UnsafePointer<AudioTimeStamp>
    ) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        guard let firstOutput = outputs.first, firstOutput.mNumberChannels > 0, ringFrames > 0 else { return }
        let frames = Int(firstOutput.mDataByteSize) / (MemoryLayout<Float>.size * Int(firstOutput.mNumberChannels))
        let source = Self.stereoSource(inputs)

        if callbacks.wrappingAdd(1, ordering: .relaxed).oldValue == 0 {
            inputLayout.store(inputs.count * 100 + Int(inputs.last?.mNumberChannels ?? 0), ordering: .relaxed)
            outputLayout.store(outputs.count * 100 + Int(firstOutput.mNumberChannels), ordering: .relaxed)
            framesPerCallback.store(frames, ordering: .relaxed)
        }
        if let source, source.frames != frames {
            frameMismatches.wrappingAdd(1, ordering: .relaxed)
        }

        // 1. Capture into the ring, and measure the level every 10 ms.
        let written = writtenFrames.load(ordering: .relaxed)
        for index in 0..<frames {
            var left: Float = 0
            var right: Float = 0
            if let source, index < source.frames {
                left = source.left[index * source.leftStride]
                right = source.right[index * source.rightStride]
            }
            let slot = (written + index) % ringFrames
            ring[2 * slot] = left
            ring[2 * slot + 1] = right

            hopSum += 0.5 * (left * left + right * right)
            hopFill += 1
            if hopFill == hopFrames {
                let hop = completedHops.load(ordering: .relaxed)
                energies[hop % energySlots] = (hopSum / Float(hopFrames)).squareRoot()
                completedHops.store(hop + 1, ordering: .releasing)
                hopSum = 0
                hopFill = 0
            }
        }

        // 2. Play back `delay` behind what was just captured.
        let start = written - delayFrames.load(ordering: .relaxed)
        for buffer in outputs {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let channels = Int(buffer.mNumberChannels)
            for index in 0..<frames {
                let sourceFrame = start + index
                let slot = sourceFrame >= 0 ? sourceFrame % ringFrames : -1
                for channel in 0..<channels {
                    data[index * channels + channel] = slot >= 0 ? ring[2 * slot + (channel & 1)] : 0
                }
            }
        }

        writtenFrames.store(written + frames, ordering: .releasing)
        outputStartFrame.store(start, ordering: .relaxed)
        if outputTime.pointee.mFlags.contains(.hostTimeValid) {
            outputHostTime.store(outputTime.pointee.mHostTime, ordering: .releasing)
        }
    }

    // MARK: - Reading, from the main thread

    /// The level of the sound heard at `hostTime`, read `anticipation` seconds ahead of it.
    /// `extraLatency` (seconds) adds to the output latency Core Audio reports (Bluetooth, display).
    func level(heardAt hostTime: UInt64, anticipation: Double, extraLatency: Double) -> Float {
        guard let heard = heardFrame(at: hostTime, extraLatency: extraLatency) else { return 0 }
        let available = completedHops.load(ordering: .acquiring) - 1
        let hop = min(Int((heard + anticipation * sampleRate) / Double(hopFrames)), available)
        guard hop >= 0, hop > available - energySlots else { return 0 }
        return energies[hop % energySlots]
    }

    /// How far ahead of the heard sound the analysis can see: the real lookahead, in seconds.
    func lookahead(at hostTime: UInt64, extraLatency: Double) -> Double? {
        guard let heard = heardFrame(at: hostTime, extraLatency: extraLatency) else { return nil }
        let analysed = Double(completedHops.load(ordering: .acquiring) * hopFrames)
        return (analysed - heard) / sampleRate
    }

    /// The level of the last 10 ms captured, in dBFS.
    var capturedLevelDecibels: Double {
        let hop = completedHops.load(ordering: .acquiring) - 1
        guard hop >= 0 else { return -120 }
        return 20 * log10(max(Double(energies[hop % energySlots]), 1e-6))
    }

    private func heardFrame(at hostTime: UInt64, extraLatency: Double) -> Double? {
        let outputHost = outputHostTime.load(ordering: .acquiring)
        guard outputHost != 0 else { return nil }
        let start = outputStartFrame.load(ordering: .relaxed)
        let latency = Double(outputLatencyFrames) / sampleRate + extraLatency
        let presented = HostClock.nanoseconds(outputHost) + latency * 1e9
        return Double(start) + (HostClock.nanoseconds(hostTime) - presented) * 1e-9 * sampleRate
    }
}
