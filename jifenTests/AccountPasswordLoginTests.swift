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

    func testMeScannerRoutesGroupInvitationsSeparatelyFromLogin() throws {
        for (raw, number) in [
            ("https://jifenqi.com/groups/join?groupNo=123456", "123456"),
            ("https://iscoreboard.live/groups/join?groupNo=1234567", "1234567"),
            (#"{"type":"JIFEN_GROUP","v":1,"groupNo":"72856000"}"#, "72856000"),
            (" 72856000 ", "72856000")
        ] {
            XCTAssertEqual(try MeQRPayload.parse(raw), .group(number))
        }
        let token = "qrl_scan_" + String(repeating: "a", count: 43)
        let login = "https://jifenqi.com/auth/qr#sid=session-0002&st=\(token)"
        XCTAssertEqual(try MeQRPayload.parse(login), .login(try QRLoginPayload.parse(login)))
    }

    func testMeScannerRejectsInvalidGroupInvitations() {
        for raw in [
            "https://iscoreboard.live.evil.test/groups/join?groupNo=72856000",
            "https://jifenqi.com/groups/join?groupNo=72856000&groupNo=123456",
            "https://jifenqi.com/groups/join?groupNo=012345",
            #"{"type":"JIFEN_GROUP","v":2,"groupNo":"72856000"}"#
        ] {
            XCTAssertThrowsError(try MeQRPayload.parse(raw))
        }
    }
}

/// 头像裁剪数学 + 上传前压缩的纯函数覆盖（裁剪视图/上传链路共用同一层）。
@MainActor
final class AvatarCropTests: XCTestCase {
    private func fixtureImage() -> UIImage {
        let size = CGSize(width: 900, height: 600)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0, green: 128, blue: 128, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 450, height: 300))
        }
    }

    func testFillScaleAndBaseDisplaySize() {
        let base = AvatarCropGeometry.baseDisplaySize(imageSize: CGSize(width: 900, height: 600), side: 300)
        XCTAssertEqual(base.width, 450, accuracy: 0.001)
        XCTAssertEqual(base.height, 300, accuracy: 0.001)
    }

    func testOffsetLimitKeepsCropWindowCovered() {
        let limit = AvatarCropGeometry.offsetLimit(imageSize: CGSize(width: 900, height: 600), side: 300, zoom: 1)
        XCTAssertEqual(limit.width, 75, accuracy: 0.001)
        XCTAssertEqual(limit.height, 0, accuracy: 0.001)

        let zoomed = AvatarCropGeometry.offsetLimit(imageSize: CGSize(width: 900, height: 600), side: 300, zoom: 2)
        XCTAssertEqual(zoomed.width, 300, accuracy: 0.001)
        XCTAssertEqual(zoomed.height, 150, accuracy: 0.001)
    }

    func testClampConfinesOffsetAndZoom() {
        let clamped = AvatarCropGeometry.clamp(
            offset: CGSize(width: 500, height: -900),
            limit: CGSize(width: 75, height: 0)
        )
        XCTAssertEqual(clamped.width, 75, accuracy: 0.001)
        XCTAssertEqual(clamped.height, 0, accuracy: 0.001)
        XCTAssertEqual(AvatarCropGeometry.clampZoom(0.2), AvatarCropGeometry.minZoom)
        XCTAssertEqual(AvatarCropGeometry.clampZoom(9), AvatarCropGeometry.maxZoom)
    }

    func testCroppedImageProducesSquareAndFollowsOffset() {
        let source = fixtureImage()
        let square = AvatarCropGeometry.croppedImage(from: source, side: 300, zoom: 1, offset: .zero)
        XCTAssertNotNil(square)
        XCTAssertEqual(square!.size, CGSize(width: 1024, height: 1024))
        XCTAssertEqual(square!.scale, 1)

        func red(_ image: UIImage, _ point: CGPoint) -> CGFloat {
            let cg = image.cgImage!
            var pixel = [UInt8](repeating: 0, count: 4)
            let cs = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(
                data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.translateBy(x: -point.x, y: -(CGFloat(cg.height) - point.y))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(cg.width), height: CGFloat(cg.height)))
            return CGFloat(pixel[0])
        }

        // 源图上半白色（x<450）、其余青色；zoom=1 时裁剪窗纵向恰铺满、横向可平移 ±75。
        // 取样 y=256 避开上下分界行：右极限看到源 x∈[0,600]（白），左极限看到 x∈[300,900]（青）。
        let leftEdge = AvatarCropGeometry.croppedImage(from: source, side: 300, zoom: 1, offset: CGSize(width: -75, height: 0))!
        let rightEdge = AvatarCropGeometry.croppedImage(from: source, side: 300, zoom: 1, offset: CGSize(width: 75, height: 0))!
        XCTAssertNotEqual(red(leftEdge, CGPoint(x: 512, y: 256)), red(rightEdge, CGPoint(x: 512, y: 256)))
        XCTAssertEqual(red(rightEdge, CGPoint(x: 512, y: 256)), 255, accuracy: 1)
        XCTAssertEqual(red(leftEdge, CGPoint(x: 512, y: 256)), 0, accuracy: 1)
    }

    func testPrepareAvatarJPEGDownscalesTo1024() {
        let big = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000)).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        }
        let png = big.pngData()!
        let out = SessionStore.prepareAvatarJPEG(png)
        XCTAssertNotNil(out)
        XCTAssertLessThanOrEqual(out!.count, 950_000)
        let decoded = UIImage(data: out!)!
        XCTAssertLessThanOrEqual(max(decoded.size.width, decoded.size.height), 1024)
    }

    func testPrepareAvatarJPEGRejectsNonImage() {
        XCTAssertNil(SessionStore.prepareAvatarJPEG(Data([0x00, 0x01, 0x02, 0x03])))
    }

    func testAppUserDecodesAvatarVisibility() throws {
        let json = Data("""
        {"id":"u1","role":"FREE","plan":"FREE","createdAt":1,"avatarVisibility":"OWNER_PREVIEW"}
        """.utf8)
        let user = try JSONDecoder().decode(AppUser.self, from: json)
        XCTAssertEqual(user.avatarVisibility, "OWNER_PREVIEW")
    }

    func testModerationBannerTextIsClientDerivedFromVisibilityCodes() {
        let namePending = NSLocalizedString("me_profile_name_under_review", value: "昵称审核中", comment: "")
        let avatarPending = NSLocalizedString("me_profile_avatar_under_review", value: "头像审核中", comment: "")

        XCTAssertNil(ProfileModerationBanner.label(nameVisibility: "PUBLIC", avatarVisibility: "PUBLIC"))
        XCTAssertNil(ProfileModerationBanner.label(nameVisibility: nil, avatarVisibility: nil))
        XCTAssertEqual(
            ProfileModerationBanner.label(nameVisibility: nil, avatarVisibility: "owner_preview"),
            avatarPending
        )
        XCTAssertEqual(
            ProfileModerationBanner.label(nameVisibility: "OWNER_PREVIEW", avatarVisibility: nil),
            namePending
        )
        XCTAssertEqual(
            ProfileModerationBanner.label(nameVisibility: "OWNER_PREVIEW", avatarVisibility: "OWNER_PREVIEW"),
            "\(namePending) · \(avatarPending)"
        )
    }

    func testRemoteImageCacheInsertAndLookup() {
        let url = URL(string: "https://example.com/avatar-\(UUID().uuidString).jpg")!
        XCTAssertNil(RemoteImageCache.shared.image(for: url))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
        RemoteImageCache.shared.insert(image, for: url)
        XCTAssertNotNil(RemoteImageCache.shared.image(for: url))
    }
}
