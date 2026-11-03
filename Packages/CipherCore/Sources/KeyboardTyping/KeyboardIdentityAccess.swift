import CipherCore

@MainActor struct KeyboardIdentityAccess {
    let readMetadata: () -> IdentityMetadataReadResult
    let readSecret: () async -> IdentityReadResult?

    init(
        identity: (() -> IdentityReadResult)?,
        metadata: (() -> IdentityMetadataReadResult)?
    ) {
        if let identity {
            readSecret = { identity() }
            readMetadata = metadata ?? { identity().publicMetadata }
        } else {
            readSecret = {
                let worker = Task.detached { () -> IdentityReadResult? in
                    guard !Task.isCancelled else { return nil }
                    return IdentityReader.keychain.read()
                }
                return await withTaskCancellationHandler {
                    await worker.value
                } onCancel: {
                    worker.cancel()
                }
            }
            readMetadata = metadata ?? IdentityReader.readKeychainMetadata
        }
    }
}

extension IdentityReadResult {
    var publicMetadata: IdentityMetadataReadResult {
        switch self {
        case .identity(let identity): .publicKey(identity.publicKey)
        case .missing: .missing
        case .unavailable(let error): .unavailable(error)
        }
    }
}
