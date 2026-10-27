import CryptoKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: test-key SEED_FILE\n".utf8))
    exit(2)
}
let key = Curve25519.Signing.PrivateKey()
let seed = Data(key.rawRepresentation.base64EncodedString().utf8)
guard FileManager.default.createFile(atPath: CommandLine.arguments[1], contents: seed, attributes: [.posixPermissions: 0o600]) else {
    FileHandle.standardError.write(Data("test-key: cannot write \(CommandLine.arguments[1])\n".utf8))
    exit(1)
}
print(key.publicKey.rawRepresentation.base64EncodedString())
