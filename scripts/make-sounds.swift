import Foundation

// Basit sentezleyici: ses efektleri ve bir ambient müzik döngüsü üretir (16-bit mono WAV).
let sr = 44_100.0

struct Synth {
    var samples: [Float]
    init(seconds: Double) { samples = Array(repeating: 0, count: Int(seconds * sr)) }

    /// Belirtilen zamanda bir sesi karıştırır. gen(t) t saniyedeki örnek (0..dur).
    mutating func add(at start: Double, dur: Double, _ gen: (Double) -> Float) {
        let s0 = Int(start * sr)
        let n = Int(dur * sr)
        for i in 0..<n where s0 + i < samples.count && s0 + i >= 0 {
            samples[s0 + i] += gen(Double(i) / sr)
        }
    }

    mutating func lowpass(cutoff: Double) {
        let rc = 1.0 / (2 * .pi * cutoff)
        let a = Float((1.0 / sr) / (rc + 1.0 / sr))
        var y: Float = 0
        for i in samples.indices { y += a * (samples[i] - y); samples[i] = y }
    }

    mutating func normalize(peak: Float) {
        let m = samples.map { abs($0) }.max() ?? 1
        guard m > 0 else { return }
        let g = peak / m
        for i in samples.indices { samples[i] *= g }
    }

    mutating func fade(inSec: Double, outSec: Double) {
        let ni = Int(inSec * sr), no = Int(outSec * sr)
        for i in 0..<min(ni, samples.count) { samples[i] *= Float(i) / Float(ni) }
        for i in 0..<min(no, samples.count) { samples[samples.count - 1 - i] *= Float(i) / Float(no) }
    }

    func write(_ path: String) {
        var data = Data()
        func u32(_ v: UInt32) { data.append(contentsOf: withUnsafeBytes(of: v.littleEndian) { Array($0) }) }
        func u16(_ v: UInt16) { data.append(contentsOf: withUnsafeBytes(of: v.littleEndian) { Array($0) }) }
        let pcm = samples.map { Int16(max(-1, min(1, $0)) * 32767) }
        data.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count * 2))
        data.append(contentsOf: Array("WAVE".utf8)); data.append(contentsOf: Array("fmt ".utf8))
        u32(16); u16(1); u16(1); u32(UInt32(sr)); u32(UInt32(sr) * 2); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count * 2))
        for v in pcm { u16(UInt16(bitPattern: v)) }
        try! data.write(to: URL(fileURLWithPath: path))
    }
}

