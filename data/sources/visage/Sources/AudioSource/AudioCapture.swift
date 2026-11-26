import CoreAudio
import Foundation
import Shared
import Synchronization

/// What the tap captures.
public struct CaptureTarget: Sendable, Equatable {
    /// The process objects to tap, as they exist now.
    public var processObjects: [AudioObjectID]
    /// macOS 26: the bundle IDs to tap; Core Audio finds the app again when it restarts.
    public var bundleIDs: [String]

    public init(processObjects: [AudioObjectID] = [], bundleIDs: [String] = []) {
        self.processObjects = processObjects
        self.bundleIDs = bundleIDs
    }
}

/// One capture: a private, muted tap on the target; an aggregate device that pairs it with the default
/// output; a single IOProc that writes the captured sound into a ring and plays it back `delay` later.
/// Capture and playback run on the aggregate device's clock: they cannot drift apart (spec, § 5).
///
/// The IOProc runs on a real-time thread: it never allocates, never locks, and talks to the rest of the
/// app through atomics and buffers allocated before it starts.
public final class AudioCapture: @unchecked Sendable {
    public private(set) var tapFormat = AudioStreamBasicDescription()
    public private(set) var sampleRate: Double = 48_000
    public private(set) var outputDeviceName = ""
    /// Device latency + safety offset + stream latency: from handing a frame over to the speaker playing it.
    public private(set) var outputLatency: Double = 0

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var overloadListener: AudioObjectPropertyListenerBlock?

    private static let ringSeconds = 2.0
    private var ring: FrameRing?
    private var hopFrames = 480
    private let levelSlots = 4096
    private let levels: UnsafeMutablePointer<Float>
    private var hopSum: Float = 0
    private var hopFill = 0

    private let delayFrames = Atomic<Int>(0)
    /// Frames captured so far; frame numbers count from 0 at the start of the capture.
    public let writtenFrames = Atomic<Int>(0)
    private let completedHops = Atomic<Int>(0)
    private let outputStartFrame = Atomic<Int>(0)
    private let outputHostTime = Atomic<UInt64>(0)
    public let callbacks = Atomic<Int>(0)
    public let overloads = Atomic<Int>(0)

    public init() {
        levels = .allocate(capacity: levelSlots)
        levels.initialize(repeating: 0, count: levelSlots)
    }

    deinit {
        stop()
        levels.deallocate()
    }

    // MARK: - Starting and stopping

    /// Creates the tap and the aggregate device, then starts the IO. While macOS waits for the user to allow
    /// system audio recording, this blocks (90 s seen in the pilot): never call it on the main thread.
    public func start(target: CaptureTarget, delayMilliseconds: Int) throws {
        do {
            try createTap(target: target)
            try createAggregateDevice()
            setDelay(milliseconds: delayMilliseconds)
            try startIO()
        } catch {
            stop()
            throw error
        }
    }

    /// Stops the IO, then destroys the aggregate device and the tap: the target plays through the speakers
    /// again. A crash does the same, the tap being private (pilot, § 2.2).
    public func stop() {
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

    public func setDelay(milliseconds: Int) {
        let frames = Int(Double(milliseconds) / 1000 * sampleRate)
        let limit = ring.map { $0.capacity / 2 } ?? 0
        delayFrames.store(min(max(frames, 0), limit), ordering: .relaxed)
    }

    private func createTap(target: CaptureTarget) throws {
        let description = CATapDescription(
            __stereoMixdownOfProcesses: target.processObjects.map { NSNumber(value: $0) })
        if !target.bundleIDs.isEmpty {
            guard #available(macOS 26, *) else {
                throw CoreAudioError(
                    operation: "tapping by bundle ID (macOS 26)", status: kAudioHardwareUnsupportedOperationError)
            }
            description.bundleIDs = target.bundleIDs
            description.isProcessRestoreEnabled = true
        }
        description.name = ProcessTaps.name
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "creating the process tap")
        tapID = tap
        tapFormat = try readProperty(tap, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
    }

