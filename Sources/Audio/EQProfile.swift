import Foundation

// MARK: - EQ Profile Model

struct EQProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    var bands: [SavedBand]
    var masterGain: Float
    var knobValues: [String: Float]?    // character knob positions (optional, back-compat)

    struct SavedBand: Codable, Hashable {
        var frequency: Float
        var gain: Float
        var q: Float
        var type: Int?
        var bypassed: Bool?
    }

    init(id: UUID = UUID(),
         name: String,
         bands: [SavedBand],
         masterGain: Float = 0,
         knobValues: [String: Float] = [:],
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.bands = bands
        self.masterGain = masterGain
        self.knobValues = knobValues.isEmpty ? nil : knobValues
        self.createdAt = createdAt
    }
}

extension EQProfile {
    static func from(bands: [EQBand], masterGain: Float, knobValues: [String: Float] = [:], name: String) -> EQProfile {
        EQProfile(
            name: name,
            bands: bands.map {
                SavedBand(
                    frequency: $0.frequency,
                    gain: $0.gain,
                    q: $0.q,
                    type: $0.type.rawValue,
                    bypassed: $0.bypassed
                )
            },
            masterGain: masterGain,
            knobValues: knobValues
        )
    }

    var eqBands: [EQBand] {
        bands.map { saved in
            EQBand(
                frequency: saved.frequency,
                gain: saved.gain,
                q: saved.q,
                type: saved.type.flatMap { EQFilterType(rawValue: $0) } ?? .bell,
                bypassed: saved.bypassed ?? false
            )
        }
    }
}

// MARK: - Storage Container

struct ProfileStorage: Codable {
    let version: Int
    var lastProfileID: UUID?
    var profiles: [EQProfile]
    var slotAProfileID: UUID?
    var slotBProfileID: UUID?
}

// MARK: - Profile Store

@MainActor
final class ProfileStore: ObservableObject {
    @Published var profiles: [EQProfile] = []
    @Published var currentProfileID: UUID?
    @Published var slotAProfileID: UUID?
    @Published var slotBProfileID: UUID?

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Ether", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profiles.json")
    }()

    init() {
        load()
    }

    // MARK: - Load / Save

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let storage = try? JSONDecoder().decode(ProfileStorage.self, from: data) else {
            profiles = []
            currentProfileID = nil
            return
        }
        profiles = storage.profiles.sorted { $0.createdAt > $1.createdAt }
        currentProfileID = storage.lastProfileID
        slotAProfileID = storage.slotAProfileID
        slotBProfileID = storage.slotBProfileID
    }

    private func save() {
        let storage = ProfileStorage(
            version: 1,
            lastProfileID: currentProfileID,
            profiles: profiles,
            slotAProfileID: slotAProfileID,
            slotBProfileID: slotBProfileID
        )
        guard let data = try? JSONEncoder().encode(storage) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - CRUD

    func saveNew(name: String, bands: [EQBand], masterGain: Float, knobValues: [String: Float] = [:]) {
        let profile = EQProfile.from(bands: bands, masterGain: masterGain, knobValues: knobValues, name: name)
        profiles.insert(profile, at: 0)
        currentProfileID = profile.id
        save()
    }

    func overwriteCurrent(bands: [EQBand], masterGain: Float, knobValues: [String: Float] = [:]) {
        guard let id = currentProfileID,
              let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        updateProfile(at: index, bands: bands, masterGain: masterGain, knobValues: knobValues)
    }

    func overwriteProfile(_ profile: EQProfile, bands: [EQBand], masterGain: Float, knobValues: [String: Float] = [:]) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        updateProfile(at: index, bands: bands, masterGain: masterGain, knobValues: knobValues)
    }

    private func updateProfile(at index: Int, bands: [EQBand], masterGain: Float, knobValues: [String: Float]) {
        profiles[index].bands = bands.map {
            EQProfile.SavedBand(frequency: $0.frequency, gain: $0.gain, q: $0.q, type: $0.type.rawValue, bypassed: $0.bypassed)
        }
        profiles[index].masterGain = masterGain
        profiles[index].knobValues = knobValues.isEmpty ? nil : knobValues
        save()
    }

    // MARK: - A/B Slots

    func assignToSlot(_ profile: EQProfile?, slot: ABSlot) {
        switch slot {
        case .a: slotAProfileID = profile?.id
        case .b: slotBProfileID = profile?.id
        }
        save()
    }

    func profile(for slot: ABSlot) -> EQProfile? {
        let id = slot == .a ? slotAProfileID : slotBProfileID
        return profiles.first(where: { $0.id == id })
    }

    func rename(_ profile: EQProfile, to newName: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].name = newName
        save()
    }

    func delete(_ profile: EQProfile) {
        profiles.removeAll { $0.id == profile.id }
        if currentProfileID == profile.id {
            currentProfileID = profiles.first?.id
        }
        if slotAProfileID == profile.id { slotAProfileID = nil }
        if slotBProfileID == profile.id { slotBProfileID = nil }
        save()
    }

    func setCurrent(_ profile: EQProfile) {
        currentProfileID = profile.id
        save()
    }
}

enum ABSlot {
    case a, b
}
