// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Common

// MARK: Protocol
public protocol TabDataStore {
    func fetchWindowData() async -> WindowData
    func saveWindowData(window: WindowData) async
    func clearAllWindowsData() async
    func fetchWindowData(withID id: UUID) async -> WindowData?
    func fetchAllWindowsData() async -> [WindowData]
    func clearWindowData(for id: UUID) async
}

public actor DefaultTabDataStore: TabDataStore {
    // MARK: Variables
    let browserKitInfo = BrowserKitInformation.shared
    static let storePath = "codableWindowsState.archive"
    static let profilePath = "profile.profile"
    static let backupPath = "profile.backup"
    private var logger: Logger = DefaultLogger.shared
    private var windowDataToSave: WindowData?
    private var nextSaveIsScheduled = false
    private let throttleTime: UInt64

    public init(throttleTime: UInt64 = 5_000_000_000) {
        self.throttleTime = throttleTime
    }

    // MARK: - URL Utils

    private var windowDataDirectoryURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: browserKitInfo.sharedContainerIdentifier)?
            .appendingPathComponent(DefaultTabDataStore.profilePath)
    }

    private var windowDataBackupDirectoryURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: browserKitInfo.sharedContainerIdentifier)?
            .appendingPathComponent(DefaultTabDataStore.backupPath)
    }

    private func windowURLPath(for windowID: UUID, isBackup: Bool) -> URL? {
        guard let baseURL = isBackup ? windowDataBackupDirectoryURL: windowDataDirectoryURL else {
            return nil
        }
        let baseFilePath = isBackup ? DefaultTabDataStore.backupPath + "_\(windowID.uuidString)" : DefaultTabDataStore.storePath + "_\(windowID.uuidString)"

        return baseURL.appendingPathComponent(baseFilePath)
    }

    // MARK: Fetching Window Data

    public func fetchWindowData() async -> WindowData {
        return WindowData(id: UUID(), isPrimary: true, activeTabId: UUID(), tabData: [])
    }

    private func fetchWindowData(withID id: UUID, isBackup: Bool) async -> WindowData? {
        guard let profileURL = self.windowURLPath(for: id, isBackup: isBackup) else {
            return nil
        }
        do {
            let windowData = try await decodeWindowData(from: profileURL)
            return windowData
        } catch {
            return nil
        }
    }

    public func fetchWindowData(withID id: UUID) async -> WindowData? {
        guard let profileURL = self.windowURLPath(for: id, isBackup: false) else {
            return nil
        }
        do {
            let windowData = try await decodeWindowData(from: profileURL)
            return windowData
        } catch {
            logger.log("Error fetching window data: \(error)",
                       level: .debug,
                       category: .tabs)
            guard let backupURL = windowDataBackupDirectoryURL else {
                return nil
            }
            do {
                let backupWindowData = try await decodeWindowData(from: backupURL)
                return backupWindowData
            } catch {
                logger.log("Error fetching backup window data: \(error)",
                           level: .debug,
                           category: .tabs)
            }
            return nil
        }
    }

    public func fetchAllWindowsData() async -> [WindowData] {
        guard let profileURL = windowDataDirectoryURL else {
            return [WindowData]()
        }

        do {
            guard let fileURLs = try self.filesFromDirectoryAtPath(path: profileURL) else {
                return [WindowData]()
            }
            do {
                let windowsData = try await self.parseWindowDataFiles(fromURLs: fileURLs)
                return windowsData
            }
        } catch {
            logger.log("Error fetching all window data: \(error)",
                       level: .debug,
                       category: .tabs)
            guard let backupURL = windowDataBackupDirectoryURL else {
                return [WindowData]()
            }
            do {
                guard let fileURLs = try self.filesFromDirectoryAtPath(path: backupURL) else {
                    return [WindowData]()
                }

                do {
                    let windowsData = try await self.parseWindowDataFiles(fromURLs: fileURLs)
                    return windowsData
                }
            } catch {
                logger.log("Error fetching all window data from backup: \(error)",
                           level: .debug,
                           category: .tabs)
                return [WindowData]()
            }
        }
    }

    private func filesFromDirectoryAtPath(path: URL) throws -> [URL]? {
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: path,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles)
        return fileURLs
    }

    private func parseWindowDataFiles(fromURLs urlList: [URL]) async throws -> [WindowData] {
        var windowsData: [WindowData] = []
        for fileURL in urlList {
            do {
                let windowData = try await decodeWindowData(from: fileURL)
                windowsData.append(windowData)
            }
        }
        return windowsData
    }

    private func decodeWindowData(from fileURL: URL) async throws -> WindowData {
        do {
            let data = try Data(contentsOf: fileURL)
            let windowData = try JSONDecoder().decode(WindowData.self, from: data)
            return windowData
        } catch {
            logger.log("Error decoding window data: \(error)",
                       level: .debug,
                       category: .tabs)
            throw error
        }
    }

    // MARK: - Saving Data

    public func saveWindowData(window: WindowData) async {
        guard let windowSavingPath = self.windowURLPath(for: window.id, isBackup: false)
        else {
            return
        }

        if checkIfFileExistsAtPath(path: windowSavingPath) {
            createWindowDataBackup(window: window, windowSavingPath: windowSavingPath)
        } else {
            if let windowDataDirectoryURL = windowDataDirectoryURL,
               !self.checkIfFileExistsAtPath(path: windowDataDirectoryURL) {
                self.createDirectoryAtPath(path: windowDataDirectoryURL)
            }
        }
        await writeWindowDataToFileWithThrottle(window: window, path: windowSavingPath)
    }

    private func createWindowDataBackup(window: WindowData, windowSavingPath: URL) {
        guard let backupWindowSavingPath = self.windowURLPath(for: window.id, isBackup: true),
              let backupDirectoryPath = self.windowDataBackupDirectoryURL else {
            return
        }
        if !self.checkIfFileExistsAtPath(path: backupDirectoryPath) {
            self.createDirectoryAtPath(path: backupDirectoryPath)
        }
        do {
            try FileManager.default.copyItem(at: windowSavingPath, to: backupWindowSavingPath)
        } catch {
            self.logger.log("Failed to create window data backup: \(error)",
                            level: .debug,
                            category: .tabs)
        }
    }

    // Throttles the saving of the data so that it happens every 'throttleTime' nanoseconds
    // as long as their is new data to be saved
    private func writeWindowDataToFileWithThrottle(window: WindowData, path: URL) async {
        // Hold onto a copy of the latest window data so whenever the save happens it is using the latest
        windowDataToSave = window

        // Ignore the request because a save is already scheduled to happen
        guard !nextSaveIsScheduled else { return }

        // Set the guard bool to true so no new saves can be initiated while waiting
        nextSaveIsScheduled = true

        // Dispatch to a task so as not to block the caller
        Task {
            // Once the throttle time has passed initiate the save and reset the bool
            try? await Task.sleep(nanoseconds: throttleTime)
            nextSaveIsScheduled = false

            do {
                guard let windowDataToSave = windowDataToSave else {
                    logger.log("Tried to save window data but found nil",
                               level: .fatal,
                               category: .tabs)
                    return
                }
                try await self.writeWindowData(windowData: windowDataToSave, to: path)
            } catch {
                logger.log("Failed to save window data: \(error)",
                           level: .debug,
                           category: .tabs)
            }
        }
    }

    private func checkIfFileExistsAtPath(path: URL) -> Bool {
        return FileManager.default.fileExists(atPath: path.path)
    }

    private func createDirectoryAtPath(path: URL) {
        do {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        } catch {
            self.logger.log("Failed to create window data directory: \(error.localizedDescription) for path: \(path.path)", level: .debug, category: .tabs)
        }
    }

    private func writeWindowData(windowData: WindowData, to url: URL) async throws {
        let data = try JSONEncoder().encode(windowData)
        try data.write(to: url, options: .atomicWrite)
    }

    // MARK: - Deleting Window Data

    public func clearWindowData(for id: UUID) async {
        guard let profileURL = self.windowURLPath(for: id, isBackup: false) else {
            return
        }
        guard let backupURL = self.windowURLPath(for: id, isBackup: true) else {
            return
        }
        await self.removeFileAt(path: profileURL)
        await self.removeFileAt(path: backupURL)
    }

    public func clearAllWindowsData() async {
        guard let profileURL = windowDataDirectoryURL, let backupURL = windowDataBackupDirectoryURL else {
            return
        }
        await self.removeAllFilesAt(path: profileURL)
        await self.removeAllFilesAt(path: backupURL)
    }

    private func removeFileAt(path: URL) async {
        do {
            try FileManager.default.removeItem(at: path)
            return
        } catch {
            logger.log("Error while clearing window data: \(error)",
                       level: .debug,
                       category: .tabs)
        }
    }
    private func removeAllFilesAt(path: URL) async {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: path,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles)
            for fileURL in fileURLs {
                await self.removeFileAt(path: fileURL)
            }
        } catch {
            logger.log("Error fetching all window data for clearing: \(error)",
                       level: .debug,
                       category: .tabs)
        }
    }
}
