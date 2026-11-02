#if DEBUG
    import Security

    /// Audit precondition only: query the real identity's identifying attributes.
    /// kSecReturnData is deliberately absent, so no secret bytes leave Keychain.
    enum KeyboardIdentityMetadataProbe {
        static func run() -> String {
            let service = "dev.cipherkeyboard.identity"
            let account = "identity.v1"
            let group = "group.dev.cipherkeyboard"
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrAccessGroup as String: group,
                kSecReturnAttributes as String: true,
                kSecMatchLimit as String: kSecMatchLimitAll,
            ]
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let entries = result as? [[String: Any]], entries.count == 1,
                entries[0][kSecAttrService as String] as? String == service,
                entries[0][kSecAttrAccount as String] as? String == account,
                entries[0][kSecAttrAccessGroup as String] as? String == group
            else { return "FAIL: identity attribute coverage" }
            return "PASS: real identity.v1; attributes only; rows=1"
        }
    }
#endif
