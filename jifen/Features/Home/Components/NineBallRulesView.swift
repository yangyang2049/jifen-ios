import ScoreCore
import SwiftUI

struct NineBallRulesView: View {
    var folk: NineBallChaseConfig = .init()
    var tournament = NineBallChaseConfig(ruleFamily: .tournament)
    /// The other family has no saved match configuration, so label its values as examples.
    var presetFamily: NineBallRuleFamily? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var feedback = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                ruleGroup(nineBallText("nine_ball_folk", "Casual chase"), id: "folk") {
                    paragraph("nine_ball_help_folk_intro", "Points transfer between players: the winner gains what the others pay. 14710 and 1357 use the same casual rules in this app, with different point values.")
                    presetNotice(for: .folk)
                    scores(folk)
                    item("nine_ball_help_wins", "Big gold, small gold and normal wins", String.localizedStringWithFormat(nineBallText("nine_ball_help_folk_wins", "Big gold: the breaker clears the rack; every opponent pays %1$d. Small gold: a qualifying clearance after taking over; the payer pays %2$d. Normal win: one payer pays %3$d, initially the winner’s previous seat. Players confirm the actual payer."), folk.bigGold, folk.smallGold, folk.normalWin))
                    paragraph(folk.smallGoldAllPay ? "nine_ball_help_all_pay" : "nine_ball_help_breaker_pay", folk.smallGoldAllPay ? "Small gold: every other player pays." : "Small gold: only this rack’s breaker pays; other players are unchanged.")
                    item("nine_ball_golden_nine", "Golden 9", String.localizedStringWithFormat(nineBallText("nine_ball_help_golden", "A legal 9 on the break or a legal combination into the 9 is a separate golden-9 result in this preset. Each opponent pays %d. Its value is configured separately from the four scheme numbers."), folk.goldenNine))
                    item("nine_ball_help_fouls_handoff", "Fouls & handoff", String.localizedStringWithFormat(nineBallText("nine_ball_help_folk_fouls", "A foul transfers %d from the offender to the next seat, who receives ball in hand. No extra ball-in-hand points. A handoff selects another player to continue without scoring or ending the rack. This casual preset does not track three-foul losses."), folk.foul))
                    paragraph(folk.handoffEnabled ? "nine_ball_help_handoff_on" : "nine_ball_help_handoff_off", folk.handoffEnabled ? "Handoff is enabled." : "Handoff is disabled.")
                    item("nine_ball_help_next_break", "Next break", nineBallText(folk.goldRetainsBreak ? "nine_ball_help_folk_break_retain" : "nine_ball_help_folk_break_next", folk.goldRetainsBreak ? "After a normal win or small gold, the next seat after the winner breaks. After big gold or golden 9, the winner breaks again." : "After any winning result, the next seat after the winner breaks."))
                    paragraph("nine_ball_help_agreement", "These are app presets, not a national standard. Agree on the rules with everyone before starting.")
                }
                ruleGroup(nineBallText("nine_ball_tournament", "Tournament points"), id: "tournament") {
                    paragraph("nine_ball_help_tournament_intro", "Two players accumulate points independently. Scoring does not deduct points from the opponent. Losing a rack does not mean losing the match.")
                    presetNotice(for: .tournament)
                    scores(tournament)
                    item("nine_ball_help_wins", "Big gold, small gold and normal wins", String.localizedStringWithFormat(nineBallText("nine_ball_help_event_wins", "Big gold (%1$d): the breaker runs out. Small gold (%2$d): includes a legal 9 on the break, all nine object balls pocketed on the break, or a continuous break-and-combination into the 9 after potting on the break. Away from the break, a runout from a table still containing the 1 and 9 qualifies; a combination during that runout does not. Other legal wins score %3$d."), tournament.bigGold, tournament.smallGold, tournament.normalWin))
                    item("nine_ball_help_break_nine", "9 on the break", nineBallText("nine_ball_help_event_nine", "A legal 9 on the break scores small gold. There is no separate golden-9 category. If the break also contains a foul, spot the 9 and apply the foul; the opponent has ball in hand."))
                    item("nine_ball_third_foul", "Third-foul loss", String.localizedStringWithFormat(nineBallText("nine_ball_help_event_fouls", "For each player, count fouls within the same rack, not necessarily consecutively. The first two give the opponent %1$d each. The third gives %2$d and loses the rack. Do not add another foul or normal-win award. Three fouls therefore award %3$d in total. Clear both counts at the next rack."), tournament.foul, tournament.thirdFoul, 2 * tournament.foul + tournament.thirdFoul))
                    item("nine_ball_help_defense_break", "Safety & break order", nineBallText("nine_ball_help_event_defense", "Legal safeties are allowed and do not score separately. There is no casual handoff action. A third-foul loss gives the rack to the opponent."))
                    paragraph(tournament.breakRule == .winner ? "nine_ball_winner_breaks" : "nine_ball_alternate_breaks", tournament.breakRule == .winner ? "Winner breaks" : "Alternate breaks")
                    item("nine_ball_total_racks", "Total racks", String.localizedStringWithFormat(nineBallText("nine_ball_help_event_racks", "Play %d total racks, not a race to that many wins. Higher points win; ties continue into extra racks. After a rack, finish early only if the trailing player cannot tie even using the remaining racks’ maximum points, including foul awards and custom values."), tournament.totalRacks))
                    item("nine_ball_help_source", "Rule reference", nineBallText("nine_ball_help_source_body", "This scoring example references the Duya Legends Chinese Nine-ball Standard Rules dated 16 October 2025. Break order, rack count and supplements depend on the event. This is not labeled the latest official Juejin edition."))
                }
                ruleGroup(nineBallText("nine_ball_help_differences", "Differences"), id: "compare") {
                    comparisonRow(nineBallText("nine_ball_folk", "Casual chase"), nineBallText("nine_ball_tournament", "Tournament points"), heading: true)
                    comparisonRow(nineBallText("nine_ball_compare_transfer", "Winner gains; payers lose the same amount."), nineBallText("nine_ball_compare_accumulate", "Scorer gains; opponent’s score stays unchanged."))
                    comparisonRow(nineBallText("nine_ball_compare_golden", "Separate golden 9; default small gold paid by the breaker."), nineBallText("nine_ball_compare_small", "Legal 9 on the break is small gold; no payer."))
                    comparisonRow(nineBallText("nine_ball_compare_folk_foul", "No automatic three-foul loss; optional handoff."), nineBallText("nine_ball_compare_event_foul", "Third foul loses the rack; legal safeties; no handoff."))
                    comparisonRow(nineBallText("nine_ball_compare_folk_players", "2–4 individual players"), nineBallText("nine_ball_compare_event_players", "Two-player singles"))
                    paragraph("nine_ball_help_same_points", "The same point numbers do not imply the same rules. Check point transfers versus accumulation, golden 9, fouls and break order.")
                }
            }.padding(20)
        }
        .background(Theme.backgroundColor)
        .navigationTitle(nineBallText("nine_ball_rules_help", "Format guide"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(NSLocalizedString("done", comment: "")) { dismiss() }.tint(Theme.primary) } }
        .navigationDestination(isPresented: $feedback) {
            // 标签随语言切换，避免英文环境下反馈标题仍是中文（沿用 GroupViews 的做法）。
            FeedbackListView(initiallyCreate: true,
                             initialCreateTitle: "#\(nineBallText("nine_ball_rules_title", "Nine-ball chase"))# ")
        }
        .presentationDetents([.large])
    }
    private func ruleGroup<Content: View>(_ title: String, id: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionTitleView(title: title, font: .system(size: 17, weight: .semibold))
            content()
            if AppFeatureFlags.feedbackEntryEnabled {
                Divider()
                Button { feedback = true } label: {
                    HStack {
                        Text(nineBallText("nine_ball_feedback_prompt", "Found a problem or have an idea?")).foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 8)
                        Text(nineBallText("nine_ball_feedback_action", "Send feedback")).foregroundStyle(Theme.primary)
                        Image(systemName: "chevron.right").foregroundStyle(Theme.primary)
                    }.font(.system(size: 12)).frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityIdentifier("nine_ball_feedback_\(id)")
            }
        }.accessibilityIdentifier("nine_ball_help_\(id)")
    }
    @ViewBuilder private func presetNotice(for family: NineBallRuleFamily) -> some View {
        if presetFamily == family {
            paragraph("nine_ball_help_preset_values", "Preset example; values are not from the current match.")
        }
    }
    private func paragraph(_ key: String, _ fallback: String) -> some View { Text(nineBallText(key, fallback)).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true) }
    private func item(_ key: String, _ fallback: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(nineBallText(key, fallback)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func scores(_ config: NineBallChaseConfig) -> some View {
        HStack(spacing: 0) {
            ForEach(NineBallPointField.summary(for: config.ruleFamily)) { field in
                VStack(spacing: 5) {
                    Text(String(config[keyPath: field.keyPath])).font(.system(size: 19, weight: .semibold)).monospacedDigit()
                    Text(field.title).font(.system(size: 10)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }.frame(maxWidth: .infinity)
            }
        }.padding(.vertical, 12).background(Theme.dialogControlBackground, in: RoundedRectangle(cornerRadius: 9))
    }
    private func comparisonRow(_ left: String, _ right: String, heading: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(left).frame(maxWidth: .infinity, alignment: .leading)
            Text(right).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.system(size: 12, weight: heading ? .semibold : .regular)).foregroundStyle(heading ? Theme.textPrimary : Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true).padding(.bottom, 12).overlay(alignment: .bottom) { Divider() }
    }
}
