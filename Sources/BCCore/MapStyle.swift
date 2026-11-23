import CoreGraphics

/// Built-in default style for standard Garmin type codes (TYP files are not interpreted yet).
public enum MapStyle {
    static func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }

    public static let background = rgb(242, 239, 233)

    /// (fill color, draw order) for polygon types.
    public static func polygon(_ t: Int) -> (CGColor, Int)? {
        switch t {
        case 0x01, 0x02, 0x0c: return (rgb(228, 222, 210), 10)           // city / industrial
        case 0x03: return (rgb(215, 215, 200), 12)
        case 0x04, 0x05: return (rgb(225, 225, 225), 14)                 // parking
        case 0x07, 0x08, 0x09, 0x0a, 0x0b: return (rgb(233, 225, 215), 13)
        case 0x13: return (rgb(215, 205, 195), 15)                       // building
        case 0x14, 0x15, 0x16, 0x17: return (rgb(205, 230, 190), 5)      // parks / forest reserves
        case 0x18, 0x19: return (rgb(200, 235, 175), 11)                 // golf / sports
        case 0x1a: return (rgb(195, 215, 185), 11)                       // cemetery
        case 0x28, 0x32, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46:
            return (rgb(170, 211, 235), 20)                              // water
        case 0x47, 0x48, 0x49: return (rgb(170, 211, 235), 20)
        case 0x4c: return (rgb(190, 225, 240), 20)
        case 0x4d: return (rgb(235, 245, 250), 21)                       // glacier
        case 0x4e, 0x4f: return (rgb(215, 232, 185), 6)                  // orchard / scrub
        case 0x50: return (rgb(173, 209, 158), 6)                        // woods
        case 0x51: return (rgb(205, 230, 215), 7)                        // wetland
        case 0x52: return (rgb(225, 235, 220), 7)
        default: return nil
        }
    }

    /// (stroke color, width in px at normal zoom, draw order, dashed) for polyline types.
    public static func line(_ t: Int) -> (CGColor, CGFloat, Int, Bool)? {
        switch t {
        case 0x01: return (rgb(230, 120, 90), 4.5, 50, false)
        case 0x02: return (rgb(240, 160, 90), 4, 49, false)
        case 0x03: return (rgb(245, 200, 100), 3.5, 48, false)
        case 0x04: return (rgb(250, 230, 130), 3, 47, false)
        case 0x05: return (rgb(255, 255, 255), 2.5, 46, false)
        case 0x06: return (rgb(255, 255, 255), 2, 45, false)
        case 0x07: return (rgb(240, 240, 240), 1.2, 44, false)
        case 0x08, 0x09, 0x0b, 0x0c: return (rgb(250, 220, 130), 2.5, 46, false)
        case 0x0a: return (rgb(190, 160, 110), 1.4, 43, true)            // unpaved
        case 0x14, 0x13: return (rgb(110, 110, 110), 1.2, 42, true)       // railway
        case 0x15: return (rgb(110, 170, 220), 1, 30, false)              // shoreline
        case 0x16, 0x0d: return (rgb(150, 90, 40), 1.1, 41, true)         // trail
        case 0x18, 0x1f, 0x26, 0x27, 0x29: return (rgb(120, 180, 225), 1.2, 31, false) // streams
        case 0x1a, 0x1b: return (rgb(100, 120, 200), 1.2, 40, true)       // ferry
        case 0x1c, 0x1d, 0x1e: return (rgb(160, 120, 170), 1.2, 39, true) // boundary
        case 0x20: return (rgb(205, 180, 150), 0.5, 25, false)            // minor contour
        case 0x21: return (rgb(190, 160, 130), 0.7, 26, false)
        case 0x22: return (rgb(170, 135, 100), 1.0, 27, false)            // major contour
        case 0x23, 0x24, 0x25: return (rgb(150, 190, 220), 0.6, 28, false)
        default: return nil
        }
    }

    public static func point(_ t: Int) -> (CGColor, CGFloat)? {
        switch t {
        case 0x01...0x0c: return (rgb(90, 90, 90), 3)      // cities
        case 0x11...0x30: return (rgb(60, 110, 190), 2.5)  // POIs
        case 0x62...0x66: return (rgb(60, 140, 200), 2)
        default: return nil
        }
    }
}
