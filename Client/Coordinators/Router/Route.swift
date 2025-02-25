// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// An enumeration representing different navigational routes in an application.
enum Route: Equatable {
    /// Represents a search route that takes a URL, a boolean value indicating whether the search is private or not and an optional set of search options.
    ///
    /// - Parameters:
    ///   - url: A `URL` object representing the URL to be searched. Pass `nil` if the search does not require a URL.
    ///   - isPrivate: A boolean value indicating whether the search is private or not.
    ///   - options: An optional set of `SearchOptions` values that can be used to customize the search behavior.
    case search(url: URL?, isPrivate: Bool, options: Set<SearchOptions>? = nil)

    /// Represents a search route that takes a URL and a tab identifier.
    ///
    /// - Parameters:
    ///   - url: A `URL` object representing the URL to be searched. Can be `nil`.
    ///   - tabId: A string representing the identifier of the tab where the search should be performed.
    case searchURL(url: URL?, tabId: String)

    /// Represents a search route that takes a query string.
    ///
    /// - Parameter query: A string representing the query to be searched.
    case searchQuery(query: String)

    /// Represents a route for sending Glean data.
    ///
    /// - Parameter url: A `URL` object representing the URL to send Glean data to.
    case glean(url: URL)

    /// Represents a home panel route that takes a `HomepanelSection` value indicating the section to be displayed.
    ///
    /// - Parameter section: An instance of `HomepanelSection` indicating the section of the home panel to be displayed.
    case homepanel(section: HomepanelSection)

    /// Represents a settings route that takes a `SettingsSection` value indicating the settings section to be displayed.
    ///
    /// - Parameter section: An instance of `SettingsSection` indicating the section of the settings menu to be displayed.
    case settings(section: SettingsSection)

    /// Represents an application action route that takes an `AppAction` value indicating the action to be performed.
    ///
    /// - Parameter action: An instance of `AppAction` indicating the application action to be performed.
    case action(action: AppAction)

    /// Represents a Firefox account sign-in route that takes an `FxALaunchParams` object indicating the parameters for the sign-in.
    ///
    /// - Parameter params: An instance of `FxALaunchParams` containing the parameters for the sign-in.
    case fxaSignIn(params: FxALaunchParams)

    /// Represents a default browser route that takes a `DefaultBrowserSection` value indicating the section to be displayed.
    ///
    /// - Parameter section: An instance of `DefaultBrowserSection` indicating the section of the default browser settings to be displayed.
    case defaultBrowser(section: DefaultBrowserSection)

    /// An enumeration representing different sections of the home panel.
    enum HomepanelSection: String, CaseIterable, Equatable {
        case bookmarks
        case topSites = "top-sites"
        case history
        case readingList = "reading-list"
        case downloads
        case newPrivateTab = "new-private-tab"
        case newTab = "new-tab"
    }

    /// An enumeration representing different sections of the settings menu.
    enum SettingsSection: String, CaseIterable, Equatable {
        case clearPrivateData = "clear-private-data"
        case newTab = "newtab"
        case homePage = "homepage"
        case mailto
        case search
        case fxa
        case systemDefaultBrowser = "system-default-browser"
        case wallpaper
        case theme
        case contentBlocker
        case toolbar
        case tabs
        case topSites
        case general
    }

    /// An enumeration representing different actions that can be performed within the application.
    enum AppAction: String, CaseIterable, Equatable {
        case closePrivateTabs = "close-private-tabs"
        case presentDefaultBrowserOnboarding
        case showQRCode
    }

    /// An enumeration representing different sections of the default browser settings.
    enum DefaultBrowserSection: String, CaseIterable, Equatable {
        case tutorial
        case systemSettings = "system-settings"
    }

    /// An enumeration representing options that can be used in a search feature.
    enum SearchOptions: Equatable {
        /// An option to focus the user's attention on the location field of the search interface.
        case focusLocationField

        /// An option to switch to a normal search mode.
        case switchToNormalMode

        /// An option to switch to a privacy mode that may hide or obscure search results and prevent data sharing.
        case switchToPrivacyMode
    }
}
