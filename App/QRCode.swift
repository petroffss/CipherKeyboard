import CoreImage
import CoreImage.CIFilterBuiltins

/// QR-код строки: CoreImage `CIQRCodeGenerator`, коррекция M, увеличение без сглаживания.
enum QRCode {
    static func image(for string: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.samplingNearest().transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
