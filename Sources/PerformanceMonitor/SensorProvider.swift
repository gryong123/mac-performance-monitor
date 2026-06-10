import Foundation

struct SensorReading: Sendable {
    let temperatureCelsius: Double?
    let fanRPM: Double?
}

protocol SensorProvider: Sendable {
    func read() -> SensorReading
}

struct UnavailableSensorProvider: SensorProvider {
    func read() -> SensorReading {
        SensorReading(temperatureCelsius: nil, fanRPM: nil)
    }
}

// 安全占位接口：后续仅允许接入签名后的只读 XPC 辅助程序。
// 主应用不会直接写入 SMC，也不会调整风扇或处理器参数。
protocol PrivilegedSensorService {
    func readSensors(completion: @escaping (SensorReading) -> Void)
}
