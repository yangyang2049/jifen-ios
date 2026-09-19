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

    func testQRLoginPayloadAcceptsCanonicalJSONAndWebURL() throws {
        let token = "qrl_scan_" + String(repeating: "a", count: 43)
        let json = """
        {"type":"AUTH_QR_LOGIN","version":1,"sessionId":"session-0001","scanToken":"\(token)"}
        """
        XCTAssertEqual(try QRLoginPayload.parse(json).sessionId, "session-0001")
        XCTAssertEqual(
            try QRLoginPayload.parse("https://jifenqi.com/auth/qr#sid=session-0002&st=\(token)").scanToken,
            token
        )
    }

    func testQRLoginPayloadRejectsLookalikeHostVersionExpiryAndMalformedCredentials() {
        let token = "qrl_scan_" + String(repeating: "a", count: 43)
        XCTAssertThrowsError(try QRLoginPayload.parse(
            "https://jifenqi.com.attacker.example/auth/qr#sid=session-0003&st=\(token)"
        ))
        XCTAssertThrowsError(try QRLoginPayload.parse(
            "{\"type\":\"AUTH_QR_LOGIN\",\"version\":2,\"sessionId\":\"session-0003\",\"scanToken\":\"\(token)\"}"
        ))
        XCTAssertThrowsError(try QRLoginPayload.parse(
            "{\"type\":\"AUTH_QR_LOGIN\",\"version\":1,\"sessionId\":\"session-0003\",\"scanToken\":\"\(token)\",\"expiresAt\":1}"
        ))
        XCTAssertThrowsError(try QRLoginPayload.parse(
            "https://jifenqi.com/auth/qr#sid=short&st=\(token)"
        ))
        XCTAssertThrowsError(try QRLoginPayload.parse(String(repeating: "x", count: 8_193)))
    }
}
