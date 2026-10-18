import SwiftUI

/// App shortcuts. They open through Kutu Home's kutu://launch/<package> link on the TV.
struct TVApp: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let color: Color

    var link: String { "kutu://launch/\(id)" }

    static let all: [TVApp] = [
        TVApp(id: "com.netflix.ninja", name: "Netflix", symbol: "play.rectangle.fill", color: Color(red: 0.75, green: 0.05, blue: 0.07)),
        TVApp(id: "com.google.android.youtube.tv", name: "YouTube", symbol: "play.fill", color: Color(red: 0.9, green: 0.1, blue: 0.1)),
        TVApp(id: "com.amazon.amazonvideo.livingroom", name: "Prime Video", symbol: "play.tv.fill", color: Color(red: 0.0, green: 0.48, blue: 0.85)),
        TVApp(id: "com.disney.disneyplus", name: "Disney+", symbol: "sparkles.tv.fill", color: Color(red: 0.05, green: 0.15, blue: 0.45)),
        TVApp(id: "com.wbd.stream", name: "Max", symbol: "film.fill", color: Color(red: 0.25, green: 0.1, blue: 0.75)),
        TVApp(id: "com.apple.atve.androidtv.appletv", name: "Apple TV", symbol: "appletv.fill", color: Color(white: 0.25)),
        TVApp(id: "com.beonetv.tod", name: "TOD", symbol: "sportscourt.fill", color: Color(red: 0.0, green: 0.55, blue: 0.5)),
        TVApp(id: "com.google.android.youtube.tvmusic", name: "YouTube Music", symbol: "music.note", color: Color(red: 0.7, green: 0.05, blue: 0.2)),
        TVApp(id: "com.phlox.tvwebbrowser", name: "TV Bro", symbol: "globe", color: Color(red: 0.1, green: 0.55, blue: 0.3)),
        TVApp(id: "ch.protonvpn.android", name: "Proton VPN", symbol: "lock.shield.fill", color: Color(red: 0.4, green: 0.25, blue: 0.75)),
        TVApp(id: "tv", name: "Canlı TV", symbol: "antenna.radiowaves.left.and.right", color: Color(red: 0.2, green: 0.3, blue: 0.45)),
        TVApp(id: "com.android.tv.settings", name: "Ayarlar", symbol: "gearshape.fill", color: Color(white: 0.3)),
    ]
}
