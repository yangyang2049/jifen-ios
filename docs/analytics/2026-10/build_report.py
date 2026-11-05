#!/usr/bin/env python3
"""Build the offline October analytics report from GA4's aggregate CSV exports."""
from __future__ import annotations

import csv
import hashlib
import io
import json
import math
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "source"
CST = timezone(timedelta(hours=8))


def raw_csv(name: str) -> list[list[str]]:
    text = (SOURCE / name).read_text(encoding="utf-8-sig")
    lines = [line for line in text.splitlines() if line and not line.startswith("#")]
    return list(csv.reader(io.StringIO("\n".join(lines))))


def records(name: str) -> list[dict]:
    rows = raw_csv(name)
    return [dict(zip(rows[0], row)) for row in rows[1:] if row[0]]


def totals(name: str) -> dict:
    rows = raw_csv(name)
    return dict(zip(rows[0], rows[1]))


def number(value: str):
    x = float(value)
    return int(x) if x.is_integer() else round(x, 6)


def metric_row(row: dict) -> dict:
    fields = {
        "Total users": "users", "Active users": "active", "New users": "new",
        "Returning users": "returning", "Sessions": "sessions",
        "Engaged sessions": "engaged", "Engagement rate": "engagementRate",
        "User engagement": "seconds", "Views": "views", "Event count": "events",
        "Total revenue": "revenue", "Average engagement time per session": "sessionSeconds",
    }
    out = {dest: number(row[src]) for src, dest in fields.items() if src in row}
    if "Stream name" in row:
        out["platform"] = "ios" if row["Stream name"] == "iScoreboard" else "gp"
    return out


NAMES = {
    "football_scoreboard": "足球", "football_5v5_scoreboard": "五人制足球",
    "basketball_scoreboard": "篮球", "three_basketball_scoreboard": "三人篮球",
    "shot_training_scoreboard": "投篮训练", "badminton_scoreboard": "羽毛球单打",
    "badminton_doubles_scoreboard": "羽毛球双打", "pingpong_scoreboard": "乒乓球单打",
    "pingpong_doubles_scoreboard": "乒乓球双打", "tennis_scoreboard": "网球单打",
    "tennis_doubles_scoreboard": "网球双打", "soft_tennis_scoreboard": "软式网球单打",
    "soft_tennis_doubles_scoreboard": "软式网球双打", "padel_scoreboard": "板式网球",
    "pickleball_scoreboard": "匹克球单打", "pickleball_doubles_scoreboard": "匹克球双打",
    "volleyball_scoreboard": "排球", "air_volleyball_scoreboard": "气排球",
    "beach_volleyball_scoreboard": "沙滩排球", "billiards_scoreboard": "台球（基础计分）",
    "eight_ball_scoreboard": "黑八追局", "nine_ball_scoreboard": "九球追分",
    "snooker_scoreboard": "斯诺克", "foosball_scoreboard": "桌上足球",
    "shuttlecock_scoreboard": "毽球", "squash_scoreboard": "壁球",
    "boxing_scoreboard": "拳击", "archery_scoreboard": "射箭",
    "simple_score_page": "简单计分", "multi_group_score": "多人计分",
    "counter_scoreboard": "计数器", "doudizhu_score": "斗地主",
    "guandan_score": "掼蛋", "shengji_score": "升级", "uno_score": "UNO",
    "go_timer": "围棋计时", "xiangqi_timer": "中国象棋计时", "chess_timer": "国际象棋计时",
    "checkers_timer": "跳棋计时", "cube_timer": "魔方计时", "stopwatch_page": "秒表",
    "countdown_page": "倒计时", "flip_coin": "抛硬币", "dice_tool": "掷骰子",
    "whistle_tool": "哨子", "random_team": "随机分组", "red_yellow_card": "红黄牌",
    "fullscreen_barrage": "全屏弹幕", "points_table": "积分表", "points_table_detail": "积分表详情",
    "date_time_tool": "日期时间工具", "aa_calculator": "AA 计算器", "ten_second_challenge": "十秒挑战",
    "home_tab": "首页", "score_tab": "计分 Tab", "timer_tab": "计时 Tab", "records_tab": "记录 Tab",
    "me_tab": "我的 Tab", "sports_record_detail": "比赛记录详情", "multiscore_record_detail": "多组计分记录详情",
    "timer_record_detail": "计时记录详情", "tools_page": "工具列表", "vip_page": "会员页",
    "login_page": "登录页", "password_login_page": "密码登录", "qr_login_page": "扫码登录",
    "profile_page": "个人资料", "about_us_page": "关于我们", "faq_page": "常见问题",
    "feedback_page": "反馈页", "feedback_tab": "反馈页", "feedback_detail_page": "反馈详情",
    "cast_page": "投屏连接", "display_connection_screen": "投屏连接",
    "scoreboard_settings_page": "计分板设置", "common_names_page": "常用名称", "common_places_page": "常用地点",
    "create_booking_page": "创建预约", "booking_detail_page": "预约详情", "schedule_list": "预约列表",
    "group_create_page": "创建小组", "group_list_page": "小组列表", "legal_web_page": "法律协议页",
    "(not set)": "页面名称未设置",
}
TOOLS = {"flip_coin", "dice_tool", "whistle_tool", "random_team", "red_yellow_card", "fullscreen_barrage", "points_table", "date_time_tool", "aa_calculator", "ten_second_challenge"}
TIMERS = {"go_timer", "xiangqi_timer", "chess_timer", "checkers_timer", "cube_timer", "stopwatch_page", "countdown_page"}
GENERAL = {"simple_score_page", "multi_group_score", "counter_scoreboard", "doudizhu_score", "guandan_score", "shengji_score", "uno_score"}


