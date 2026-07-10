import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Grabadora (micrófono → PCM16 16 kHz mono, con chunks y nivel)

final class Recorder {
    private let engine = AVAudioEngine()
    private var samples = Data()
    private var converter: AVAudioConverter?
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!

    var onChunk: ((Data) -> Void)?
    var onLevel: ((Float) -> Void)?
    private(set) var isRecording = false

    /// PCM crudo acumulado hasta ahora (para transcripción parcial en vivo).
    var pcmAcumulado: Data { samples }

    func start() throws {
        samples = Data()
        let input = engine.inputNode
        // Fijar el micrófono ANTES de leer el formato: sin esto macOS puede
        // enchufarnos el mic del iPhone (Continuity) y grabar silencio.
        if let dev = Microfono.elegido(), let au = input.audioUnit {
            var id = dev
            AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &id,
                                 UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let inFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inFormat, to: outFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }
            let ratio = self.outFormat.sampleRate / inFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: self.outFormat, frameCapacity: capacity) else { return }
            var served = false
            converter.convert(to: out, error: nil) { _, status in
                if served {
                    status.pointee = .noDataNow
                    return nil
                }
                served = true
                status.pointee = .haveData
                return buffer
            }
            guard out.frameLength > 0, let ch = out.int16ChannelData else { return }
            let chunk = Data(bytes: ch[0], count: Int(out.frameLength) * 2)
            self.samples.append(chunk)
            self.onChunk?(chunk)

            var sum: Double = 0
            let n = Int(out.frameLength)
            for i in 0..<n {
                let v = Double(ch[0][i]) / 32768.0
                sum += v * v
            }
            let rms = Float((sum / Double(max(n, 1))).squareRoot())
            let boosted = Float(pow(Double(min(rms * 12, 1.0)), 0.5))
            self.onLevel?(boosted)
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stop() -> Data {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        return wavFile(from: samples)
    }

    private func wavFile(from pcm: Data) -> Data {
        var wav = Data()
        let sampleRate: UInt32 = 16000
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { wav.append(contentsOf: $0) } }
        wav.append("RIFF".data(using: .ascii)!)
        append(UInt32(36 + pcm.count).littleEndian)
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        append(UInt32(16).littleEndian)
        append(UInt16(1).littleEndian)
        append(UInt16(1).littleEndian)
        append(sampleRate.littleEndian)
        append(UInt32(sampleRate * 2).littleEndian)
        append(UInt16(2).littleEndian)
        append(UInt16(16).littleEndian)
        wav.append("data".data(using: .ascii)!)
        append(UInt32(pcm.count).littleEndian)
        wav.append(pcm)
        return wav
    }
}

