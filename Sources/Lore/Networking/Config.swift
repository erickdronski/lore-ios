import Foundation

/// Environment constants for the Lore Supabase project (`lore`, ref uiuwzymvyrgfyiugqlkp).
///
/// The anon key below is **publishable by design**, it is the Supabase
/// "anon/publishable" role key that ships inside every client build (web and
/// iOS alike). It grants nothing beyond what Row Level Security allows the
/// `anon` role: SELECT on published read surfaces (`place_explore`, `dive`,
/// `tour`, `tour_stop`, non-rejected `fact` rows) and a user's own rows once
/// authenticated. All writes go through Edge Functions with the service-role
/// key server-side; there are no client INSERT policies on `contribution`,
/// `verification`, or `anchor` at all (lore/docs/03-ARCHITECTURE.md §5).
/// Hardcoding it is the same posture as `lore-web`, do not treat it as a
/// secret, and never put the service-role key anywhere near this file.
enum Config {
    /// Public Lore web surface used for legal, support, and share links until a
    /// custom domain is configured and verified.
    static let webURL = URL(string: "https://lore-web-liart.vercel.app")!

    static func placeShareURL(slug: String) -> URL {
        webURL.appending(path: "p").appending(path: slug)
    }

    /// Supabase project base URL.
    static let supabaseURL = URL(string: "https://uiuwzymvyrgfyiugqlkp.supabase.co")!

    /// Supabase anon (publishable) key, see doc comment above.
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVpdXd6eW12eXJnZnlpdWdxbGtwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI5NjMwNzYsImV4cCI6MjA5ODUzOTA3Nn0.4t_e9svhpmXkvr8z595sWrkiQliu6vMrW7wdhuE5I0U"

    /// PostgREST base (`/rest/v1`).
    static var restURL: URL { supabaseURL.appending(path: "rest/v1") }

    /// GoTrue auth base (`/auth/v1`).
    static var authURL: URL { supabaseURL.appending(path: "auth/v1") }

    /// Edge Functions base (`/functions/v1`), e.g. the `streetview` proxy that
    /// keeps the Google Maps key server-side.
    static var functionsURL: URL { supabaseURL.appending(path: "functions/v1") }

    /// Storage base (`/storage/v1`), e.g. the private `journal-photos` bucket.
    static var storageURL: URL { supabaseURL.appending(path: "storage/v1") }

    /// The pilot city. Every read surface is filtered by `city` (docs/00 §8:
    /// Chicago seed, Loop / Riverwalk / Museum Campus).
    static let defaultCity = "chicago"

    // MARK: Feature flags

    /// Render the native MapLibre GL Native map (the flagship map, docs/17 +
    /// docs/22) instead of the MapKit stand-in. Default false so the app builds
    /// and runs today on any machine, MapKit is still the shipped map. Flip to
    /// true ONLY after the MapLibre SPM package compiles on a device with Xcode
    /// (this scaffold cannot compile against MapLibre types headless), then the
    /// map on the Map tab becomes the ported Lore restyle + storied towers.
    static let useMapLibreMap = false
}