def category(name: str) -> str:
    if name in TOOLS:
        return "tool"
    if name in TIMERS:
        return "timer"
    if name in GENERAL:
        return "general"
    if name.endswith("_scoreboard"):
        return "sport"
    return "page"


def table(name: str, dimension: str, output: str) -> list[dict]:
    return [{**metric_row(r), output: r[dimension]} for r in records(name)]


def retention() -> list[dict]:
    # GA4 exports an unlabelled series column. RESERVED_TOTAL duplicates date_range_0.
    # At offsets with no returning users GA4 may emit a zero cohort size, so the
    # denominator must come from day 0, never from a sum of later-offset sizes.
    rows = [r for r in raw_csv("retention-cohorts.csv")[1:]
            if len(r) == 7 and r[3] == "date_range_0" and len(r[1]) == 8 and r[1].isdigit()]
    output = []
    for store, platform in [("iTunes", "ios"), ("com.android.vending", "gp")]:
        group = [r for r in rows if r[2] == store]
        base = {r[1]: int(r[4]) for r in group if r[0] == "0000"}
        assert len(base) == 31
        for offset in (1, 3, 7, 14, 21, 28):
            cutoff = date(2026, 10, 30) - timedelta(days=offset)
            mature = {d: n for d, n in base.items() if d <= cutoff.strftime("%Y%m%d")}
            denominator = sum(mature.values())
            numerator = sum(int(r[5]) for r in group if int(r[0]) == offset and r[1] in mature)
            assert 0 <= numerator <= denominator
            p = numerator / denominator if denominator else 0
            z = 1.96
            center = (p + z*z/(2*denominator)) / (1+z*z/denominator)
            radius = z * math.sqrt(p*(1-p)/denominator+z*z/(4*denominator**2)) / (1+z*z/denominator)
            output.append({"platform": platform, "day": offset, "returned": numerator,
                           "eligible": denominator, "rate": p, "low": max(0, center-radius),
                           "high": min(1, center+radius), "cutoff": cutoff.isoformat()})
    return output


