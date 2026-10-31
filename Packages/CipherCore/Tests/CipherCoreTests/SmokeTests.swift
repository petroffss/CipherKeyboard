import CipherCore
import Testing

@Suite("Каркас")
struct SmokeTests {
    @Test("Модуль подключается и знает название продукта")
    func productName() {
        #expect(CipherCore.productName == "CipherKeyboard")
    }
}
