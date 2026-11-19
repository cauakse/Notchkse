import Darwin
import IOKit
import Observation
import SwiftUI

/// CPU, GPU e RAM. Só faz leitura enquanto o card está na tela.
@Observable
final class SystemStats {
    private(set) var cpu: Double = 0
    private(set) var gpu: Double = 0
    private(set) var ram: Double = 0
    private(set) var ramUsedGB: Double = 0

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var previousTicks: [UInt32]?

    /// Contagem de referência: várias views podem pedir leitura ao mesmo tempo.
    func beginObserving() {
        viewers += 1
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func endObserving() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        timer?.invalidate()
        timer = nil
        previousTicks = nil
    }

    private func sample() {
        let cpuValue = readCPU()
        let gpuValue = Self.readGPU()
        let (ramFraction, usedGB) = Self.readRAM()
        withAnimation(.easeInOut(duration: 0.6)) {
            if let cpuValue { cpu = cpuValue }
            if let gpuValue { gpu = gpuValue }
            ram = ramFraction
            ramUsedGB = usedGB
        }
    }

    /// Diferença de "ticks" de todos os núcleos desde a última leitura.
    private func readCPU() -> Double? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let ticks = (0..<Int(infoCount)).map { UInt32(bitPattern: info[$0]) }
        defer { previousTicks = ticks }
        guard let previous = previousTicks, previous.count == ticks.count else { return nil }

        var used: UInt64 = 0, total: UInt64 = 0
        let stride = Int(CPU_STATE_MAX)
        for core in 0..<Int(count) {
            for state in 0..<stride {
                let delta = UInt64(ticks[core * stride + state] &- previous[core * stride + state])
                total += delta
                if state != Int(CPU_STATE_IDLE) { used += delta }
            }
        }
        return total > 0 ? Double(used) / Double(total) : 0
    }

    /// Apple Silicon expõe a utilização da GPU no IORegistry (sem root).
    private static func readGPU() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
               let value = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber {
                best = max(best ?? 0, value.doubleValue / 100)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return best
    }

    /// "Usada" como no Monitor de Atividade: ativa + wired + comprimida.
    private static func readRAM() -> (Double, Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard result == KERN_SUCCESS, total > 0 else { return (0, 0) }
        let page = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        return (min(used / total, 1), used / 1_073_741_824)
    }
}

// MARK: - Medidor: ícone claro preenchido de baixo para cima com cor forte

struct UsageGauge: View {
    let symbol: String
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(color.opacity(0.25))
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(color.gradient)
                    .mask(alignment: .bottom) {
                        GeometryReader { geo in
                            Rectangle()
                                .frame(height: geo.size.height * min(max(value, 0), 1))
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
            }
            .frame(width: 34, height: 34)
            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .contentTransition(.numericText(value: value))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    static func tint(for value: Double, base: Color) -> Color {
        value >= 0.9 ? .red : (value >= 0.75 ? .orange : base)
    }
}

struct SystemStatsCard: View {
    @Environment(AppContext.self) private var ctx

    var body: some View {
        let stats = ctx.stats
        VStack(alignment: .leading, spacing: 8) {
            Text("Sistema").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accentSoft)
            HStack(spacing: 10) {
                UsageGauge(symbol: "cpu.fill", label: "CPU", value: stats.cpu,
                           color: UsageGauge.tint(for: stats.cpu, base: Color(red: 0.36, green: 0.78, blue: 1.0)))
                UsageGauge(symbol: "square.stack.3d.down.forward.fill", label: "GPU", value: stats.gpu,
                           color: UsageGauge.tint(for: stats.gpu, base: Color(red: 0.70, green: 0.45, blue: 1.0)))
                UsageGauge(symbol: "memorychip.fill", label: "RAM", value: stats.ram,
                           color: UsageGauge.tint(for: stats.ram, base: Color(red: 0.35, green: 0.90, blue: 0.55)))
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            Text(String(format: "%.1f GB em uso", stats.ramUsedGB))
                .font(.system(size: 9)).foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
        .onAppear { stats.beginObserving() }
        .onDisappear { stats.endObserving() }
    }
}
