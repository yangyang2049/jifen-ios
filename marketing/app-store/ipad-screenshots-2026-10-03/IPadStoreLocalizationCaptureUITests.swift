
import UIKit

final class IPadStoreLocalizationCaptureUITests: XCTestCase {
    private func capture(locale: String, language: String, region: String, names: [String], teams: [String]) {
        continueAfterFailure = false
        let scenes = ["snooker", "basketball", "record", "setup", "home"]
        let app = XCUIApplication(bundleIdentifier: "com.douhua.jifen.ios")
        for (index, scene) in scenes.enumerated() {
            app.terminate()
            XCUIDevice.shared.orientation = .landscapeLeft
            app.launchArguments = [
                "-AppleLanguages", "(\(language))", "-AppleLocale", region,
                "-UITestSkipLegalConsent", "YES", "-UITestSkipScoreboardUsageHints", "YES",
                "-UITestScreenshotMode", "1", "-UITestRecordFixtures",
                "-UITestRecordTeamName1", names[0], "-UITestRecordTeamName2", names[1],
                "-jifen-v2.appAppearanceMode", "light"
            ]
            if scene != "home" { app.launchArguments += ["-MarketingScreenshotFixture", scene] }
            let players = scene == "basketball" ? teams + Array(names.dropFirst(2)) : names
            for (number, player) in players.enumerated() {
                app.launchArguments += ["-UITestSetupName\(number + 1)", player]
            }
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
            XCUIDevice.shared.orientation = .landscapeLeft
            Thread.sleep(forTimeInterval: 1.0)
            let screenshot = XCUIScreen.main.screenshot()
            let image = screenshot.image
            XCTAssertEqual(Int((image.size.width * image.scale).rounded()), 2752)
            XCTAssertEqual(Int((image.size.height * image.scale).rounded()), 2064)
            let name = String(format: "ipad-%@-%02d-%@", locale, index + 1, scene)
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            print("IPAD_CAPTURED " + name)
        }
        app.terminate()
    }

