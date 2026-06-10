import Darwin
import Foundation
import IOKit.ps

protocol MetricsProvider: Sendable {
    func sample() async -> MetricSnapshot
}

final class SystemMetricsProvider: MetricsProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var previousNetwork: (received: UInt64, sent: UInt64, date: Date)?
    private let sensorProvider: SensorProvider

    init(sensorProvider: SensorProvider = UnavailableSensorProvider()) {
        self.sensorProvider = sensorProvider
    }

    func sample() async -> MetricSnapshot {
        await Task.detached(priority: .utility) { [self] in
            let now = Date()
            let cpu = cpuUsage()
            let memory = memoryUsage()
            let disk = diskUsage()
            let network = networkUsage(at: now)
            let battery = batteryStatus()
            let sensors = sensorProvider.read()
            let processes = topProcesses()

            return MetricSnapshot(
                timestamp: now,
                cpuPercent: cpu,
                gpuPercent: nil,
                memoryPercent: memory.percent,
                memoryUsedGB: memory.usedGB,
                memoryTotalGB: memory.totalGB,
                diskPercent: disk.percent,
                diskUsedGB: disk.usedGB,
                diskTotalGB: disk.totalGB,
                networkDownloadBytesPerSecond: network.download,
                networkUploadBytesPerSecond: network.upload,
                temperatureCelsius: sensors.temperatureCelsius,
                fanRPM: sensors.fanRPM,
                batteryPercent: battery.percent,
                isCharging: battery.isCharging,
                topProcesses: processes
            )
        }.value
    }

    private func cpuUsage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let current = (
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )

        lock.lock()
        defer {
            previousCPUTicks = current
            lock.unlock()
        }

        guard let previous = previousCPUTicks else { return 0 }

        let user = current.user &- previous.user
        let system = current.system &- previous.system
        let idle = current.idle &- previous.idle
        let nice = current.nice &- previous.nice
        let total = user + system + idle + nice

        guard total > 0 else { return 0 }
        return min(100, Double(user + system + nice) / Double(total) * 100)
    }

    private func memoryUsage() -> (percent: Double, usedGB: Double, totalGB: Double) {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &statistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS, totalBytes > 0 else { return (0, 0, 0) }

        let active = UInt64(statistics.active_count)
        let wired = UInt64(statistics.wire_count)
        let compressed = UInt64(statistics.compressor_page_count)
        let usedBytes = (active + wired + compressed) * UInt64(pageSize)
        let divisor = 1_073_741_824.0

        return (
            min(100, Double(usedBytes) / Double(totalBytes) * 100),
            Double(usedBytes) / divisor,
            Double(totalBytes) / divisor
        )
    }

    private func diskUsage() -> (percent: Double, usedGB: Double, totalGB: Double) {
        guard let values = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let total = values[.systemSize] as? NSNumber,
              let free = values[.systemFreeSize] as? NSNumber else {
            return (0, 0, 0)
        }

        let totalBytes = total.doubleValue
        let usedBytes = max(0, totalBytes - free.doubleValue)
        let divisor = 1_073_741_824.0

        return (
            totalBytes > 0 ? usedBytes / totalBytes * 100 : 0,
            usedBytes / divisor,
            totalBytes / divisor
        )
    }

    private func networkUsage(at date: Date) -> (download: Double, upload: Double) {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let firstAddress = addressPointer else {
            return (0, 0)
        }
        defer { freeifaddrs(addressPointer) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let interface = pointer?.pointee {
            let name = String(cString: interface.ifa_name)
            if name != "lo0",
               interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               let dataPointer = interface.ifa_data {
                let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
                received += UInt64(data.ifi_ibytes)
                sent += UInt64(data.ifi_obytes)
            }
            pointer = interface.ifa_next
        }

        lock.lock()
        defer {
            previousNetwork = (received, sent, date)
            lock.unlock()
        }

        guard let previous = previousNetwork else { return (0, 0) }
        let duration = max(0.1, date.timeIntervalSince(previous.date))

        return (
            Double(received &- previous.received) / duration,
            Double(sent &- previous.sent) / duration
        )
    }

    private func batteryStatus() -> (percent: Double?, isCharging: Bool?) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any],
              let current = description[kIOPSCurrentCapacityKey] as? Double,
              let maximum = description[kIOPSMaxCapacityKey] as? Double,
              maximum > 0 else {
            return (nil, nil)
        }

        let state = description[kIOPSPowerSourceStateKey] as? String
        return (current / maximum * 100, state == kIOPSACPowerValue)
    }

    private func topProcesses() -> [ProcessUsage] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Ao", "pid=,pcpu=,rss=,comm="]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let text = String(data: data, encoding: .utf8) else { return [] }

            return text
                .split(separator: "\n")
                .compactMap { line -> ProcessUsage? in
                    let parts = line.split(
                        maxSplits: 3,
                        whereSeparator: { $0 == " " || $0 == "\t" }
                    )
                    guard parts.count == 4,
                          let pid = Int32(parts[0]),
                          let cpu = Double(parts[1]),
                          let rss = Double(parts[2]) else {
                        return nil
                    }

                    return ProcessUsage(
                        id: pid,
                        name: URL(fileURLWithPath: String(parts[3])).lastPathComponent,
                        cpuPercent: cpu,
                        memoryMB: rss / 1024
                    )
                }
                .filter { $0.id != ProcessInfo.processInfo.processIdentifier }
        } catch {
            return []
        }
    }
}
