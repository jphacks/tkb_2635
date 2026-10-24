"""夜間利用の調査用に、公式ページの本文とリンクを比較可能な形へ整える。"""

import hashlib
import re
import time
import unicodedata
from html.parser import HTMLParser
from socket import timeout as SocketTimeout
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


def normalize(value):
    return " ".join(unicodedata.normalize("NFKC", value).split())


class OfficialRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urlsplit(newurl).scheme != "https" or urlsplit(newurl).hostname != urlsplit(req.full_url).hostname:
            raise ValueError("別のホストへの転送です。公式URLを人が確認してください")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def download_once(url):
    if urlsplit(url).scheme != "https":
        raise ValueError("HTTPSの公式ページを指定してください")
    request = Request(url, headers={"User-Agent": "AsteraNightAccessCheck/1.0"})
    with build_opener(OfficialRedirect()).open(request, timeout=25) as response:
        if response.headers.get_content_type() != "text/html":
            raise ValueError("HTMLの案内ページではありません")
        data = response.read(3_000_001)
        if len(data) > 3_000_000:
            raise ValueError("ページが大きすぎます")
        encoding = response.headers.get_content_charset()
        if not encoding:
            found = re.search(br'charset\s*=\s*["\']?([\w-]+)', data[:8192], re.I)
            encoding = found[1].decode("ascii") if found else "utf-8"
        return data.decode(encoding)


def download(url):
    for attempt in range(2):
        try:
            return download_once(url)
        except HTTPError as error:
            if attempt or error.code not in {429, 500, 502, 503, 504}:
                raise
        except (URLError, TimeoutError, SocketTimeout):
            if attempt:
                raise
        # 一時的な障害だけ1回再試行し、恒常的な取得不可を隠さない。
        time.sleep(1)


class PageContent(HTMLParser):
    ignored = {"script", "style", "noscript", "nav", "header", "footer", "aside", "svg"}
    void = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}

    def __init__(self, url):
        super().__init__(convert_charrefs=True)
        self.url = url
        self.stack = []
        self.parts = []
        self.title = []

    def handle_starttag(self, tag, attrs):
        hidden = any(item[1] for item in self.stack) or tag in self.ignored
        if tag not in self.void:
            self.stack.append((tag, hidden))
        if hidden:
            return
        attrs = dict(attrs)
        # お知らせの見出しだけでなくリンク先の差し替えも検知する。
        value = attrs.get("href") if tag == "a" else attrs.get("src") if tag == "img" else None
        if value and not value.startswith(("#", "javascript:", "data:", "mailto:", "tel:")):
            target = urljoin(self.url, value)
            if urlsplit(target).scheme in {"http", "https"}:
                self.parts.append(f"[{tag}:{target}]")
        if tag == "img" and attrs.get("alt"):
            self.parts.append(attrs["alt"])

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in self.void:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        for index in range(len(self.stack) - 1, -1, -1):
            if self.stack[index][0] == tag:
                del self.stack[index:]
                break

    def handle_data(self, data):
        if any(tag == "title" for tag, _ in self.stack):
            self.title.append(data)
        if not any(hidden for _, hidden in self.stack):
            self.parts.append(data)


def snapshot(source, html):
    parser = PageContent(source["url"])
    parser.feed(html)
    title = normalize(" ".join(parser.title))
    body = normalize(" ".join(parser.parts))
    if normalize(source["identity"]) not in title or len(body) < 100:
        raise ValueError("施設名または本文を確認できません。案内の移転・形式変更を確認してください")
    for marker in source.get("requiredMarkers", []):
        if normalize(marker) not in body:
            raise ValueError(f"必要な見出しを確認できません: {marker}")
    sections = []
    for bounds in source.get("sections", []):
        start = body.index(normalize(bounds[0]))
        end = body.index(normalize(bounds[1]), start + len(normalize(bounds[0])))
        sections.append(body[start:end])
    content = "\n".join(sections) if sections else body
    return {"url": source["url"], "title": title,
            "sha256": hashlib.sha256(content.encode("utf-8")).hexdigest(), "content": content}
