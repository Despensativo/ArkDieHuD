import Foundation
import PrivateAPI

/// An enum representing a power sensor type
public enum PowerSensorType: Sendable {
    case voltage
    case current
}

/// A struct representing a voltage sensor
public struct VoltageSensorReading: BaseSensorReading {
    /// Stable unique identifier for the sensor
    public let id: String
    /// The name of the sensor
    public let name: String
    /// The current voltage reading (in Volts)
    public let voltage: Double

    init(name: String, voltage: Double) {
        self.id = name
        self.name = name
        self.voltage = voltage
    }
}

/// A struct representing a current sensor
public struct CurrentSensorReading: BaseSensorReading {
    /// Stable unique identifier for the sensor
    public let id: String
    /// The name of the sensor
    public let name: String
    /// The current amperage reading (in Amperes)
    public let current: Double

    init(name: String, current: Double) {
        self.id = name
        self.name = name
        self.current = current
    }
}

/// A struct for representing any power sensor
public struct PowerSensorReading: BaseSensorReading {
    /// Stable unique identifier for the sensor
    public let id: String
    /// The name of the sensor
    public let name: String
    /// The sensor type (voltage or current)
    public let type: PowerSensorType
    /// The sensor value
    public let value: Double

    /// Convenience property to get voltage (if this is a voltage sensor)
    public var voltage: Double? {
        self.type == .voltage ? self.value : nil
    }

    /// Convenience property to get current (if this is a current sensor)
    public var current: Double? {
        self.type == .current ? self.value : nil
    }

    init(name: String, type: PowerSensorType, value: Double) {
        self.id = "\(type)-\(name)"
        self.name = name
        self.type = type
        self.value = value
    }
}

/// A manager actor for power sensors (voltage and current)
public actor PowerSensorManager: SensorManager {
    public typealias SensorType = PowerSensorReading

    /// Shared instance for easy access
    public static let shared = PowerSensorManager()

    /// Event type for power values
    private let eventType = Int64(kIOHIDEventTypePower)

    /// Private initializer for singleton pattern
    private init() {}

    /// Get all available power sensors (both voltage and current)
    public func getAllSensors() async -> [PowerSensorReading] {
        let voltageSensors = self.getSpecificSensors(
            usage: kHIDUsage_AppleVendorPowerSensor_Voltage,
            type: .voltage
        )

        let currentSensors = self.getSpecificSensors(
            usage: kHIDUsage_AppleVendorPowerSensor_Current,
            type: .current
        )

        return (voltageSensors + currentSensors).sorted { $0.name < $1.name }
    }

    /// Helper method to get sensors of a specific type
    private func getSpecificSensors(usage: Int32, type: PowerSensorType) -> [PowerSensorReading] {
        let values = SensorUtils.readValues(
            page: kHIDPage_AppleVendorPowerSensor,
            usage: usage,
            eventType: self.eventType,
            fieldBase: Int32(kIOHIDEventTypePower)
        )

        return values.map { name, value in
            PowerSensorReading(name: name, type: type, value: value)
        }
    }

    /// Get all available voltage sensors with current voltage readings
    public func getAllVoltageSensors() async -> [VoltageSensorReading] {
        let voltages = SensorUtils.readValues(
            page: kHIDPage_AppleVendorPowerSensor,
            usage: kHIDUsage_AppleVendorPowerSensor_Voltage,
            eventType: self.eventType,
            fieldBase: Int32(kIOHIDEventTypePower)
        )

        return voltages
            .map { name, voltage in VoltageSensorReading(name: name, voltage: voltage) }
            .sorted { $0.name < $1.name }
    }

    /// Get all available current sensors with current amperage readings
    public func getAllCurrentSensors() async -> [CurrentSensorReading] {
        let currents = SensorUtils.readValues(
            page: kHIDPage_AppleVendorPowerSensor,
            usage: kHIDUsage_AppleVendorPowerSensor_Current,
            eventType: self.eventType,
            fieldBase: Int32(kIOHIDEventTypePower)
        )

        return currents
            .map { name, current in CurrentSensorReading(name: name, current: current) }
            .sorted { $0.name < $1.name }
    }
}