func sine(_ f: Double, _ t: Double) -> Float { Float(sin(2 * .pi * f * t)) }
func env(_ t: Double, attack: Double, decay: Double) -> Float {
    t < attack ? Float(t / attack) : Float(exp(-(t - attack) / decay))
}
func noise() -> Float { Float.random(in: -1...1) }
func note(_ midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

let out = CommandLine.arguments[1]
func sfx(_ name: String, _ seconds: Double, peak: Float = 0.6, _ build: (inout Synth) -> Void) {
    var s = Synth(seconds: seconds)
    build(&s)
    s.normalize(peak: peak)
    s.fade(inSec: 0.002, outSec: 0.01)
    s.write("\(out)/\(name).wav")
}

// --- Efektler
sfx("place", 0.12) { s in
    s.add(at: 0, dur: 0.12) { t in sine(700 + 900 * t / 0.12, t) * env(t, attack: 0.003, decay: 0.03) }
    s.add(at: 0, dur: 0.01) { t in noise() * 0.3 * env(t, attack: 0.001, decay: 0.003) }
}
sfx("rotate", 0.06) { s in
    s.add(at: 0, dur: 0.06) { t in sine(1500, t) * env(t, attack: 0.002, decay: 0.012) }
}
sfx("remove", 0.18) { s in
    s.add(at: 0, dur: 0.18) { t in sine(220 - 140 * t / 0.18, t) * env(t, attack: 0.004, decay: 0.06) }
}
sfx("deliver", 0.3, peak: 0.45) { s in
    s.add(at: 0, dur: 0.15) { t in sine(note(81), t) * env(t, attack: 0.004, decay: 0.05) }
    s.add(at: 0.09, dur: 0.21) { t in sine(note(88), t) * env(t, attack: 0.004, decay: 0.07) }
}
sfx("complaint", 0.2, peak: 0.4) { s in
    s.add(at: 0, dur: 0.2) { t in (sine(330, t) + 0.5 * sine(337, t)) * env(t, attack: 0.01, decay: 0.07) }
}
sfx("breach", 0.5, peak: 0.7) { s in
    s.add(at: 0, dur: 0.5) { t in
        let f = 200 - 110 * t / 0.5
        let saw = Float(2 * (f * t - floor(0.5 + f * t)))
        let trem = Float(0.6 + 0.4 * sin(2 * .pi * 18 * t))
        return saw * trem * env(t, attack: 0.005, decay: 0.25)
    }
}
sfx("contract", 0.7, peak: 0.5) { s in
    for (i, m) in [72.0, 76, 79, 84].enumerated() {
        s.add(at: Double(i) * 0.1, dur: 0.4) { t in (sine(note(m), t) + 0.3 * sine(note(m + 12), t)) * env(t, attack: 0.004, decay: 0.12) }
    }
}
sfx("unlock", 1.0, peak: 0.5) { s in
    for (i, m) in [67.0, 71, 74, 79, 83, 86].enumerated() {
        s.add(at: Double(i) * 0.09, dur: 0.5) { t in (sine(note(m), t) + 0.3 * sine(note(m + 12), t)) * env(t, attack: 0.004, decay: 0.15) }
    }
}
sfx("upgrade", 0.3, peak: 0.5) { s in
    s.add(at: 0, dur: 0.3) { t in sine(400 * pow(4, t / 0.3), t) * env(t, attack: 0.01, decay: 0.12) }
}
sfx("error", 0.16, peak: 0.45) { s in
    for i in 0..<2 {
        s.add(at: Double(i) * 0.08, dur: 0.06) { t in Float(sin(2 * .pi * 300 * t) > 0 ? 0.6 : -0.6) * env(t, attack: 0.002, decay: 0.02) }
    }
}
sfx("tap", 0.04, peak: 0.35) { s in
    s.add(at: 0, dur: 0.04) { t in sine(2200, t) * env(t, attack: 0.001, decay: 0.006) }
}
// Kum havuzu: yalıtımda patlatma. Boğuk gümbürtü + kısa gürültü patlaması, sonra çıtırtı kuyruğu.
sfx("detonate", 0.45, peak: 0.6) { s in
    s.add(at: 0, dur: 0.35) { t in sine(90 - 50 * t / 0.35, t) * env(t, attack: 0.003, decay: 0.12) }
    s.add(at: 0, dur: 0.12) { t in noise() * env(t, attack: 0.001, decay: 0.03) }
    s.add(at: 0.1, dur: 0.35) { t in noise() * 0.25 * env(t, attack: 0.01, decay: 0.1) * Float(0.5 + 0.5 * sin(2 * .pi * 40 * t)) }
    s.lowpass(cutoff: 1800)
}
// Karantina: dosya çöpe gidiyor. Aşağı kayan ıslık + kapak tıkırtısı.
sfx("quarantine", 0.32, peak: 0.45) { s in
    s.add(at: 0, dur: 0.22) { t in sine(900 * pow(0.25, t / 0.22), t) * env(t, attack: 0.004, decay: 0.08) }
    s.add(at: 0.2, dur: 0.12) { t in (sine(160, t) + 0.4 * noise()) * env(t, attack: 0.001, decay: 0.03) }
}
// Polyglot uyarısı: iki hızlı yükselen bip (ikinci kimlik!).
sfx("polyglot", 0.3, peak: 0.45) { s in
    for i in 0..<2 {
        s.add(at: Double(i) * 0.13, dur: 0.1) { t in (sine(1100 + 300 * Double(i), t) + 0.3 * sine(2200 + 600 * Double(i), t)) * env(t, attack: 0.003, decay: 0.03) }
    }
}
// Seviye atlama: yükselen major arpej + parıltı; "unlock"tan daha kısa ve parlak.
sfx("levelup", 0.9, peak: 0.55) { s in
    for (i, m) in [72.0, 76, 79, 84, 88].enumerated() {
        s.add(at: Double(i) * 0.07, dur: 0.5) { t in (sine(note(m), t) + 0.35 * sine(note(m + 12), t) + 0.15 * sine(note(m + 19), t)) * env(t, attack: 0.003, decay: 0.14) }
    }
    s.add(at: 0.3, dur: 0.6) { t in sine(note(100), t) * 0.15 * env(t, attack: 0.05, decay: 0.2) * Float(0.5 + 0.5 * sin(2 * .pi * 9 * t)) }
}
// Başarım: iki notalı çan + hafif titreşim.
sfx("achievement", 0.55, peak: 0.5) { s in
    s.add(at: 0, dur: 0.45) { t in (sine(note(83), t) + 0.5 * sine(note(83) * 2.76, t)) * env(t, attack: 0.003, decay: 0.12) }
    s.add(at: 0.12, dur: 0.43) { t in (sine(note(90), t) + 0.5 * sine(note(90) * 2.76, t)) * env(t, attack: 0.003, decay: 0.15) * Float(0.8 + 0.2 * sin(2 * .pi * 6 * t)) }
}

// --- Müzik: A minör, 84 bpm, Am–F–C–G, 8 bar. İki kez render edilip ikinci döngü alınır: kuyruklar başa sarar.
let bpm = 84.0
let beat = 60 / bpm
let bars = 8
let loopSec = Double(bars) * 4 * beat
let chords: [[Double]] = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]] // A2.., F2.., C2.., G2..
var m = Synth(seconds: loopSec * 2 + 1)
var rng = SystemRandomNumberGenerator()
for loop in 0..<2 {
    let base = Double(loop) * loopSec
    for bar in 0..<bars {
        let chord = chords[bar / 2]
        let barStart = base + Double(bar) * 4 * beat
        // Pad: yumuşak, detune'lu sinüsler
        for n in chord {
            let f = note(n + 12)
            m.add(at: barStart, dur: 4 * beat + 0.4) { t in
                let a: Float = t < 0.6 ? Float(t / 0.6) : (t > 4 * beat ? Float(max(0, 1 - (t - 4 * beat) / 0.4)) : 1)
                return 0.08 * a * (sine(f, t) + sine(f * 1.002, t) + 0.5 * sine(f * 0.5, t))
            }
        }
        // Arp: 8'lik notalar, iki oktav
        let arpNotes = chord.map { $0 + 24 } + chord.map { $0 + 36 }
        for e in 0..<8 {
            let idx = [0, 1, 2, 3, 2, 4, 1, 5][e]
            let f = note(arpNotes[idx])
            let vel: Float = (e % 2 == 0 ? 0.22 : 0.15) * Float.random(in: 0.85...1.0, using: &rng)
            m.add(at: barStart + Double(e) * beat / 2, dur: 0.6) { t in
                vel * (sine(f, t) + 0.25 * sine(f * 2, t)) * env(t, attack: 0.004, decay: 0.18)
            }
        }
        // Bas: her vuruşta kök, yumuşak
        for b in 0..<4 {
            let f = note(chord[0] - 12)
            m.add(at: barStart + Double(b) * beat, dur: beat) { t in 0.3 * sine(f, t) * env(t, attack: 0.01, decay: 0.3) }
        }
        // Kick 1 ve 3, hat off-beat (çok hafif)
        for b in [0, 2] {
            m.add(at: barStart + Double(b) * beat, dur: 0.2) { t in 0.5 * sine(55 * (1 + 2 * exp(-t * 40)), t) * env(t, attack: 0.002, decay: 0.08) }
        }
        for b in 0..<4 {
            m.add(at: barStart + Double(b) * beat + beat / 2, dur: 0.05) { t in 0.05 * noise() * env(t, attack: 0.001, decay: 0.012) }
        }
    }
}
m.lowpass(cutoff: 3200)
var loopOut = Synth(seconds: loopSec)
let off = Int(loopSec * sr)
for i in 0..<loopOut.samples.count { loopOut.samples[i] = m.samples[off + i] }
loopOut.normalize(peak: 0.5)
loopOut.write("\(out)/music-loop.wav")
print("sounds written to \(out)")
