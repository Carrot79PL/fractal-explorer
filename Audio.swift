import AVFoundation

/// Generatywna muzyka ambient: wolno zmieniające się akordy (pad z lekko rozstrojonych oscylatorów),
/// rzadkie „dzwonki" z pentatoniki i pogłos. Głębokość zoomu rozjaśnia brzmienie.
final class AmbientMusic {
    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    private var node: AVAudioSourceNode?
    private let sr: Double

    // Parametry zapisywane z wątku głównego, czytane przez wątek audio.
    private var targetGain: Float = 0
    private var brightness: Float = 0.2

    // Stan syntezatora (tylko wątek audio).
    private static let chords: [[Double]] = [
        [45, 52, 59, 60, 64], [41, 48, 52, 57, 60], [48, 55, 62, 64, 67],
        [43, 50, 57, 59, 62], [45, 52, 57, 60, 64], [40, 47, 55, 59, 62]
    ]
    private static let bellNotes: [Double] = [69, 72, 74, 76, 79, 81, 84, 86, 88]
    private let nV = 5
    private var freq = [Double](repeating: 110, count: 5)
    private var target = [Double](repeating: 110, count: 5)
    private var phases = [Double](repeating: 0, count: 15)
    private var lfo = [Double](repeating: 0, count: 5)
    private let lfoRate: [Double] = [0.041, 0.057, 0.033, 0.071, 0.049]
    private let panL: [Float] = [0.9, 0.7, 0.5, 0.3, 0.15]
    private let panR: [Float] = [0.15, 0.3, 0.5, 0.7, 0.9]
    private let detune: [Double] = [-0.0021, 0.0, 0.0023]
    private var chordIndex = 0
    private var chordTimer = 0
    private var gain: Float = 0
    private(set) var peak: Float = 0

    private var bFreq = [Double](repeating: 0, count: 6)
    private var bPhase = [Double](repeating: 0, count: 6)
    private var bEnv = [Float](repeating: 0, count: 6)
    private var bPan = [Float](repeating: 0.5, count: 6)
    private var bellTimer = 0
    private var bellNext = 0
    private var rng: UInt32 = 2463534242

    init() {
        let hw = engine.outputNode.outputFormat(forBus: 0).sampleRate
        sr = hw > 8000 ? hw : 44100
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        let n = AVAudioSourceNode(format: fmt) { [unowned self] _, _, frames, abl -> OSStatus in
            self.render(frames: Int(frames), abl: abl)
            return noErr
        }
        node = n
        engine.attach(n)
        engine.attach(reverb)
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = 55
        engine.connect(n, to: reverb, format: fmt)
        engine.connect(reverb, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 0.5
        setChord(0, instant: true)
        bellNext = Int(sr * 3)
    }

    // MARK: API (wątek główny)

    func setEnabled(_ on: Bool) {
        targetGain = on ? 1 : 0
        if on {
            if !engine.isRunning { try? engine.start() }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self, self.targetGain == 0 else { return }
                self.engine.pause()
            }
        }
    }

    func setVolume(_ v: Double) { engine.mainMixerNode.outputVolume = Float(min(max(v, 0), 1)) }
    func setDepth(_ d: Double) { brightness = Float(d) }

    // MARK: Synteza (wątek audio)

    private func nextRandom() -> Double {
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5
        return Double(rng) / Double(UInt32.max)
    }

    private func midi(_ m: Double) -> Double { 440.0 * pow(2.0, (m - 69.0) / 12.0) }

    private func setChord(_ i: Int, instant: Bool = false) {
        let c = Self.chords[i % Self.chords.count]
        for v in 0..<nV {
            target[v] = midi(c[v])
            if instant { freq[v] = target[v] }
        }
    }

    private func render(frames: Int, abl: UnsafeMutablePointer<AudioBufferList>) {
        let list = UnsafeMutableAudioBufferListPointer(abl)
        guard list.count >= 2,
              let l = list[0].mData?.assumingMemoryBound(to: Float.self),
              let r = list[1].mData?.assumingMemoryBound(to: Float.self) else { return }
        let twoPi = 2.0 * Double.pi
        let glide = 1.0 - exp(-1.0 / (sr * 3.0))
        let bellDecay = Float(exp(-1.0 / (sr * 2.4)))
        let b = brightness
        let h2 = 0.12 + 0.35 * Double(b), h3 = 0.04 + 0.22 * Double(b)
        let chordLen = Int(sr * 16)

        for i in 0..<frames {
            gain += (targetGain - gain) * 0.00004
            chordTimer -= 1
            if chordTimer <= 0 {
                chordTimer = chordLen
                chordIndex = (chordIndex + 1) % Self.chords.count
                setChord(chordIndex)
            }
            var pl: Float = 0, pr: Float = 0
            for v in 0..<nV {
                freq[v] += (target[v] - freq[v]) * glide
                lfo[v] += twoPi * lfoRate[v] / sr
                if lfo[v] > twoPi { lfo[v] -= twoPi }
                let amp = Float(0.65 + 0.35 * sin(lfo[v])) * 0.05
                var s = 0.0
                for d in 0..<3 {
                    let k = v * 3 + d
                    phases[k] += twoPi * freq[v] * (1 + detune[d]) / sr
                    if phases[k] > twoPi { phases[k] -= twoPi }
                    let p = phases[k]
                    s += sin(p) + h2 * sin(2 * p) + h3 * sin(3 * p)
                }
                let o = Float(s) * amp
                pl += o * panL[v]
                pr += o * panR[v]
            }
            // dzwonki
            bellTimer += 1
            if bellTimer >= bellNext {
                bellTimer = 0
                bellNext = Int(sr * (2.5 + nextRandom() * 5.0 * (1.2 - Double(b))))
                let slot = Int(nextRandom() * 6) % 6
                let note = Self.bellNotes[Int(nextRandom() * Double(Self.bellNotes.count)) % Self.bellNotes.count]
                bFreq[slot] = midi(note)
                bEnv[slot] = 1
                bPan[slot] = Float(0.15 + 0.7 * nextRandom())
            }
            for k in 0..<6 where bEnv[k] > 0.0005 {
                bPhase[k] += twoPi * bFreq[k] / sr
                if bPhase[k] > twoPi * 64 { bPhase[k] -= twoPi * 64 }
                let p = bPhase[k]
                let o = bEnv[k] * Float(sin(p) + 0.3 * sin(2.76 * p)) * 0.045
                pl += o * (1 - bPan[k])
                pr += o * bPan[k]
                bEnv[k] *= bellDecay
            }
            l[i] = tanhf(pl * gain)
            r[i] = tanhf(pr * gain)
            peak = max(peak, abs(l[i]), abs(r[i]))
        }
    }
}
