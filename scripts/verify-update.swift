import CryptoKit
import Foundation

let arguments = CommandLine.arguments
let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[1]), options: .mappedIfSafe)
guard let publicKey = Data(base64Encoded: arguments[2]),
      let signature = Data(base64Encoded: arguments[3]),
      try Curve25519.Signing.PublicKey(rawRepresentation: publicKey).isValidSignature(signature, for: archive) else {
    fatalError("The update signature does not match the public key embedded in Doorman")
}
