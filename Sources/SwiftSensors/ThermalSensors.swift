import Foundation
import PrivateAPI

/// A struct representing a thermal sensor reading from the device.
///
/// Thermal sensor readings measure temperature at various points in the device.
/// These measurements are useful for monitoring device health and detecting
/// potential overheating issues.
public struct ThermalSensorReading: BaseSensorReading {
    /// Stable unique identifier for the sensor (uses sensor name to avoid SwiftUI churn)
    public let id: String
    /// The name of the sensor
    public let name: String
    /// The current temperature reading
    public let temperature: Double

    init(name: String, temperature: Double) {
        self.id = name
        self.name = name
        self.temperature = temperature
    }
}

/// A manager actor for thermal sensors
public actor ThermalSensorManager: SensorManager {
    public typealias SensorType = ThermalSensorReading

    /// Shared instance for easy access
    public static let shared = ThermalSensorManager()

    /// Event type for temperature
    private let eventType = Int64(kIOHIDEventTypeTemperature)

    /// Private initializer for singleton pattern
    private init() {}

    /// Get all available thermal sensors with current temperature readings
    public func getAllSensors() async -> [ThermalSensorReading] {
        let temps = SensorUtils.readValues(
            page: kHIDPage_AppleVendor,
            usage: kHIDUsage_AppleVendor_TemperatureSensor,
            eventType: self.eventType,
            fieldBase: Int32(kIOHIDEventTypeTemperature)
        )

        return temps
            .map { name, temp in ThermalSensorReading(name: name, temperature: temp) }
            .sorted { $0.name < $1.name }
    }

    // Legacy method for backward compatibility
    public func getAllThermalSensors() async -> [ThermalSensorReading] {
        await self.getAllSensors()
    }
}
