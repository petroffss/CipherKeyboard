import Foundation
import Testing
@testable import KeyboardTyping

struct KeyboardInputTests {
    @Test func insertsAtGraphemeBoundary() {
        var model = KeyboardInput()
        model.insert("Привет")
        model.moveCursor(to: 3)
        model.insert("X")
        model.insert("\n")
        model.insert(" ")
        #expect(model.text == "ПриX\n вет")
        model.deleteBackward()
        #expect(model.text == "ПриX\nвет")
        #expect(model.cursor == 5)
        model.insert("e\u{301}")
        #expect(model.cursor == 6)
    }
    @Test func layoutsAndTransitions() {
        var m = KeyboardInput()
        #expect(m.rows == [Array("йцукенгшщзх"), Array("фывапролджэ"), Array("ячсмитьбю")].map { $0.map(String.init) })
        m.insert("abc"); m.moveCursor(to: 1); m.toggleLanguage()
        #expect(m.rows == [Array("qwertyuiop"), Array("asdfghjkl"), Array("zxcvbnm")].map { $0.map(String.init) })
        m.toggleNumbers()
        #expect(
            m.rows == [
                ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
                ["-", "/", ":", ";", "(", ")", "₽", "&", "@", "\""], [".", ",", "?", "!", "'"],
            ])
        m.toggleSymbols()
        #expect(
            m.rows == [
                ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
                ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"], [".", ",", "?", "!", "'"],
            ])
        m.toggleNumbers(); #expect(m.page == .letters && m.language == .english)
        m.toggleNumbers(); m.toggleLanguage()
        #expect(m.page == .letters && m.language == .russian)
        #expect(m.text == "abc" && m.cursor == 1)
    }
    @Test func shiftStateMachine() {
        for prefix in ["", "x\n", "x. ", "x! ", "x? "] {
            var m = KeyboardInput(); m.insert(prefix); #expect(m.uppercase)
            m.typeKey("я"); #expect(m.text == prefix + "Я"); #expect(!m.uppercase)
        }
        var m = KeyboardInput(); m.insert("abc"); m.moveCursor(to: 1); #expect(!m.uppercase)
        m.tapShift(at: 0); #expect(m.shift == .once)
        m.typeKey("1"); m.typeKey(" "); m.toggleLanguage(); m.toggleNumbers()
        #expect(m.shift == .once)
        m.typeKey("e"); #expect(m.shift == .automatic)
        m.reset(); m.tapShift(at: 0); #expect(!m.uppercase)
        m.typeKey("1"); m.typeKey(" "); #expect(!m.uppercase)
        m.typeKey("е"); #expect(m.text == "1 е")
        m.reset(); m.tapShift(at: 0); m.tapShift(at: 0.299)
        #expect(m.shift == .caps); m.toggleLanguage(); #expect(m.shift == .caps)
        m.tapShift(at: 1); #expect(m.shift == .off)
        m.reset(); m.tapShift(at: 0); m.tapShift(at: 0.301); #expect(m.shift != .caps)
    }
    @Test func deletesCharacters() {
        for value in ["e\u{301}", "👍🏽", "🇷🇺", "👨‍👩‍👧‍👦"] {
            var m = KeyboardInput(); m.insert(value + "right"); m.moveCursor(to: 1); m.deleteBackward()
            #expect(m.text == "right" && m.cursor == 0)
            m.deleteBackward(); #expect(m.text == "right")
            m.reset(); m.deleteBackward(); #expect(m.text.isEmpty && m.cursor == 0)
        }
    }
    @Test func utf8Limit() {
        for value in [String(repeating: "a", count: 3500), String(repeating: "я", count: 1750)] {
            var m = KeyboardInput(); m.insert(value); #expect(m.counter == "3500 / 4096 байт")
            m.insert("a"); #expect(m.counter == "3501 / 4096 байт")
            m.insert(String(repeating: "x", count: 595)); #expect(m.byteCount == 4096)
            m.moveCursor(to: 10)
            for extra in ["a", "\n", "ё", "👨‍👩‍👧‍👦"] {
                let before = m.text
                let rejected = m.insert(extra); #expect(!rejected);
                #expect(m.text == before && m.cursor == 10 && m.limitError)
                #expect(KeyboardInput.limitMessage == "Сообщение не должно превышать 4096 байт")
            }
            m.deleteBackward(); #expect(!m.limitError)
            let accepted = m.insert("a"); #expect(accepted); #expect(!m.limitError)
        }
    }
}
