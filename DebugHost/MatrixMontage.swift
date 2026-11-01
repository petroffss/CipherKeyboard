#if DEBUG && os(macOS)
    import AppKit
    import Foundation

    /// Native, dependency-free contact sheets for independent inspection of every captured frame.
    @main enum MatrixMontage {
        struct Frame: Decodable {
            let kind: String
            let width: Int
            let orientation: String
            let theme: String
            let state: String
            let file: String
        }
        struct Manifest: Decodable { let frames: [Frame] }
        @MainActor static func main() throws {
            guard CommandLine.arguments.count == 3 else { exit(2) }
            let input = URL(fileURLWithPath: CommandLine.arguments[1])
            let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: input))
            for (state, frames) in Dictionary(grouping: manifest.frames, by: \.state) {
                let size = NSSize(width: 1200, height: state == "preview" ? 960 : 1420)
                guard
                    let bitmap = NSBitmapImageRep(
                        bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                    let context = NSGraphicsContext(bitmapImageRep: bitmap)
                else { throw CocoaError(.coderInvalidValue) }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
                ("CipherKeyboard · " + state as NSString).draw(
                    at: NSPoint(x: 12, y: size.height - 30),
                    withAttributes: [.font: NSFont.boldSystemFont(ofSize: 20), .foregroundColor: NSColor.black])
                for frame in frames {
                    guard let image = NSImage(contentsOfFile: frame.file),
                        let column = [375, 402, 440].firstIndex(of: frame.width)
                    else { throw CocoaError(.fileReadCorruptFile) }
                    let portrait = frame.orientation == "portrait"
                    let dark = frame.theme == "dark"
                    let rowTop = portrait ? (dark ? 500.0 : 40.0) : (dark ? 1190.0 : 960.0)
                    let cardHeight = portrait ? 450.0 : 220.0
                    let card = NSRect(
                        x: Double(column) * 400 + 10, y: size.height - rowTop - cardHeight, width: 380,
                        height: cardHeight - 25)
                    let scale = min(card.width / image.size.width, card.height / image.size.height)
                    let rect = NSRect(
                        x: card.midX - image.size.width * scale / 2, y: card.midY - image.size.height * scale / 2,
                        width: image.size.width * scale, height: image.size.height * scale)
                    image.draw(in: rect)
                    let title = "\(frame.width) · \(frame.orientation) · \(frame.theme)"
                    (title as NSString).draw(
                        at: NSPoint(x: card.minX, y: card.maxY + 5),
                        withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black])
                }
                NSGraphicsContext.restoreGraphicsState()
                guard let data = bitmap.representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try data.write(to: output.appendingPathComponent(state + ".png"))
            }
        }
    }
#endif
