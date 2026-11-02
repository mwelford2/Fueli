import Foundation
import Testing
@testable import Fueli

struct FueliTests {
    @Test func releaseIdentityRemainsFueli() {
        #expect(Bundle.main.bundleIdentifier == "com.welford.fueli")
    }
}
