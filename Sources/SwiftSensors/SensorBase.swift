import Foundation
import PrivateAPI

/// Base protocol for all sensor reading types
public protocol BaseSensorReading: Identifiable, Sendable {
    var id: String { get }
    var name: String { get }
}

/// Base protocol for all sensor managers
public protocol SensorManager {
    associatedtype SensorType: BaseSensorReading
    static var shared: Self { get }

    /// Get all available sensors from this manager
    func getAllSensors() async -> [SensorType]
}

/// Common functions for sensor querying and data processing
public enum SensorUtils {
    /// Create a query dictionary for HID matching
    public static func query(page: Int32, usage: Int32) -> [String: Int32] {
        [
            "PrimaryUsagePage": page,
            "PrimaryUsage": usage,
        ]
    }

    /// Calculate event field base for a given type
    public static func eventFieldBase(_ type: Int32) -> Int32 {
        type << 16
    }

    /// Read all matching IOHID sensor values in a single memory-safe pass without CF leaks
    public static func readValues(
        page: Int32,
        usage: Int32,
        eventType: Int64,
        fieldBase: Int32
    ) -> [String: Double] {
        let raw = IOHIDReadSensorValues(page, usage, eventType, fieldBase)
        var result: [String: Double] = [:]
        result.reserveCapacity(raw.count)
        for (name, number) in raw {
            result[name] = number.doubleValue
        }
        return result
    }
}