    func testCapture_en_US() { capture(locale: "en-US", language: "en", region: "en_US", names: ["Ethan", "Liam", "Emma", "Mia"], teams: ["Home", "Away"]) }
    func testCapture_ja() { capture(locale: "ja", language: "ja", region: "ja_JP", names: ["伊達政宗", "真田幸村", "武田信玄", "上杉謙信"], teams: ["ホーム", "アウェイ"]) }
    func testCapture_ko() { capture(locale: "ko", language: "ko", region: "ko_KR", names: ["민준", "서준", "지훈", "수빈"], teams: ["홈팀", "원정팀"]) }
    func testCapture_de_DE() { capture(locale: "de-DE", language: "de", region: "de_DE", names: ["Max", "Paul", "Anna", "Lena"], teams: ["Heim", "Gast"]) }
    func testCapture_fr_FR() { capture(locale: "fr-FR", language: "fr", region: "fr_FR", names: ["Louis", "Hugo", "Emma", "Jules"], teams: ["Domicile", "Extérieur"]) }
    func testCapture_es_ES() { capture(locale: "es-ES", language: "es-ES", region: "es_ES", names: ["Pablo", "Álvaro", "Lucía", "Mateo"], teams: ["Local", "Visitante"]) }
    func testCapture_pt_BR() { capture(locale: "pt-BR", language: "pt-BR", region: "pt_BR", names: ["Lucas", "Pedro", "Ana", "Gabriel"], teams: ["Mandante", "Visitante"]) }
    func testCapture_it() { capture(locale: "it", language: "it", region: "it_IT", names: ["Luca", "Marco", "Giulia", "Andrea"], teams: ["Casa", "Trasferta"]) }
    func testCapture_ru() { capture(locale: "ru", language: "ru", region: "ru_RU", names: ["Алексей", "Иван", "Анна", "Мария"], teams: ["Хозяева", "Гости"]) }
    func testCapture_ar_SA() { capture(locale: "ar-SA", language: "ar", region: "ar_SA", names: ["أحمد", "عمر", "علي", "يوسف"], teams: ["المضيف", "الضيف"]) }
    func testCapture_hi() { capture(locale: "hi", language: "hi", region: "hi_IN", names: ["अर्जुन", "राहुल", "आदित्य", "विवेक"], teams: ["मेज़बान", "मेहमान"]) }
    func testCapture_nl_NL() { capture(locale: "nl-NL", language: "nl", region: "nl_NL", names: ["Daan", "Bram", "Lotte", "Finn"], teams: ["Thuis", "Uit"]) }
    func testCapture_tr() { capture(locale: "tr", language: "tr", region: "tr_TR", names: ["Emre", "Deniz", "Ece", "Can"], teams: ["Ev Sahibi", "Deplasman"]) }
    func testCapture_id() { capture(locale: "id", language: "id", region: "id_ID", names: ["Andi", "Budi", "Dewi", "Rina"], teams: ["Tuan Rumah", "Tandang"]) }
    func testCapture_vi() { capture(locale: "vi", language: "vi", region: "vi_VN", names: ["Minh", "An", "Linh", "Nam"], teams: ["Chủ nhà", "Khách"]) }
    func testCapture_th() { capture(locale: "th", language: "th", region: "th_TH", names: ["นนท์", "ภูมิ", "เมย์", "พลอย"], teams: ["เหย้า", "เยือน"]) }
    func testCapture_bn_BD() { capture(locale: "bn-BD", language: "bn", region: "bn_BD", names: ["আরিফ", "হাসান", "রাহুল", "সুমন"], teams: ["স্বাগতিক", "অতিথি"]) }
    func testCapture_ca() { capture(locale: "ca", language: "ca", region: "ca_ES", names: ["Marc", "Pau", "Laia", "Joan"], teams: ["Local", "Visitant"]) }
    func testCapture_cs() { capture(locale: "cs", language: "cs", region: "cs_CZ", names: ["Jakub", "Tomáš", "Anna", "Petr"], teams: ["Domácí", "Hosté"]) }
    func testCapture_da() { capture(locale: "da", language: "da", region: "da_DK", names: ["Mads", "Emil", "Freja", "Noah"], teams: ["Hjemme", "Ude"]) }
    func testCapture_el() { capture(locale: "el", language: "el", region: "el_GR", names: ["Νίκος", "Γιάννης", "Μαρία", "Ελένη"], teams: ["Γηπεδούχοι", "Φιλοξενούμενοι"]) }
    func testCapture_en_AU() { capture(locale: "en-AU", language: "en", region: "en_AU", names: ["Jack", "Oliver", "Charlotte", "Amelia"], teams: ["Home", "Away"]) }
    func testCapture_en_CA() { capture(locale: "en-CA", language: "en", region: "en_CA", names: ["Noah", "Lucas", "Olivia", "Emma"], teams: ["Home", "Away"]) }
    func testCapture_en_GB() { capture(locale: "en-GB", language: "en", region: "en_GB", names: ["Harry", "Oliver", "George", "Arthur"], teams: ["Home", "Away"]) }
    func testCapture_es_MX() { capture(locale: "es-MX", language: "es-MX", region: "es_MX", names: ["Diego", "Luis", "Sofía", "Mateo"], teams: ["Local", "Visitante"]) }
    func testCapture_fi() { capture(locale: "fi", language: "fi", region: "fi_FI", names: ["Eero", "Mikko", "Aino", "Leo"], teams: ["Koti", "Vieras"]) }
    func testCapture_fr_CA() { capture(locale: "fr-CA", language: "fr-CA", region: "fr_CA", names: ["Émile", "Félix", "Alice", "Léa"], teams: ["Domicile", "Visiteurs"]) }
    func testCapture_gu_IN() { capture(locale: "gu-IN", language: "gu", region: "gu_IN", names: ["જય", "અર્જુન", "કિરણ", "રાહુલ"], teams: ["યજમાન", "મહેમાન"]) }
    func testCapture_he() { capture(locale: "he", language: "he", region: "he_IL", names: ["דניאל", "יונתן", "נועם", "מאיה"], teams: ["בית", "חוץ"]) }
    func testCapture_hr() { capture(locale: "hr", language: "hr", region: "hr_HR", names: ["Luka", "Ivan", "Ana", "Marko"], teams: ["Domaći", "Gosti"]) }
    func testCapture_hu() { capture(locale: "hu", language: "hu", region: "hu_HU", names: ["Bence", "Máté", "Anna", "Lili"], teams: ["Hazai", "Vendég"]) }
    func testCapture_kn_IN() { capture(locale: "kn-IN", language: "kn", region: "kn_IN", names: ["ಅರ್ಜುನ್", "ಕಿರಣ್", "ರಾಹುಲ್", "ವಿಕಾಸ್"], teams: ["ಆತಿಥೇಯ", "ಅತಿಥಿ"]) }
    func testCapture_ml_IN() { capture(locale: "ml-IN", language: "ml", region: "ml_IN", names: ["അർജുൻ", "കിരൺ", "രാഹുൽ", "അനിൽ"], teams: ["ആതിഥേയ", "അതിഥി"]) }
    func testCapture_mr_IN() { capture(locale: "mr-IN", language: "mr", region: "mr_IN", names: ["अजय", "राहुल", "आदित्य", "विवेक"], teams: ["यजमान", "पाहुणे"]) }
    func testCapture_ms() { capture(locale: "ms", language: "ms", region: "ms_MY", names: ["Amir", "Hakim", "Aiman", "Farah"], teams: ["Tuan Rumah", "Pelawat"]) }
    func testCapture_no() { capture(locale: "no", language: "nb", region: "nb_NO", names: ["Ola", "Emil", "Ingrid", "Lars"], teams: ["Hjemme", "Borte"]) }
    func testCapture_or_IN() { capture(locale: "or-IN", language: "or", region: "or_IN", names: ["ଅର୍ଜୁନ", "ରାହୁଲ", "କିରଣ", "ସୁମନ"], teams: ["ଆୟୋଜକ", "ଅତିଥି"]) }
    func testCapture_pa_IN() { capture(locale: "pa-IN", language: "pa", region: "pa_IN", names: ["ਅਮਨ", "ਅਰਜੁਨ", "ਰਾਹੁਲ", "ਕਿਰਨ"], teams: ["ਮੇਜ਼ਬਾਨ", "ਮਹਿਮਾਨ"]) }
    func testCapture_pl() { capture(locale: "pl", language: "pl", region: "pl_PL", names: ["Jan", "Piotr", "Anna", "Tomasz"], teams: ["Gospodarze", "Goście"]) }
    func testCapture_pt_PT() { capture(locale: "pt-PT", language: "pt-PT", region: "pt_PT", names: ["João", "Miguel", "Maria", "Tiago"], teams: ["Casa", "Visitante"]) }
    func testCapture_ro() { capture(locale: "ro", language: "ro", region: "ro_RO", names: ["Andrei", "Mihai", "Ana", "Elena"], teams: ["Gazde", "Oaspeți"]) }
    func testCapture_sk() { capture(locale: "sk", language: "sk", region: "sk_SK", names: ["Martin", "Tomáš", "Anna", "Peter"], teams: ["Domáci", "Hostia"]) }
    func testCapture_sl_SI() { capture(locale: "sl-SI", language: "sl", region: "sl_SI", names: ["Luka", "Jan", "Ana", "Miha"], teams: ["Domači", "Gostje"]) }
    func testCapture_sv() { capture(locale: "sv", language: "sv", region: "sv_SE", names: ["Erik", "Johan", "Anna", "Elsa"], teams: ["Hemma", "Borta"]) }
    func testCapture_ta_IN() { capture(locale: "ta-IN", language: "ta", region: "ta_IN", names: ["அருண்", "கவின்", "விஜய்", "சூர்யா"], teams: ["உள்ளூர்", "விருந்தினர்"]) }
    func testCapture_te_IN() { capture(locale: "te-IN", language: "te", region: "te_IN", names: ["అర్జున్", "కిరణ్", "రాహుల్", "వికాస్"], teams: ["ఆతిథ్య", "అతిథి"]) }
    func testCapture_uk() { capture(locale: "uk", language: "uk", region: "uk_UA", names: ["Андрій", "Тарас", "Олена", "Іван"], teams: ["Господарі", "Гості"]) }
    func testCapture_ur_PK() { capture(locale: "ur-PK", language: "ur", region: "ur_PK", names: ["احمد", "علی", "عمر", "حسن"], teams: ["میزبان", "مہمان"]) }
}
