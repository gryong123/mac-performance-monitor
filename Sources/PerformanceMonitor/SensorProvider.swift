import Foundation
import IOKit

struct SensorReading: Sendable {
    let temperatureCelsius: Double?
    let fanRPM: Double?
}

protocol SensorProvider: Sendable {
    func read() -> SensorReading
}

struct AppleSmartBatterySensorProvider: SensorProvider {
    func read() -> SensorReading {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else {
            return SensorReading(temperatureCelsius: nil, fanRPM: nil)
        }
        defer { IOObjectRelease(service) }

        guard let rawTemperature = IORegistryEntryCreateCFProperty(
            service,
            "Temperature" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber else {
            return SensorReading(temperatureCelsius: nil, fanRPM: nil)
        }

        return SensorReading(
            temperatureCelsius: Self.celsius(fromRawValue: rawTemperature.doubleValue),
            fanRPM: nil
        )
    }

    static func celsius(fromRawValue rawValue: Double) -> Double? {
        let value = rawValue / 100
        guard (0...100).contains(value) else { return nil }
        return value
    }
}

struct UnavailableSensorProvider: SensorProvider {
    func read() -> SensorReading {
        SensorReading(temperatureCelsius: nil, fanRPM: nil)
    }
}

// CPU/GPU 核心温度与风扇后续仅允许接入签名后的只读 XPC 辅助程序。
// 主应用只读取公开的电池温度，不写入 SMC，也不调整风扇或处理器参数。
protocol PrivilegedSensorService {
    func readSensors(completion: @escaping (SensorReading) -> Void)
}