    private func createAggregateDevice() throws {
        let output = try defaultOutputDevice()
        let outputUID = try readStringProperty(output, kAudioDevicePropertyDeviceUID)
        let tapUID = try readStringProperty(tapID, kAudioTapPropertyUID)
        outputDeviceName = (try? readStringProperty(output, kAudioObjectPropertyName)) ?? outputUID

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: ProcessTaps.name,
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tapUID]],
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        try check(
            AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate), "creating the aggregate device"
        )
        aggregateID = aggregate

        sampleRate = try readProperty(aggregate, kAudioDevicePropertyNominalSampleRate, initial: Float64(0))
        guard sampleRate > 0 else {
            throw CoreAudioError(operation: "reading the sample rate", status: kAudioHardwareUnsupportedOperationError)
        }
        ring = FrameRing(capacity: Int(Self.ringSeconds * sampleRate))
        hopFrames = Int(sampleRate / 100)

        let scope = kAudioObjectPropertyScopeOutput
        let deviceLatency =
            (try? readProperty(output, kAudioDevicePropertyLatency, scope: scope, initial: UInt32(0))) ?? 0
        let safetyOffset =
            (try? readProperty(output, kAudioDevicePropertySafetyOffset, scope: scope, initial: UInt32(0))) ?? 0
        let streams =
            (try? readArrayProperty(output, kAudioDevicePropertyStreams, scope: scope, filler: AudioObjectID(0))) ?? []
        let streamLatency =
            streams.first.flatMap { try? readProperty($0, kAudioStreamPropertyLatency, initial: UInt32(0)) } ?? 0
        outputLatency = Double(deviceLatency + safetyOffset + streamLatency) / sampleRate
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

    // MARK: - The real-time thread

    private struct StereoSource {
        let left: UnsafeMutablePointer<Float>
        let leftStride: Int
        let right: UnsafeMutablePointer<Float>
        let rightStride: Int
        let frames: Int
    }

    /// The tap's channels come last in the aggregate's input: the output sub-device's own inputs, when it
    /// has any (a headset microphone), come first.
    private static func stereoSource(_ inputs: UnsafeMutableAudioBufferListPointer) -> StereoSource? {
        guard let last = inputs.last, last.mNumberChannels > 0,
            let data = last.mData?.assumingMemoryBound(to: Float.self)
        else { return nil }
        let channels = Int(last.mNumberChannels)
        let frames = Int(last.mDataByteSize) / (MemoryLayout<Float>.size * channels)
        if channels >= 2 {
            return StereoSource(
                left: data + (channels - 2), leftStride: channels, right: data + (channels - 1), rightStride: channels,
                frames: frames)
        }
        if inputs.count >= 2, inputs[inputs.count - 2].mNumberChannels == 1,
            let previous = inputs[inputs.count - 2].mData?.assumingMemoryBound(to: Float.self)
        {
            return StereoSource(left: previous, leftStride: 1, right: data, rightStride: 1, frames: frames)
        }
        return StereoSource(left: data, leftStride: 1, right: data, rightStride: 1, frames: frames)
    }

    private func render(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>,
        outputTime: UnsafePointer<AudioTimeStamp>
    ) {
        guard let ring else { return }
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        guard let firstOutput = outputs.first, firstOutput.mNumberChannels > 0 else { return }
        let frames = Int(firstOutput.mDataByteSize) / (MemoryLayout<Float>.size * Int(firstOutput.mNumberChannels))
        let source = Self.stereoSource(inputs)
        callbacks.wrappingAdd(1, ordering: .relaxed)

        // 1. Capture into the ring, and measure the level every 10 ms.
        let written = writtenFrames.load(ordering: .relaxed)
        for index in 0..<frames {
            var left: Float = 0
            var right: Float = 0
            if let source, index < source.frames {
                left = source.left[index * source.leftStride]
                right = source.right[index * source.rightStride]
            }
            ring.write(frame: written + index, left: left, right: right)
            hopSum += 0.5 * (left * left + right * right)
            hopFill += 1
            if hopFill == hopFrames {
                let hop = completedHops.load(ordering: .relaxed)
                levels[hop % levelSlots] = (hopSum / Float(hopFrames)).squareRoot()
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
                let frame = start + index
                for channel in 0..<channels {
                    data[index * channels + channel] = channel & 1 == 0 ? ring.left(frame) : ring.right(frame)
                }
            }
        }

        writtenFrames.store(written + frames, ordering: .releasing)
        outputStartFrame.store(start, ordering: .relaxed)
        if outputTime.pointee.mFlags.contains(.hostTimeValid) {
            outputHostTime.store(outputTime.pointee.mHostTime, ordering: .releasing)
        }
    }

    // MARK: - Reading, from other threads

    /// The frame of captured sound heard at `hostTime`; `extraLatency` (seconds) adds to the output latency
    /// Core Audio reports (Bluetooth headphones, the display). Nil before the first callback.
    public func heardFrame(at hostTime: UInt64, extraLatency: Double = 0) -> Double? {
        let outputHost = outputHostTime.load(ordering: .acquiring)
        guard outputHost != 0 else { return nil }
        let start = outputStartFrame.load(ordering: .relaxed)
        let presented = HostClock.seconds(outputHost) + outputLatency + extraLatency
        return Double(start) + (HostClock.seconds(hostTime) - presented) * sampleRate
    }

    /// How far ahead of the heard sound the capture has got, in seconds: the lookahead the analysis has.
    public func lookahead(at hostTime: UInt64, extraLatency: Double = 0) -> Double? {
        guard let heard = heardFrame(at: hostTime, extraLatency: extraLatency) else { return nil }
        return (Double(writtenFrames.load(ordering: .acquiring)) - heard) / sampleRate
    }

    /// The level of the last 10 ms captured, in dBFS.
    public var capturedLevelDecibels: Double {
        let hop = completedHops.load(ordering: .acquiring) - 1
        guard hop >= 0 else { return -120 }
        return 20 * log10(max(Double(levels[hop % levelSlots]), 1e-6))
    }

    /// Copies captured frames, mixed down to mono, for the analysis. False when they are not (or no
    /// longer) in the ring.
    public func copyCaptured(from start: Int, count: Int, into destination: UnsafeMutablePointer<Float>) -> Bool {
        guard let ring else { return false }
        return ring.copyMono(
            from: start, count: count, written: writtenFrames.load(ordering: .acquiring), into: destination)
    }
}
