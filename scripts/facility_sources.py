"""公式ページから施設情報を読む。JavaScriptは実行せず、JSON文字列だけを解析する。"""

import ast
import json
import re
import unicodedata
from html.parser import HTMLParser
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen

SKY = "https://www.shibuya-scramble-square.com/sky/"
TOCHO = "https://www.zaimu.metro.tokyo.lg.jp/tochousha/goannai/tenbou"
KITTE = "https://marunouchi.jp-kitte.jp/guide/facilities.jsp"
HOLIDAYS = "https://www8.cao.go.jp/chosei/shukujitsu/syukujitsu.csv"


class SourceError(ValueError):
    pass


class PageText(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
        self.skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style"):
            self.skip += 1

    def handle_endtag(self, tag):
        if tag in ("script", "style"):
            self.skip = max(0, self.skip - 1)

    def handle_data(self, data):
        if not self.skip:
            self.parts.append(data)


def text(html):
    parser = PageText()
    parser.feed(html)
    return " ".join(unicodedata.normalize("NFKC", " ".join(parser.parts)).split())


def download(url):
    request = Request(url, headers={"User-Agent": "AsteraFacilityCheck/1.0"})
    with urlopen(request, timeout=30) as response:
        # 知らないサイトへの転送や巨大なレスポンスは採用しない。
        if urlparse(response.url).scheme != "https" or urlparse(response.url).hostname != urlparse(url).hostname:
            raise SourceError("公式サイト以外へのリダイレクト")
        data = response.read(5_000_001)
        if len(data) > 5_000_000:
            raise SourceError("ページが大きすぎます")
        encoding = response.headers.get_content_charset() or ("cp932" if url.endswith(".csv") else "utf-8")
        return data.decode(encoding)


def match(pattern, value):
    result = re.search(pattern, value)
    if result is None:
        raise SourceError(f"公式ページの形式が変わりました: {pattern}")
    return result


def clock(value):
    value = value.strip()
    if not re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", value):
        raise SourceError(f"時刻が不正です: {value}")
    return value


def json_blocks(script):
    for found in re.finditer(r"JSON\.parse\(('(?:\\.|[^'\\])*')\)", script):
        try:
            yield json.loads(ast.literal_eval(found.group(1)))
        except (ValueError, SyntaxError):
            continue


def nodes(value):
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from nodes(child)
    elif isinstance(value, list):
        for child in value:
            yield from nodes(child)


def unique(values, label):
    candidates = {json.dumps(v, ensure_ascii=False, sort_keys=True): v for v in values}
    if len(candidates) != 1:
        raise SourceError(f"{label}を一意に読めません ({len(candidates)}件)")
    return next(iter(candidates.values()))


def sky_script(page, marker, fetch):
    paths = re.findall(r'<script\b[^>]*\bsrc="([^"]+)"', page)
    urls = [urljoin(SKY, p) for p in paths if marker in p and p.startswith("/sky/_next/static/")]
    return fetch(unique(urls, marker))


def parse_sky(app_script, ticket_script):
    app_nodes = [n for b in json_blocks(app_script) for n in nodes(b)]
    hours = unique([n for n in app_nodes if isinstance(n, dict)
                    and {"open_hour", "close_hour", "last_hour"} <= n.keys()], "営業時間")
    ticket_nodes = [n for b in json_blocks(ticket_script) for n in nodes(b)]
    basic = unique([n for n in ticket_nodes if isinstance(n, dict)
                    and n.get("title") == "入場チケット" and "tickets" in n], "通常チケット")
    roof = unique([n for n in ticket_nodes if isinstance(n, dict)
                   and {"head", "list0", "list1"} <= n.keys()], "屋上の注意")
    prices = basic["tickets"]
    if prices.get("name0") != "大人" or len(prices["body0"]) != 2:
        raise SourceError("大人料金の区分が変わりました")
    fee = "WEB大人: " + " / ".join(text(p["title"] + " " + p["content"]) for p in prices["body0"])
    fee += "。小人: " + text(prices["body1"]) + "（年齢区分・窓口料金は公式サイト参照）"
    closure = text(unique([n["body"] for n in roof["head"] if n["title"] == "屋上閉鎖について"], "屋上閉鎖"))
    prohibited = [text(n["text"]) for n in roof["list1"]["body"]]
    allowed = [text(n["text"]) for n in roof["list0"]["body"]]
    notes = " ".join(text(n) for n in basic["notes"])
    if "WEB" not in notes or "完売" not in notes:
        raise SourceError("チケット販売条件を確認できません")
    return {
        "openingHours": {"alwaysOpen": False, "open": clock(hours["open_hour"]),
                         "close": clock(hours["close_hour"]), "lastAdmission": clock(hours["last_hour"]),
                         "note": "通常営業時間。特別営業・臨時休館・当日の屋上開放状況は公式案内を確認。"},
        "admissionFee": fee,
        "reservationRequired": True,
        "accessConditions": "日時指定券の事前購入を推奨。大人券はWEB完売時、窓口も完売。屋上の開放は天候次第。"
                            + closure + " 屋上への持込不可: " + "、".join(prohibited)
                            + "。持込可能: " + "、".join(allowed) + "。",
        "officialWebsite": SKY + "ticket/",
    }


def parse_tocho(html):
    page = text(html)
    admission = match(r"南展望室 入室可能時間:([0-9]+)時([0-9]+)分[~〜～]([0-9]+)時([0-9]+)分", page)
    hours = match(r"開室時間 ([0-9]+)時([0-9]+)分[~〜～]([0-9]+)時([0-9]+)分", page)
    values = [clock(f"{int(hours[i]):02}:{int(hours[i+1]):02}") for i in (1, 3)]
    last = clock(f"{int(admission[3]):02}:{int(admission[4]):02}")
    for required in ["入室料金 無料", "事前予約、団体予約は受け付けしておりません", "第1及び第3火曜日",
                     "祝日", "翌", "12月29日", "1月2日", "三脚", "照明の一部消灯"]:
        if required not in page:
            raise SourceError(f"都庁の条件が変わりました: {required}")
    return {
        "openingHours": {"alwaysOpen": False, "open": values[0], "close": values[1], "lastAdmission": last,
                         "note": "第1・第3火曜休室（祝日の場合は翌平日）。12/29〜31・1/2〜3、庁舎点検日休室。"
                                 "元日の特別開室・東京マラソン日・臨時閉室は公式の開室スケジュールで確認。"},
        "admissionFee": "無料", "reservationRequired": False,
        "accessConditions": "45階の屋内展望室。事前予約・団体予約の受付なし。三脚等を使う撮影は不可。"
                            "悪天候等による急な閉室あり。一部照明の消灯案内あり（照明の段階評価は未確認）。"
                            "公式案内に北東・南東・南西・西の眺望紹介があるが、窓ごとの可視方位・高度は未確認。",
        "officialWebsite": TOCHO,
    }


def parse_kitte(html):
    page = text(html)
    # 同じページの「旧郵便局長室」や店舗の営業時間を拾わない。
    garden = match(r"Roof Garden .KITTE Garden.(.+?)SHOP SEARCH", page)[1]
    hours = match(r"\[平日\]([0-9:]+)[~〜～]([0-9:]+) \[土日祝\]([0-9:]+)[~〜～]([0-9:]+)", garden)
    for required in ["天候により閉鎖", "入場 無料", "JR東京駅丸の内駅舎"]:
        if required not in garden:
            raise SourceError(f"KITTEの条件が変わりました: {required}")
    return {
        "openingHours": {"alwaysOpen": False, "open": clock(hours[1]), "close": clock(hours[2]),
                         "weeklyOverrides": {"1": {"open": clock(hours[3]), "close": clock(hours[4])},
                                             "7": {"open": clock(hours[3]), "close": clock(hours[4])}},
                         "note": "平日 " + hours[1] + "〜" + hours[2] + "、土日祝 " + hours[3] + "〜" + hours[4]
                                 + "。天候による閉鎖あり。臨時休館は公式案内を確認。"},
        "admissionFee": "無料",
        "reservationRequired": None,
        "accessConditions": "6階の屋上庭園。天候により閉鎖する場合あり。JR東京駅丸の内駅舎を望める。"
                            "観測可能な正確な方位範囲・周辺照明の強さは公式情報では未確認。",
        "officialWebsite": KITTE,
    }
