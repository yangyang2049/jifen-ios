import XCTest
@testable import jifen

@MainActor final class GroupBilliardsTests: XCTestCase {
    struct Fixtures: Decodable { var fixtures:[Fixture] }
    struct Fixture: Decodable {var id:String;var rules:GroupBilliardsRules;var participants:[GroupBilliardsParticipant];var result:GroupBilliardsResult}
    func fixtures() throws -> [Fixture] {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent()
        return try JSONDecoder().decode(Fixtures.self,from:Data(contentsOf:root.appendingPathComponent("Fixtures/billiards-v2.json"))).fixtures
    }
    func testEverySharedVariantAndNativeSetupMapping() throws {
        for f in try fixtures() {
            try f.rules.validate();try f.result.validate(rules:f.rules)
            let setup=try f.rules.setup(names:f.participants.map(\.memberId))
            XCTAssertEqual(setup.playerCount,f.rules.playerCount)
            XCTAssertEqual(setup.nineBallBigGold,f.rules.config.bigGold)
            XCTAssertEqual(setup.eightBallHandicapRacks,f.rules.config.handicapRacks)
            let body=GroupBilliardsSubmission(rules:f.rules,participants:f.participants,clientSessionId:"fixture-session",clientRecordId:"fixture-record",playedAt:1,source:"manual",result:f.result)
            try body.validate()
            var invalid=body;invalid.participants[1].memberId=invalid.participants[0].memberId;XCTAssertThrowsError(try invalid.validate())
            var result=f.result;result.scores.removeLast();XCTAssertThrowsError(try result.validate(rules:f.rules))
            result=f.result;result.scores[0].points=2147483648;XCTAssertThrowsError(try result.validate(rules:f.rules))
        }
    }
    /// 战绩页要用响应里的 `bucket` 回显规则桶选中态，净积分榜要「场均」和「平」两列。
    func testRankingBucketAverageAndDrawsDecode() throws {
        let json = #"{"bucket":"bucket-1","items":[{"memberId":"m1","displayName":"A","rank":1,"games":6,"wins":3,"losses":2,"draws":1,"totalPoints":7,"averagePoints":1.1666,"winRateText":"50%"}]}"#
        let ranking = try JSONDecoder().decode(GroupBilliardsRanking.self, from: Data(json.utf8))
        XCTAssertEqual(ranking.bucket, "bucket-1")
        let row = try XCTUnwrap(ranking.items?.first)
        XCTAssertEqual(row.draws, 1)
        XCTAssertEqual(row.averageText, "1.2")
        XCTAssertEqual(row.signedPoints, "+7")
        XCTAssertEqual(row.qualifiedWinRate, "50%")
        XCTAssertNil(GroupBilliardsRank(memberId: "m2", displayName: "B", rank: 2, games: 4).qualifiedWinRate)
        XCTAssertEqual(GroupBilliardsRank.signed(-3), "-3")
        XCTAssertEqual(GroupBilliardsRank.signed(0), "0")
    }
    /// v2 契约新增的三个业务码必须有文案，不能退化成裸键。
    func testBilliardsBusinessErrorCodesMapToCopy() {
        for code in ["SESSION_FROZEN", "ACTIVITY_NOT_COMPLETE", "RESULT_VOIDED"] {
            let message = groupErrorMessage(APIClientError.server(status: 409, code: code, message: nil, nextAvailableAt: nil))
            XCTAssertFalse(message.isEmpty, code)
            XCTAssertFalse(message.hasPrefix("group_"), "\(code) fell back to a raw key")
        }
    }
    func testUnknownValuesDoNotCrashListsAndV2CannotUseRacketRules() throws {
        XCTAssertEqual(try JSONDecoder().decode(GroupSport.self,from:Data("\"future_sport\"".utf8)),.unsupported)
        XCTAssertEqual(try JSONDecoder().decode(GroupFormat.self,from:Data("\"individuals\"".utf8)),.individuals)
        XCTAssertFalse(GroupMatchRules.supports(.billiards))
        for f in try fixtures() {
            var r=f.rules;r.variant="future_variant";XCTAssertThrowsError(try r.validate())
        }
    }
    func testV2ResultRoundTripPreservesSignedScoresAndIdentity() throws {
        let f=try fixtures()[0]
        let row=GroupBilliardsRow(format:.individuals,id:"result",groupId:"group",gameId:"game",rules:f.rules,result:f.result,participants:f.participants.map{.init(participantId:$0.participantId,memberId:$0.memberId,position:$0.position,displayName:"Same",side:"individuals",seat:$0.position,canonicalMemberId:$0.memberId)},status:"confirmed",playedAt:1,revision:1)
        XCTAssertTrue(row.shareText.contains("-13"))
        let summary=row.personalSummary(groupName:"Group")
        let envelope=PersonalRecordEnvelope(libraryId:"group:group",recordKey:row.id,kind:"score",project:"nine_ball",playedAt:1,participantMode:"individual",participants:[],summary:summary,origin:.init(nativeSchemaVersion:2,sourceSystem:"group"),nativePayload:[:],assetIds:[])
        let presentation=RecordListPresentation(envelope)
        XCTAssertTrue(presentation.score?.contains("-13") == true)
        XCTAssertEqual(summary["players"]?.array?.count,3)
        let data=try JSONEncoder().encode(row)
        let result=try JSONDecoder().decode(GroupResult.self,from:data)
        XCTAssertEqual(result.billiards?.result.scores,f.result.scores)
        XCTAssertEqual(result.participants.map(\.memberId),f.participants.map(\.memberId))
        let round=try JSONDecoder().decode(GroupResult.self,from:JSONEncoder().encode(result))
        XCTAssertEqual(round.billiards?.result.scores,f.result.scores)
    }
    func testNativeRecordProjectionAndFrozenRules() throws {
        for f in try fixtures() {
            let c=f.rules.config,values=f.result.scores.map(\.points)
            let source=GroupBilliardsSource(accountID:"account",groupID:"group",groupName:"group",clientSessionID:"session",rules:f.rules,participants:f.participants,names:f.participants.map(\.memberId))
            var cfg:[String:AnyCodable]=[:]
            let ints:[String:Int?]=["nineBallBigGold":c.bigGold,"nineBallSmallGold":c.smallGold,"nineBallGoldenNine":c.goldenNine,"nineBallNormalWin":c.normalWin,"nineBallFoul":c.foul,"nineBallThirdFoul":c.thirdFoul,"nineBallTotalRacks":c.totalRacks,"maxSets":c.targetRacks ?? c.maxFrames,"eightBallHandicapRacks":c.handicapRacks]
            for(k,v) in ints {if let v{cfg[k]=AnyCodable(v)}}
            cfg["nineBallRuleFamily"]=AnyCodable(f.rules.knownVariant == .tournament ? "tournament":"folk")
            if let v=c.smallGoldAllPay {cfg["nineBallSmallGoldAllPay"]=AnyCodable(v)}
            if let v=c.goldRetainsBreak {cfg["nineBallGoldRetainsBreak"]=AnyCodable(v)}
            if let v=c.handoffEnabled {cfg["nineBallHandoffEnabled"]=AnyCodable(v)}
            if let v=c.breakRule {cfg["nineBallBreakRule"]=AnyCodable(v)}
            let extra:[String:AnyCodable]=["chasePlayerPoints":AnyCodable(values),"chaseRuleVersion":AnyCodable(3),"chaseRoundNumber":AnyCodable((f.result.completedRacks ?? 0)+1),"billiardsNaturalCompletion":AnyCodable(f.result.completion == "completed")]
            var record=ScoreboardRecord(id:"record",gameType:try XCTUnwrap(f.rules.knownVariant).gameType,startTime:Date(timeIntervalSince1970:1),endTime:Date(timeIntervalSince1970:2),team1Name:"Same",team2Name:"Same",team1FinalScore:values[0],team2FinalScore:values[1],team1SetScore:values[0],team2SetScore:values[1],totalScoreChanges:1,extraData:extra,projectConfiguration:cfg)
            let body=try GroupBilliardsPersistence.project(record,source:source)
            XCTAssertEqual(body.result.scores,f.result.scores);XCTAssertEqual(body.participants,f.participants)
            if f.rules.knownVariant == .folk {record.projectConfiguration?["nineBallBigGold"]=AnyCodable(99);XCTAssertThrowsError(try GroupBilliardsPersistence.project(record,source:source))}
        }
    }
    func testDefaultsMatchAndroid() {
        XCTAssertTrue(GroupBilliardsRules.defaults(.folk).config.handoffEnabled == true)
        XCTAssertEqual(GroupBilliardsRules.defaults(.tournament).config.thirdFoul,2)
        XCTAssertEqual(GroupBilliardsRules.defaults(.tournament).config.totalRacks,10)
        XCTAssertEqual(GroupBilliardsRules.defaults(.tournament).config.breakRule,"winner")
    }
    /// 一步式入口：九球合一为 4 个玩法组，后端变体由页内规则族决定。
    func testVariantGroupsMatchAndroid() {
        XCTAssertEqual(GroupBilliardsGroup.allCases.map(\.rawValue), ["nine_ball", "eight_ball", "snooker", "standard"])
        XCTAssertEqual(GroupBilliardsGroup.group(of: .folk), .nineBall)
        XCTAssertEqual(GroupBilliardsGroup.group(of: .tournament), .nineBall)
        for variant in [GroupBilliardsVariant.eight, .snooker, .standard] {
            XCTAssertEqual(GroupBilliardsGroup.group(of: variant).backend(family: "tournament"), variant)
        }
        // 提交前必须还原成后端合法变体：nine_ball 这个前端组值不能流到接口。
        XCTAssertEqual(GroupBilliardsGroup.nineBall.backend(family: "folk"), .folk)
        XCTAssertEqual(GroupBilliardsGroup.nineBall.backend(family: "tournament"), .tournament)
        XCTAssertEqual(GroupBilliardsRules.defaults(for: .nineBall, family: .tournament).variant, "nine_ball_tournament")
        XCTAssertEqual(GroupBilliardsRules.defaults(for: .standard).variant, "standard")
        // 普通台球没有任何可调规则，整块规则设置不渲染。
        XCTAssertFalse(GroupBilliardsRules.defaults(.standard).knownVariant!.hasAdjustableRules)
        XCTAssertTrue(GroupBilliardsRules.defaults(.snooker).knownVariant!.hasAdjustableRules)
    }
    /// 切玩法 / 切规则族：每个变体的 config 键集不同，换算后必须仍然通过校验。
    func testSwitchingGroupAndFamilyKeepsRulesValid() throws {
        var rules = GroupBilliardsRules.defaults(.folk, count: 3)
        rules.config.bigGold = 12
        rules.initialBreakerParticipantId = "p2"
        XCTAssertEqual(rules.group, .nineBall)
        XCTAssertEqual(rules.family, .folk)
        let tournament = rules.converting(to: .tournament, count: 2)
        try tournament.validate()
        XCTAssertEqual(tournament.config.bigGold, 12)
        XCTAssertEqual(tournament.playerCount, 2)
        // 开球位必须落在实际人数里，否则请求会写出不存在的 p2。
        XCTAssertNil(tournament.initialBreakerParticipantId)
        let back = tournament.converting(to: .folk, count: 3)
        try back.validate()
        XCTAssertEqual(back.config.bigGold, 12)
        XCTAssertEqual(back.config.handoffEnabled, GroupBilliardsRules.defaults(.folk).config.handoffEnabled)
        for variant in [GroupBilliardsVariant.eight, .snooker, .standard] {
            let converted = rules.converting(to: variant)
            try converted.validate()
            XCTAssertEqual(converted.group, GroupBilliardsGroup.group(of: variant))
        }
        // 黑八让局不能超过目标局数。
        var eight = GroupBilliardsRules.defaults(.eight)
        eight.config.handicapRacks = 3
        eight.config.handicapBeneficiary = "p1"
        eight.config.targetRacks = 2
        let narrowed = eight.converting(to: .eight)
        XCTAssertLessThanOrEqual(narrowed.config.handicapRacks ?? 0, 1)
        try narrowed.validate()
    }
    func testTerminalBoundaryAndLedgerBalance() throws {
        for f in try fixtures() {
            var v=f.result
            if f.rules.knownVariant == .folk {v.scores[0].points+=1;XCTAssertThrowsError(try v.validate(rules:f.rules))}
            if f.rules.knownVariant == .eight {v.scores[0].points=0;v.scores[1].points=0;XCTAssertThrowsError(try v.validate(rules:f.rules))}
            if f.rules.knownVariant == .standard {v.completion="early_stop";XCTAssertThrowsError(try v.validate(rules:f.rules))}
        }
    }
    func testOutboxSurvivesRestartAndDiscardCannotResurrect() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("billiards-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let store=GroupBilliardsPersistence(root:root),f=try fixtures()[0]
        let body=GroupBilliardsSubmission(rules:f.rules,participants:f.participants,clientSessionId:"fixture-session",clientRecordId:"fixture-record",playedAt:1,source:"manual",result:f.result)
        let row=GroupBilliardsUpload(id:"record",accountID:"one",groupID:"group",body:body)
        try store.add(row);try store.add(row)
        let restored=GroupBilliardsPersistence(root:root)
        XCTAssertEqual(try restored.rows(accountID:"one").count,1);XCTAssertTrue(try restored.rows(accountID:"two").isEmpty)
        try restored.finish(row,discard:true);try store.add(row);XCTAssertTrue(try restored.rows(accountID:"one").isEmpty)
        try store.finish(row,failure:"NETWORK_FAILED");XCTAssertTrue(try restored.rows(accountID:"one").isEmpty)
    }
    func testFixtureRowsDecodeAsGroupResultsAndRacketRowsStillDecode() throws {
        // 台球行由 `GroupBilliardsRow` 编码：没有 `format`，座位是 participantId/position。
        // 这里直接用磁盘上的真实 fixture 内容（服务端形态）走 `GroupResult` 解码。
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent()
        let data=try Data(contentsOf:root.appendingPathComponent("Fixtures/billiards-v2.json"))
        let file=try XCTUnwrap(try JSONSerialization.jsonObject(with:data) as? [String:Any])
        let rawRows=try XCTUnwrap(file["fixtures"] as? [[String:Any]])
        let expected=try fixtures();XCTAssertEqual(rawRows.count,expected.count)
        for (raw,f) in zip(rawRows,expected) {
            XCTAssertNil(raw["format"])
            var row:[String:Any]=["id":f.id,"groupId":"group","gameId":"game","sport":"billiards","status":"confirmed","playedAt":1,"revision":1]
            for key in ["rules","participants","result"] { row[key]=raw[key] }
            let decoded=try JSONDecoder().decode(GroupResult.self,from:try JSONSerialization.data(withJSONObject:row))
            XCTAssertNil(decoded.rules);XCTAssertEqual(decoded.setScore,.init(a:0,b:0))
            XCTAssertEqual(decoded.format,f.rules.participantMode == "individuals" ? .individuals : .singles)
            XCTAssertEqual(decoded.participants.map(\.memberId),f.participants.map(\.memberId))
            XCTAssertEqual(decoded.participants.map(\.seat),f.participants.map(\.position))
            XCTAssertEqual(decoded.participants.map(\.side),f.participants.map { f.rules.participantMode == "individuals" ? "individuals" : ($0.position == 0 ? "A" : "B") })
            let billiards=try XCTUnwrap(decoded.billiards)
            XCTAssertEqual(billiards.rules,f.rules);XCTAssertEqual(billiards.result,f.result)
            XCTAssertEqual(billiards.participants.map(\.participant),f.participants)
            let round=try JSONDecoder().decode(GroupResult.self,from:try JSONEncoder().encode(decoded))
            XCTAssertEqual(round.billiards?.result,f.result);XCTAssertEqual(round.participants.map(\.memberId),f.participants.map(\.memberId))
        }
        let racket="{\"id\":\"r\",\"groupId\":\"g\",\"gameId\":\"game\",\"format\":\"singles\",\"sport\":\"tennis\",\"setScore\":{\"a\":2,\"b\":0},\"participants\":[{\"memberId\":\"a\",\"side\":\"A\",\"seat\":0},{\"memberId\":\"b\",\"side\":\"B\",\"seat\":0}],\"playedAt\":1,\"status\":\"confirmed\",\"revision\":1}"
        let decoded=try JSONDecoder().decode(GroupResult.self,from:Data(racket.utf8))
        XCTAssertNil(decoded.billiards);XCTAssertEqual(decoded.sport,.tennis);XCTAssertEqual(decoded.format,.singles)
        XCTAssertEqual(decoded.setScore,.init(a:2,b:0));XCTAssertEqual(decoded.participants.map(\.side),["A","B"])
    }
    func testCorruptBilliardsStoreDegradesWithoutThrowing() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("billiards-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        for name in ["sources.json","outbox.json","rules.json"] { try Data("{not json".utf8).write(to:root.appendingPathComponent(name)) }
        let store=GroupBilliardsPersistence(root:root),f=try fixtures()[0]
        let record=ScoreboardRecord(id:"record",gameType:.nineBall,startTime:Date(timeIntervalSince1970:1),endTime:Date(timeIntervalSince1970:2),team1Name:"A",team2Name:"B",team1FinalScore:0,team2FinalScore:0,totalScoreChanges:1)
        XCTAssertEqual(store.annotate(record).id,record.id);XCTAssertNil(store.annotate(record).billiardsSource)
        XCTAssertTrue(try store.rows(accountID:"one").isEmpty);XCTAssertNil(try store.source(recordID:"record"));XCTAssertNil(try store.rememberedRules(accountID:"one",groupID:"g"))
        let quarantined=try FileManager.default.contentsOfDirectory(atPath:root.path).filter{$0.hasPrefix("sources.json.corrupt-")}
        XCTAssertEqual(quarantined.count,1)
        // 坏文件隔离后同一份存储可以自愈：写入并读回。
        let source=GroupBilliardsSource(accountID:"one",groupID:"g",groupName:"group",clientSessionID:"session",rules:f.rules,participants:f.participants,names:f.participants.map(\.memberId))
        try store.saveSource(source,recordID:"record");try store.rememberRules(f.rules,accountID:"one",groupID:"g")
        XCTAssertEqual(try store.source(recordID:"record")?.groupID,"g");XCTAssertEqual(try store.rememberedRules(accountID:"one",groupID:"g"),f.rules)
        XCTAssertEqual(store.annotate(record).billiardsSource?.clientSessionID,"session")
    }
    func testRematchDropsActivityBindingAndRetainsRulesAndMembers() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("billiards-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let store=GroupBilliardsPersistence(root:root),f=try fixtures()[0]
        let source=GroupBilliardsSource(accountID:"one",groupID:"g",groupName:"group",clientSessionID:"old",gameID:"game",activityID:"act",activitySessionID:"slot",rules:f.rules,participants:f.participants,names:["A","A","C"])
        try store.saveSource(source,recordID:"old");try store.inheritSource(from:"old",to:"new")
        let next=try XCTUnwrap(store.source(recordID:"new"));XCTAssertNil(next.activityID);XCTAssertNil(next.gameID);XCTAssertEqual(next.rules,f.rules);XCTAssertEqual(next.participants,f.participants)
    }
}