def main():
    download_hashes = {}
    for path in Path.home().joinpath("Downloads").glob("download*.csv"):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        download_hashes[digest] = datetime.fromtimestamp(path.stat().st_mtime, CST).isoformat(timespec="seconds")
    files = []
    for path in sorted(SOURCE.glob("*.csv")):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        files.append({"file": path.name, "sha256": digest, "bytes": path.stat().st_size,
                      "exportedAt": download_hashes.get(digest)})
    data = {
        "meta": {"property": "iscoreboard", "propertyId": "555327954",
                 "dateStart": "2026-10-01", "dateEnd": "2026-10-31",
                 "timezone": "GMT+04:00", "currency": "USD", "provisional": True,
                 "generatedAt": datetime.now(CST).isoformat(timespec="seconds"),
                 "retentionObservedThrough": "2026-10-30",
                 "exploration": "https://analytics.google.com/analytics/web/?authuser=0&hl=en-US#/analysis/a254588017p555327954/edit/GJAHY-6nRAaOr-Bc8nlDYw",
                 "filters": ["Stream name matches regex ^iScoreboard( Android)?$", "App store matches regex ^(iTunes|com.android.vending)$"],
                 "files": files},
        "names": NAMES,
        "categories": {key: category(key) for key in NAMES},
        "summary": [metric_row(r) for r in records("store-summary.csv")],
        "streamSummary": [{**metric_row(r), "stream": r["Stream name"]} for r in records("platform-summary.csv")],
        "installation": [{**metric_row(r), "store": r["App store"]} for r in records("installation-sources.csv")],
        "countries": table("countries.csv", "Country", "country"),
        "daily": table("daily.csv", "Date", "date"),
        "screens": table("screens.csv", "Page title and screen name", "screen"),
        "countryScreens": [{**metric_row(r), "screen": r["Page title and screen name"], "country": r["Country"]} for r in records("country-screens.csv")],
        "events": table("events.csv", "Event name", "event"),
        "versions": table("versions.csv", "App version", "version"),
        "devices": table("devices.csv", "Device category", "device"),
        "languages": table("languages.csv", "Language", "language"),
        "acquisition": [{**metric_row(r), "source": r["First user source"], "medium": r["First user medium"]} for r in records("acquisition.csv")],
        "retention": retention(),
    }
    # Exact additive reconciliation is meaningful for event and view counts.
    assert sum(r["views"] for r in data["screens"]) == int(totals("screens.csv")["Views"]) == 11221
    assert sum(r["views"] for r in data["countryScreens"]) == 11221
    assert sum(r["events"] for r in data["events"]) == 64627
    assert len(data["countryScreens"]) == 943
    assert [(r["users"], r["active"]) for r in data["summary"]] == [(632, 613), (66, 66)]
    event_rows = records("country-screen-events.csv")
    assert sum(int(r["Event count"]) for r in event_rows) == 64627
    assert len(event_rows) == 4189
    contexts = Counter()
    for r in event_rows:
        if r["Stream name"] == "iScoreboard" and r["Event name"] == "match_start":
            contexts[r["Page title and screen name"]] += int(r["Event count"])
    data["matchStartContext"] = dict(contexts)
    data["meta"]["eventCountryScreenRows"] = len(event_rows)
    assert contexts["home_tab"] == 501 and sum(contexts.values()) == 1917
    (ROOT / "data.json").write_text(json.dumps(data, ensure_ascii=False, indent=2)+"\n")
    (ROOT / "source-manifest.json").write_text(json.dumps(data["meta"], ensure_ascii=False, indent=2)+"\n")
    compact = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    template = (ROOT / "report.template.html").read_text()
    assert template.count("__REPORT_DATA__") == 1
    (ROOT / "index.html").write_text(template.replace("__REPORT_DATA__", compact))
    print(f"Built {ROOT / 'index.html'} ({(ROOT / 'index.html').stat().st_size:,} bytes)")
    print("Verified: store scope, 11,221 views, 64,627 events, 943 country-page rows, 4,189 event-country-page rows; retention maturity and denominators.")


if __name__ == "__main__":
    main()
