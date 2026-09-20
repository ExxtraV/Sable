import Foundation
import CryptoKit

// Public data only: verify the archive against the key embedded in the app.
do {
    guard CommandLine.arguments.count == 4,
          let keyData = Data(base64Encoded: CommandLine.arguments[2]),
          let signature = Data(base64Encoded: CommandLine.arguments[3]) else {
        throw NSError(domain: "UpdateVerification", code: 1)
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    guard key.isValidSignature(signature, for: archive) else {
        throw NSError(domain: "UpdateVerification", code: 2)
    }
    print("Archive signature matches the app's public key.")
} catch {
    FileHandle.standardError.write(Data("Update signature verification failed.\n".utf8))
    exit(1)
}
