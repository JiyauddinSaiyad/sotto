import AVFoundation
import CoreAudio

/// Your side of the call. Echo cancellation keeps the speakers from being
/// transcribed as you.
final class MicCapture {
    private let engine = AVAudioEngine()
    private var onBuffer: (AVAudioPCMBuffer) -> Void = { _ in }
    private var observer: NSObjectProtocol?

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        self.onBuffer = onBuffer
        // AirPods in mid-call means AVAudioEngine quietly stops. Rebuild on the new
        // device before anyone notices.
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self else { return }
            engine.inputNode.removeTap(onBus: 0)
            try? run()
        }
        try run()
    }

    private func run() throws {
        let onBuffer = onBuffer
        let input = engine.inputNode
        try? input.setVoiceProcessingEnabled(true)
        input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        // Voice processing hands back 7 channels. Channel 0 is you; the other 6
        // are… opinions. Fold to mono or the converter outputs silence.
        let format = input.outputFormat(forBus: 0)
        let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let source = buffer.floatChannelData,
                  let out = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: buffer.frameLength) else { return }
            out.frameLength = buffer.frameLength
            out.floatChannelData![0].update(from: source[0], count: Int(buffer.frameLength))
            onBuffer(out)
        }
        try engine.start()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

/// Everyone else, via a Core Audio process tap on the system output. Asks only for
/// "System Audio Recording"; Sotto never sees your screen, so it never asks to.
final class SystemAudioCapture {
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private var listener: AudioObjectPropertyListenerBlock?
    private var onBuffer: (AVAudioPCMBuffer) -> Void = { _ in }
    private var onStop: (Error) -> Void = { _ in }
    private let queue = DispatchQueue(label: "sotto.system-audio")
    /// Without permission macOS doesn't send silence, it sends nothing at all. So "no
    /// callbacks yet" is the only tell that System Audio Recording is switched off.
    private(set) var isFlowing = false
    private var outputChanged = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                           mScope: kAudioObjectPropertyScopeGlobal,
                                                           mElement: kAudioObjectPropertyElementMain)

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void, onStop: @escaping (Error) -> Void) async throws {
        self.onBuffer = onBuffer
        self.onStop = onStop
        try run()
        // Switching to AirPods moves the system mix to a new device; re-tap so we
        // follow it instead of listening to the old one go quiet.
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            teardown()
            do { try run() } catch { self.onStop(error) }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &outputChanged, queue, listener)
        self.listener = listener
    }

    func stop() async {
        if let listener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &outputChanged, queue, listener)
        }
        listener = nil
        teardown()
    }

    /// The recipe: a tap on everything, a private aggregate device wrapping it, and an
    /// IO proc on that device. Four Core Audio calls to say "let me listen". Classic.
    private func run() throws {
        let description = CATapDescription(__stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tap))

        var asbd = AudioStreamBasicDescription()
        try check(read(tap, kAudioTapPropertyFormat, into: &asbd))
        guard let format = AVAudioFormat(streamDescription: &asbd) else { throw NSError(domain: NSOSStatusErrorDomain, code: -1) }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sotto",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device))

        let onBuffer = onBuffer
        try check(AudioDeviceCreateIOProcIDWithBlock(&proc, device, queue) { [unowned self] _, input, _, _, _ in
            self.isFlowing = true
            // Tap-only aggregate, so the one stream in here is ours. (Add the speakers as a
            // sub-device and you get their stream too, in a layout the tap format lies about.)
            guard let tapStream = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)).first else { return }
            // Copy out of Core Audio's memory before handing it on. The HAL reuses it the
            // moment we return, and the resampler likes to come back for leftovers.
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: tapStream)
            guard let borrowed = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: &list),
                  let owned = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: borrowed.frameLength) else { return }
            owned.frameLength = borrowed.frameLength
            memcpy(owned.mutableAudioBufferList.pointee.mBuffers.mData, tapStream.mData, Int(tapStream.mDataByteSize))
            onBuffer(owned)
        })
        try check(AudioDeviceStart(device, proc))
    }

    private func teardown() {
        if let proc {
            AudioDeviceStop(device, proc)
            AudioDeviceDestroyIOProcID(device, proc)
        }
        proc = nil
        if device != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(device) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        device = AudioObjectID(kAudioObjectUnknown)
        tap = AudioObjectID(kAudioObjectUnknown)
    }

    private func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T) -> OSStatus {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
    }

    private func check(_ status: OSStatus) throws {
        if status != noErr { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}


