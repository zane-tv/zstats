import Testing
import Foundation
import AppKit
@testable import ZStatKit
@testable import ZStatUI

@Suite("ZStats branding, logo, migration, and upstream-updater removal", .serialized)
struct BrandingTests {

    @Test("Logo loads as a non-empty template image named ZStats")
    func logoIsTemplateAndNamedZStats() throws {
        let image = try #require(Logo.image)
        #expect(image.isTemplate)
        #expect(image.accessibilityDescription == "ZStats")
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test("SettingsStore default and legacy directories resolve cleanly without side effects")
    func settingsDirectoriesResolveCleanly() {
        #expect(SettingsStore.defaultDirectory.lastPathComponent == "ZStats")
        #expect(SettingsStore.legacyAirStatsDirectory.lastPathComponent == "AirStats")
        #expect(SettingsStore.defaultDirectory.deletingLastPathComponent()
                == SettingsStore.legacyAirStatsDirectory.deletingLastPathComponent())
    }

    @MainActor
    @Test("SettingsStore migrates legacy AirStats settings and 24-hour history once without touching the legacy folder")
    func migratesLegacyAirStatsSettingsAndHistoryOnce() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZStatsMigration-\(UUID().uuidString)", isDirectory: true)
        let legacyDir = root.appendingPathComponent("AirStats", isDirectory: true)
        let zstatsDir = root.appendingPathComponent("ZStats", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Even when an empty ZStats directory already exists on disk, migration must run
        // because ZStats/settings.json has not been created yet.
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: zstatsDir, withIntermediateDirectories: true)

        let legacyJSON = """
        {
          "updates": {
            "lastCheckedAt": 776000000,
            "latestVersion": "1.5",
            "latestURL": "https://example.invalid/download"
          },
          "general": {
            "language": "vietnamese",
            "launchAtLogin": false,
            "temperatureUnit": "fahrenheit"
          },
          "menuBar": {
            "usesIconTitles": true,
            "items": [
              {
                "metric": "bluetoothBattery",
                "style": "iconAndText",
                "isEnabled": true,
                "showsCaption": true,
                "bluetoothDevice": { "id": "aa-bb", "name": "X11mouse1", "category": "mouse" }
              }
            ]
          }
        }
        """
        let legacySettingsURL = legacyDir.appendingPathComponent("settings.json")
        try Data(legacyJSON.utf8).write(to: legacySettingsURL)

        var history = MinuteHistory()
        let sampleDate = Date(timeIntervalSince1970: 1_760_000_040)
        history.advance(to: sampleDate)
        history.record(.cpuTotal, 0.42)
        MinuteHistoryFile(directory: legacyDir).save(history)

        let store = SettingsStore(directory: zstatsDir,
                                  legacyDirectory: legacyDir,
                                  saveDebounce: .seconds(3600))
        defer {
            store.update {
                $0.general.language = .system
                $0.theme = ThemeSettings()
            }
        }

        #expect(store.loadDiagnostic == nil)
        #expect(store.settings.general.language == .vietnamese)
        #expect(store.settings.general.launchAtLogin == false)
        #expect(store.settings.general.temperatureUnit == .fahrenheit)
        #expect(store.settings.menuBar.usesIconTitles == true)
        #expect(store.settings.menuBar.items.first?.bluetoothDevice?.name == "X11mouse1")

        // Retired upstream update keys are stripped in the migrated ZStats settings file,
        // while the original AirStats settings file remains untouched.
        let migratedText = try String(contentsOf: zstatsDir.appendingPathComponent("settings.json"), encoding: .utf8)
        #expect(!migratedText.contains("latestURL"))
        #expect(!migratedText.contains("updates"))
        let preservedLegacyText = try String(contentsOf: legacySettingsURL, encoding: .utf8)
        #expect(preservedLegacyText.contains("latestURL"))

        // 24-hour history file was copied across and loads identically.
        let migratedHistory = try #require(MinuteHistoryFile(directory: zstatsDir).load())
        #expect(migratedHistory == history)

