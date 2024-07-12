//
//  AppDelegate.swift
//  LyricsX - https://github.com/ddddxxx/LyricsX
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Cocoa
import GenericID
import HotKey
import MusicPlayer
import AppCenter
import AppCenterAnalytics
import AppCenterCrashes

#if !IS_FOR_MAS
import Sparkle
#endif

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return true
    }
    
    
    func registerUserDefaults() {
        let currentLang = NSLocale.preferredLanguages.first!
        let isZh = currentLang.hasPrefix("zh") || currentLang.hasPrefix("yue")
        let isHant = isZh && (currentLang.contains("-Hant") || currentLang.contains("-HK"))
        
        let defaultsUrl = Bundle.main.url(forResource: "UserDefaults", withExtension: "plist")!
        if let dict = NSDictionary(contentsOf: defaultsUrl) as? [String: Any] {
            defaults.register(defaults: dict)
        }
        defaults.register(defaults: [
            .desktopLyricsColor: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1),
            .desktopLyricsProgressColor: #colorLiteral(red: 0.1985405816, green: 1, blue: 0.8664234302, alpha: 1),
            .desktopLyricsShadowColor: #colorLiteral(red: 0, green: 1, blue: 0.8333333333, alpha: 1),
            .desktopLyricsBackgroundColor: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.6041579279),
            .lyricsWindowTextColor: #colorLiteral(red: 0.7540688515, green: 0.7540867925, blue: 0.7540771365, alpha: 1),
            .lyricsWindowHighlightColor: #colorLiteral(red: 0.8866666667, green: 1, blue: 0.8, alpha: 1),
            .preferBilingualLyrics: isZh,
            .chineseConversionIndex: isHant ? 2 : 0,
            .desktopLyricsXPositionFactor: 0.5,
            .desktopLyricsYPositionFactor: 0.9,
        ])
    }

    static var shared: AppDelegate? {
        return NSApplication.shared.delegate as? AppDelegate
    }

    @IBOutlet weak var lyricsOffsetTextField: NSTextField!
    @IBOutlet weak var lyricsOffsetStepper: NSStepper!
    @IBOutlet weak var statusBarMenu: NSMenu!

    var karaokeLyricsWC: KaraokeLyricsWindowController?

    lazy var searchLyricsWC: NSWindowController = {
        let searchVC = NSStoryboard.main!.instantiateController(withIdentifier: .init("SearchLyricsViewController")) as! SearchLyricsViewController
        let window = NSWindow(contentViewController: searchVC)
        window.title = NSLocalizedString("Search Lyrics", comment: "window title")
        return NSWindowController(window: window)
    }()

    // HotKey variables
    var hotKeyToggleMenuBarLyrics: HotKey?
    var hotKeyToggleKaraokeLyrics: HotKey?
    var hotKeyShowLyricsWindow: HotKey?
    var hotKeyOffsetIncrease: HotKey?
    var hotKeyOffsetDecrease: HotKey?
    var hotKeyWriteToiTunes: HotKey?
    var hotKeyWrongLyrics: HotKey?
    var hotKeySearchLyrics: HotKey?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        registerUserDefaults()
        #if RELEASE
        AppCenter.start(withAppSecret: "36777a05-06fd-422e-9375-a934b3c835a5", services:[
            Analytics.self,
            Crashes.self
        ])
        #endif

        let controller = AppController.shared

        karaokeLyricsWC = KaraokeLyricsWindowController()
        karaokeLyricsWC?.showWindow(nil)

        MenuBarLyricsController.shared.statusItem.menu = statusBarMenu
        statusBarMenu.delegate = self

        lyricsOffsetStepper.bind(.value,
                                 to: controller,
                                 withKeyPath: #keyPath(AppController.lyricsOffset),
                                 options: [.continuouslyUpdatesValue: true])
        lyricsOffsetTextField.bind(.value,
                                   to: controller,
                                   withKeyPath: #keyPath(AppController.lyricsOffset),
                                   options: [.continuouslyUpdatesValue: true])

        setupHotKeys()

        NSRunningApplication.runningApplications(withBundleIdentifier: lyricsXHelperIdentifier).forEach { $0.terminate() }

        let sharedKeys: [UserDefaults.DefaultsKeys] = [
            .launchAndQuitWithPlayer,
            .preferredPlayerIndex,
        ]
        sharedKeys.forEach {
            groupDefaults.bind(NSBindingName($0.key), withDefaultName: $0)
        }

        #if IS_FOR_MAS
        checkForMASReview(force: true)
        #else
        SUUpdater.shared()?.checkForUpdatesInBackground()
        if #available(OSX 10.12.2, *) {
            observeDefaults(key: .touchBarLyricsEnabled, options: [.new, .initial]) { _, change in
                if change.newValue, TouchBarLyricsController.shared == nil {
                    TouchBarLyricsController.shared = TouchBarLyricsController()
                } else if !change.newValue, TouchBarLyricsController.shared != nil {
                    TouchBarLyricsController.shared = nil
                }
            }
        }
        #endif
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        if AppController.shared.currentLyrics?.metadata.needsPersist == true {
            AppController.shared.currentLyrics?.persist()
        }
        if defaults[.launchAndQuitWithPlayer] {
            let url = Bundle.main.bundleURL
                .appendingPathComponent("Contents/Library/LoginItems/LyricsXHelper.app")
            groupDefaults[.launchHelperTime] = Date()
            do {
                try NSWorkspace.shared.launchApplication(at: url, configuration: [:])
                log("launch LyricsX Helper succeed.")
            } catch {
                log("launch LyricsX Helper failed. reason: \(error)")
            }
        }
    }
    
    @objc func toggleMenuBarLyrics() {
        defaults[.menuBarLyricsEnabled] = !defaults[.menuBarLyricsEnabled]
    }

    @objc func toggleKaraokeLyrics() {
        defaults[.desktopLyricsEnabled] = !defaults[.desktopLyricsEnabled]
    }

    @objc func showLyricsHUD(_ sender: Any?) {
        // Your implementation here
    }

    @objc func increaseOffset(_ sender: Any?) {
        AppController.shared.lyricsOffset += 100
    }

    @objc func decreaseOffset(_ sender: Any?) {
        AppController.shared.lyricsOffset -= 100
    }

    @objc func writeToiTunes(_ sender: Any?) {
        AppController.shared.writeToiTunes(overwrite: true)
    }

    @objc func wrongLyrics(_ sender: Any?) {
        guard let track = selectedPlayer.currentTrack else {
            return
        }
        defaults[.noSearchingTrackIds].append(track.id)
        if defaults[.writeToiTunesAutomatically] {
            track.setLyrics("")
        }
        if let url = AppController.shared.currentLyrics?.metadata.localURL {
            try? FileManager.default.removeItem(at: url)
        }
        AppController.shared.currentLyrics = nil
        AppController.shared.searchCanceller?.cancel()
    }

    @objc func searchLyrics(_ sender: Any?) {
        searchLyricsWC.window?.makeKeyAndOrderFront(nil)
        (searchLyricsWC.contentViewController as! SearchLyricsViewController?)?.reloadKeyword()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupHotKeys() {
        // Bind HotKeys to corresponding actions
        hotKeyToggleMenuBarLyrics = HotKey(key: .l, modifiers: [.command, .option])
        hotKeyToggleMenuBarLyrics?.keyDownHandler = {
            self.toggleMenuBarLyrics()
        }

        hotKeyToggleKaraokeLyrics = HotKey(key: .k, modifiers: [.command, .option])
        hotKeyToggleKaraokeLyrics?.keyDownHandler = {
            self.toggleKaraokeLyrics()
        }

        hotKeyShowLyricsWindow = HotKey(key: .w, modifiers: [.command, .option])
        hotKeyShowLyricsWindow?.keyDownHandler = {
            self.showLyricsHUD(nil)
        }

        hotKeyOffsetIncrease = HotKey(key: .upArrow, modifiers: [.command, .option])
        hotKeyOffsetIncrease?.keyDownHandler = {
            self.increaseOffset(nil)
        }

        hotKeyOffsetDecrease = HotKey(key: .downArrow, modifiers: [.command, .option])
        hotKeyOffsetDecrease?.keyDownHandler = {
            self.decreaseOffset(nil)
        }

        hotKeyWriteToiTunes = HotKey(key: .t, modifiers: [.command, .option])
        hotKeyWriteToiTunes?.keyDownHandler = {
            self.writeToiTunes(nil)
        }

        hotKeyWrongLyrics = HotKey(key: .r, modifiers: [.command, .option])
        hotKeyWrongLyrics?.keyDownHandler = {
            self.wrongLyrics(nil)
        }

        hotKeySearchLyrics = HotKey(key: .s, modifiers: [.command, .option])
        hotKeySearchLyrics?.keyDownHandler = {
            self.searchLyrics(nil)
        }
    }


    // Other existing methods remain unchanged

}
