import Testing
@testable import Garage

struct AppleSignInNonceTests {
    @Test func randomString_hasRequestedLength() {
        let nonce = AppleSignInNonce.randomString(length: 32)

        #expect(nonce.count == 32)
    }

    @Test func randomString_usesExpectedCharacterSet() {
        let nonce = AppleSignInNonce.randomString(length: 128)
        let allowedCharacters = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

        #expect(nonce.allSatisfy { allowedCharacters.contains($0) })
    }

    @Test func sha256_matchesKnownDigest() {
        #expect(
            AppleSignInNonce.sha256("hello") ==
                "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    }
}