        // Once ZStats/settings.json exists, later edits in AirStats/settings.json do not overwrite ZStats.
        store.update { $0.general.temperatureUnit = .celsius }
        store.flush()
        let secondStore = SettingsStore(directory: zstatsDir,
                                        legacyDirectory: legacyDir,
                                        saveDebounce: .seconds(3600))
        #expect(secondStore.settings.general.temperatureUnit == .celsius)
    }

    @MainActor
    @Test("Corrupt legacy AirStats settings fall back cleanly without quarantining or diagnostics")
    func corruptLegacyAirStatsFallsBackCleanly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZStatsCorruptMigration-\(UUID().uuidString)", isDirectory: true)
        let legacyDir = root.appendingPathComponent("AirStats", isDirectory: true)
        let zstatsDir = root.appendingPathComponent("ZStats", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        try Data("{corrupt".utf8).write(to: legacyDir.appendingPathComponent("settings.json"))

        let store = SettingsStore(directory: zstatsDir,
                                  legacyDirectory: legacyDir,
                                  saveDebounce: .seconds(3600))
        #expect(store.loadDiagnostic == nil)
        #expect(store.settings.general.updateInterval == 2)
        #expect(FileManager.default.fileExists(atPath: legacyDir.appendingPathComponent("settings.json").path))
    }

    @Test("Info.plist carries ZStats metadata and no Sparkle auto-update keys")
    func infoPlistHasZStatsAndNoSparkleKeys() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = repoRoot.appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let raw = try PropertyListSerialization.propertyList(from: data, format: nil)
        let plist = try #require(raw as? [String: Any])

        #expect(plist["CFBundleName"] as? String == "ZStats")
        #expect(plist["CFBundleDisplayName"] as? String == "ZStats")
        #expect(plist["CFBundleExecutable"] as? String == "ZStats")
        #expect(plist["CFBundleIdentifier"] as? String == "com.zstats.ZStats")
        #expect((plist["NSBluetoothAlwaysUsageDescription"] as? String)?.contains("ZStats") == true)

        let forbiddenKeys = [
            "SUFeedURL",
            "SUPublicEDKey",
            "SUAutomaticallyUpdate",
            "SUEnableAutomaticChecks",
            "SUScheduledCheckInterval",
        ]
        for key in forbiddenKeys {
            #expect(plist[key] == nil, "Unexpected updater key \(key) still present in Info.plist")
        }
    }

    @MainActor
    @Test("OffscreenRenderer renders English and Vietnamese surfaces, honours mutated settings, and restores global state")
    func offscreenRendererRendersAndRestoresGlobalState() async throws {
        let outDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZStatsBrandingRender-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outDir) }

        for language in [AppLanguage.english, .vietnamese] {
            var settings = ZStatKit.Settings()
            settings.general.language = language
            for surface in [OffscreenRenderer.Surface.settings, .panel] {
                let req = OffscreenRenderer.Request(surface: surface, scenario: .nominal,
                                                    isDark: true, scale: 1, settings: settings)
                let url = try OffscreenRenderer.render(req, to: outDir)
                let data = try Data(contentsOf: url)
                #expect(data.count > 1000)
                // Yield between AppKit offscreen renders so concurrent main-actor window
                // tests (e.g. WindowTortureTests) are never starved across their timers.
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        // Rendering the same cached key with a different panel disclosure state must update
        // the cached store rather than returning a stale layout, and must restore static
        // language/theme globals synchronously on exit.
        var collapsedSettings = ZStatKit.Settings()
        collapsedSettings.general.language = .english
        let collapsedData = try Data(contentsOf: OffscreenRenderer.render(
            .init(surface: .panel, scenario: .nominal, isDark: false, scale: 1, settings: collapsedSettings),
            to: outDir))
        try await Task.sleep(for: .milliseconds(20))

        let langBefore = SettingsStore.currentLanguage
        let themeBefore = SettingsStore.currentTheme
        var expandedSettings = collapsedSettings
        expandedSettings.general.language = .vietnamese
        expandedSettings.panel.collapsedModules.remove(.cpu)
        expandedSettings.theme.setAllColors(ThemeColor(red: 0.9, green: 0.2, blue: 0.3))
        let expandedData = try Data(contentsOf: OffscreenRenderer.render(
            .init(surface: .panel, scenario: .nominal, isDark: false, scale: 1, settings: expandedSettings),
            to: outDir))

        #expect(collapsedData != expandedData)
        #expect(SettingsStore.currentLanguage == langBefore)
        #expect(SettingsStore.currentTheme == themeBefore)
    }
}
