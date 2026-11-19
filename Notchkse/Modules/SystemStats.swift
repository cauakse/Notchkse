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
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
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
        if let cpuValue { cpu = cpuValue }
        if let gpuValue { gpu = gpuValue }
        ram = ramFraction
        ramUsedGB = usedGB
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

/// Ícone de placa de vídeo desenhado à mão (o SF Symbols não tem um de GPU).
/// Corpo com ventoinha vazada, suporte à esquerda e conectores embaixo.
struct GPUIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let u = min(rect.width, rect.height) / 16
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: rect.minX + x * u, y: rect.minY + y * u, width: w * u, height: h * u)
        }
        var p = Path()
        // Corpo da placa
        p.addRoundedRect(in: r(0.5, 2, 15, 10), cornerSize: CGSize(width: 2.4 * u, height: 2.4 * u))
        // Duas ventoinhas vazadas (even-odd), cada uma com o miolo preenchido
        p.addEllipse(in: r(1.9, 3.4, 7.2, 7.2))
        p.addEllipse(in: r(4.4, 5.9, 2.2, 2.2))
        p.addEllipse(in: r(9.6, 4.6, 4.8, 4.8))
        p.addEllipse(in: r(11.25, 6.25, 1.5, 1.5))
        // Contatos do slot PCIe
        p.addRoundedRect(in: r(3, 12.9, 4.5, 2), cornerSize: CGSize(width: 0.5 * u, height: 0.5 * u))
        p.addRoundedRect(in: r(8.5, 12.9, 4.5, 2), cornerSize: CGSize(width: 0.5 * u, height: 0.5 * u))
        return p
    }
}

enum GaugeIcon {
    case symbol(String)
    case gpu

    @ViewBuilder
    func view(_ style: Color) -> some View {
        switch self {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: 13, weight: .semibold)).foregroundStyle(style)
        case .gpu:
            GPUIconShape().fill(style, style: FillStyle(eoFill: true)).frame(width: 16, height: 16)
        }
    }
}

/// Ícone em branco translúcido de fundo, preenchido de baixo para cima
/// com branco sólido conforme o uso.
struct UsageGauge: View {
    let icon: GaugeIcon
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                icon.view(.white.opacity(0.22))
                icon.view(.white)
                    .mask(alignment: .bottom) {
                        GeometryReader { geo in
                            Rectangle()
                                .frame(height: geo.size.height * min(max(value, 0), 1))
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
            }
            .frame(width: 16, height: 16)
            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .frame(minWidth: 26, alignment: .leading)
        }
        .help("\(label): \(Int((value * 100).rounded()))%")
    }
}

/// Indicadores de CPU, GPU e RAM no cabeçalho do notch aberto.
struct HeaderStats: View {
    @Environment(AppContext.self) private var ctx

    var body: some View {
        let stats = ctx.stats
        HStack(spacing: 8) {
            UsageGauge(icon: .symbol("cpu.fill"), label: "CPU", value: stats.cpu)
            UsageGauge(icon: .gpu, label: "GPU", value: stats.gpu)
            UsageGauge(icon: .symbol("memorychip.fill"), label: String(format: "RAM (%.1f GB)", stats.ramUsedGB), value: stats.ram)
        }
        .onAppear { stats.beginObserving() }
        .onDisappear { stats.endObserving() }
    }
}
