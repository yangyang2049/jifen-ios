import Foundation
import XCTest
@testable import jifen

final class AccountPasswordLoginTests: XCTestCase {
    func testEndpointAndPayloadMatchBackendContract() throws {
        XCTAssertEqual(PasswordLoginEndpoint.path, "/api/auth/login/email")

        let body = PasswordLoginEndpoint.Body(email: "review@example.com", password: " p@ss word ")
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(json["email"], "review@example.com")
        XCTAssertEqual(json["password"], " p@ss word ")
    }

    func testAccountValidationAcceptsEmailAndSupportedPhoneFormats() {
        XCTAssertTrue(PasswordLoginInputValidator.isEmailOrPhoneAccount("review@example.com"))
        XCTAssertTrue(PasswordLoginInputValidator.isEmailOrPhoneAccount("13800138000"))
        XCTAssertTrue(PasswordLoginInputValidator.isEmailOrPhoneAccount("+86 138-0013-8000"))
    }

    func testAccountValidationRejectsMalformedPhoneValues() {
        XCTAssertFalse(PasswordLoginInputValidator.isEmailOrPhoneAccount(""))
        XCTAssertFalse(PasswordLoginInputValidator.isEmailOrPhoneAccount("12345"))
        XCTAssertFalse(PasswordLoginInputValidator.isEmailOrPhoneAccount("13800138000x"))
    }
}
