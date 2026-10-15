import AVFoundation
import Foundation
import Observation

/// Ses efektleri ve müzik. Sessiz anahtarına ve kullanıcının kendi müziğine saygı duyar (.ambient).
@MainActor
@Observable
final class AudioManager {
    static let shared = AudioManager()

    enum Sfx: String, CaseIterable {
        case place, rotate, remove, deliver, complaint, breach, contract, unlock, upgrade, error, tap
    }

    var sfxEnabled: Bool {
        didSet { UserDefaults.standard.set(sfxEnabled, forKey: "sfxEnabled") }
    }
    var musicEnabled: Bool {
        didSet {
            UserDefaults.standard.set(musicEnabled, forKey: "musicEnabled")
            if musicEnabled { startMusic() } else { music?.pause() }
        }
    }

    private var players: [Sfx: [AVAudioPlayer]] = [:]
    private var music: AVAudioPlayer?
    private var lastPlayed: [Sfx: TimeInterval] = [:]

    private init() {
        let d = UserDefaults.standard
        sfxEnabled = d.object(forKey: "sfxEnabled") as? Bool ?? true
        musicEnabled = d.object(forKey: "musicEnabled") as? Bool ?? true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for s in Sfx.allCases {
            guard let url = Bundle.main.url(forResource: s.rawValue, withExtension: "wav") else { continue }
            // Aynı efekt üst üste çalabilsin diye küçük bir havuz.
            players[s] = (0..<3).compactMap { _ in
                let p = try? AVAudioPlayer(contentsOf: url)
                p?.prepareToPlay()
                return p
            }
        }
    }

    func play(_ s: Sfx, volume: Float = 1) {
        guard sfxEnabled, let pool = players[s] else { return }
        let now = CACurrentMediaTime()
        // Aynı efekt 40 ms içinde tekrar istenirse yut: bant dolduğunda tıkırtı seli olmasın.
        if let last = lastPlayed[s], now - last < 0.04 { return }
        lastPlayed[s] = now
        let p = pool.first { !$0.isPlaying } ?? pool[0]
        p.volume = volume
        p.currentTime = 0
        p.play()
    }

    func startMusic() {
        guard musicEnabled else { return }
        if music == nil, let url = Bundle.main.url(forResource: "music-loop", withExtension: "wav") {
            music = try? AVAudioPlayer(contentsOf: url)
            music?.numberOfLoops = -1
            music?.volume = 0.35
            music?.prepareToPlay()
        }
        if music?.isPlaying == false { music?.play() }
    }

    func pauseMusic() { music?.pause() }
}
