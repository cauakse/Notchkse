import AppKit
import ImageIO

nonisolated enum Shell {
    /// PATH do usuário + pastas comuns de CLIs (apps GUI não herdam o PATH do terminal).
    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extra = [
            "\(home)/.local/bin", "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
            "\(home)/.bun/bin", "\(home)/.npm-global/bin", "\(home)/.cargo/bin",
            "\(home)/.volta/bin", "\(home)/bin",
        ]
        env["PATH"] = (extra + [env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        return env
    }

    /// Executa e espera terminar. Chame fora da main thread.
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

nonisolated enum AppleScript {
    /// Execute sempre na mesma fila serial (NSAppleScript não é thread-safe).
    static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }
}

nonisolated enum ImageUtils {
    /// Decodifica direto em tamanho reduzido (economiza RAM com capas e prints).
    static func thumbnail(data: Data, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(source: source, maxPixel: maxPixel)
    }

    static func thumbnail(url: URL, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(source: source, maxPixel: maxPixel)
    }

    private static func thumbnail(source: CGImageSource, maxPixel: Int) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
    }

    /// Cor média da imagem, "avivada" para servir de cor de destaque.
    static func accentColor(of image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let ok: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                      bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard ok else { return nil }
        let base = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                           blue: CGFloat(pixel[2]) / 255, alpha: 1)
        return NSColor(hue: base.hueComponent,
                       saturation: min(max(base.saturationComponent, 0.35), 0.85),
                       brightness: max(base.brightnessComponent, 0.8),
                       alpha: 1)
    }
}

extension String {
    /// Remove códigos de cor ANSI da saída de CLIs.
    var strippingANSI: String {
        replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    }
}

enum Haptics {
    static func tap(enabled: Bool) {
        guard enabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
