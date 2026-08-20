import Foundation

enum Palette {
    static let outline      = RGBA(hex: 0x17274E)
    static let outlineSoft  = RGBA(hex: 0x24386B)

    static let rimGreen     = RGBA(hex: 0x5FA83F)
    static let rimGreenLit  = RGBA(hex: 0x76C24E)
    static let rimGreenDark = RGBA(hex: 0x3B7530)
    static let flesh        = RGBA(hex: 0xE4EC90)
    static let fleshDot     = RGBA(hex: 0xC9D97A)

    // Readout plaque, set into the pit.
    static let plaque       = RGBA(hex: 0x4C2C18)
    static let plaqueLit    = RGBA(hex: 0x5E3A22)
    static let plaqueDark   = RGBA(hex: 0x321B0D)

    static let ink          = RGBA(hex: 0xF3ECD2)
    static let inkDim       = RGBA(hex: 0x9A8468)

    static let leaf         = RGBA(hex: 0x57A03E)
    static let leafDark     = RGBA(hex: 0x2F6B2A)
    static let bud          = RGBA(hex: 0xEDE9F6)
    static let budShade     = RGBA(hex: 0xC6C0DC)

    // Progress ring / motion glint tint by phase.
    static let accentFocus    = RGBA(hex: 0x8FD65B)
    static let accentFocusLit = RGBA(hex: 0xD8F5C0)
    static let accentBreak    = RGBA(hex: 0x3E8FB0)
    static let accentBreakLit = RGBA(hex: 0xA9DCEA)
}
