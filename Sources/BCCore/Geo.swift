import Foundation

/// Garmin map units: 24-bit, full circle = 2^24.
public let unitsPerCircle = 16777216.0
public let degPerUnit = 360.0 / unitsPerCircle

public enum Merc {
    /// Web-Mercator normalised coordinates, x,y in [0,1], y grows southwards.
    @inline(__always) public static func x(lon: Double) -> Double { lon / 360.0 + 0.5 }
    @inline(__always) public static func y(lat: Double) -> Double {
        let s = sin(max(-85.0511, min(85.0511, lat)) * .pi / 180)
        return 0.5 - log((1 + s) / (1 - s)) / (4 * .pi)
    }
    public static func lon(x: Double) -> Double { (x - 0.5) * 360 }
    public static func lat(y: Double) -> Double {
        let n = .pi * (1 - 2 * y)
        return atan(sinh(n)) * 180 / .pi
    }
    @inline(__always) public static func x(unit: Int) -> Double { Double(unit) / unitsPerCircle + 0.5 }
    @inline(__always) public static func y(unit: Int) -> Double { y(lat: Double(unit) * degPerUnit) }
}
