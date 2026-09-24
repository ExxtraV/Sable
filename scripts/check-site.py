#!/usr/bin/env python3
"""Audits the website (website/) for the basics search engines and readers rely on.

For every page: a lang attribute, one h1, headings that never skip a level, a
title, a description, a canonical URL that matches its path, and Open Graph and
Twitter card tags. Blog posts also need og:type article with published and
modified times and BlogPosting JSON-LD. Also: every image has alt text and
width and height; internal links and #anchors resolve; JSON-LD parses; the
home page's softwareVersion matches Info.plist; and sitemap.xml lists every
indexable page (and only real pages) with a valid, not-future lastmod.

Titles over 60 characters and descriptions over 155 are reported as notes, not
failures, because they're the maintainer's prose. Standard library only.
"""
import datetime
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE_DIR = ROOT / "website"
SITE = "https://sablewriter.app"
failures = []
notes = []


def fail(page, message):
    failures.append("%s: %s" % (page, message))


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.lang = None
        self.title = ""
        self.in_title = False
        self.meta = {}
        self.links = []
        self.headings = []
        self.images = []
        self.hrefs = []
        self.ids = set()
        self.ld = []
        self._ld = None
        self.brand_depth = 0

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a:
            self.ids.add(a["id"])
        if tag == "html":
            self.lang = a.get("lang")
        elif tag == "title":
            self.in_title = True
        elif tag == "meta":
            key = a.get("property") or a.get("name")
            if key and "content" in a:
                self.meta.setdefault(key, []).append(a["content"])
        elif tag == "link":
            self.links.append(a)
        elif re.fullmatch(r"h[1-6]", tag):
            self.headings.append(int(tag[1]))
        elif tag == "img":
            self.images.append((a, self.brand_depth > 0))
        elif tag == "a":
            if "href" in a:
                self.hrefs.append(a["href"])
            if "brand" in (a.get("class") or "").split():
                self.brand_depth += 1
        elif tag == "script" and a.get("type") == "application/ld+json":
            self._ld = []

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False
        elif tag == "a" and self.brand_depth:
            self.brand_depth -= 1
        elif tag == "script" and self._ld is not None:
            self.ld.append("".join(self._ld))
            self._ld = None

    def handle_data(self, data):
        if self.in_title:
            self.title += data
        if self._ld is not None:
            self._ld.append(data)


def url_for(path):
    rel = path.relative_to(SITE_DIR).as_posix()
    if rel == "index.html":
        return SITE + "/"
    if rel.endswith("/index.html"):
        return SITE + "/" + rel[:-len("/index.html")]
    return SITE + "/" + rel[:-len(".html")]


def resolve_internal(href, pages):
    """Returns (exists, anchor_ok) for a site-relative link."""
    path, _, anchor = href.partition("#")
    path = path.split("?")[0]
    if path in ("", "/"):
        target = SITE_DIR / "index.html"
    else:
        rel = path.lstrip("/")
        candidates = [SITE_DIR / rel, SITE_DIR / (rel + ".html"), SITE_DIR / rel / "index.html"]
        target = next((c for c in candidates if c.is_file()), None)
    if target is None:
        return False, True
    if anchor and target in pages:
        return True, anchor in pages[target].ids
    return True, True


def check_page(path, page, pages):
    name = path.relative_to(SITE_DIR).as_posix()
    noindex = any("noindex" in v for v in page.meta.get("robots", []))
    if page.lang != "en":
        fail(name, 'needs <html lang="en">.')
    h1s = page.headings.count(1)
    if h1s != 1:
        fail(name, "has %d h1 elements; it should have exactly one." % h1s)
    previous = 0
    for level in page.headings:
        if previous and level > previous + 1:
            fail(name, "heading jumps from h%d to h%d." % (previous, level))
        previous = level
    if not page.title.strip():
        fail(name, "has no <title>.")
    elif len(page.title.strip()) > 60:
        notes.append("%s: title is %d characters (about 60 is the usual limit)." % (name, len(page.title.strip())))
    desc = (page.meta.get("description") or [""])[0]
    if not desc:
        fail(name, "has no meta description.")
    elif len(desc) > 155:
        notes.append("%s: description is %d characters (about 155 is the usual limit)." % (name, len(desc)))
    for tag in ("viewport", "color-scheme"):
        if tag not in page.meta:
            fail(name, "missing <meta name=%s>." % tag)
    for image, decorative in ((a, d) for a, d in page.images):
        src = image.get("src", "?")
        if "alt" not in image or (not image["alt"].strip() and not decorative):
            fail(name, "image %s needs alt text." % src)
        if not image.get("width") or not image.get("height"):
            fail(name, "image %s needs width and height." % src)
        if src.startswith("/"):
            local = SITE_DIR / src.lstrip("/").split("?")[0]
            if not local.is_file():
                fail(name, "image %s doesn't exist." % src)
            elif local.stat().st_size > 300_000:
                fail(name, "image %s is %d KB; compress it." % (src, local.stat().st_size // 1000))
    for href in page.hrefs:
        if href.startswith("/") and not href.startswith("//"):
            exists, anchor_ok = resolve_internal(href, pages)
            if not exists:
                fail(name, "link %s doesn't go anywhere." % href)
            elif not anchor_ok:
                fail(name, "link %s points at a section that doesn't exist." % href)
    graph = []
    for block in page.ld:
        try:
            data = json.loads(block)
        except ValueError as error:
            fail(name, "JSON-LD doesn't parse: %s" % error)
            continue
        graph.extend(data.get("@graph", [data]))
    types = {node.get("@type") for node in graph}
    if noindex:
        return
    canon = [l["href"] for l in page.links if l.get("rel") == "canonical"]
    if canon != [url_for(path)]:
        fail(name, "canonical should be exactly %s (found %s)." % (url_for(path), canon))
    og_type = (page.meta.get("og:type") or [""])[0]
    for key in ("og:type", "og:site_name", "og:url", "og:title", "og:description", "og:image", "og:image:alt",
                "twitter:card", "twitter:title", "twitter:description", "twitter:image"):
        if key not in page.meta:
            fail(name, "missing %s." % key)
    if page.meta.get("og:url") != [url_for(path)]:
        fail(name, "og:url should match the canonical URL.")
    if name.startswith("blog/") and name != "blog/index.html":
        if og_type != "article":
            fail(name, "posts should use og:type article.")
        for key in ("article:published_time", "article:modified_time"):
            if key not in page.meta:
                fail(name, "missing %s." % key)
        if "BlogPosting" not in types:
            fail(name, "missing BlogPosting JSON-LD.")
        if "BreadcrumbList" not in types:
            fail(name, "missing BreadcrumbList JSON-LD.")
    if name == "index.html":
        apps = [n for n in graph if n.get("@type") == "SoftwareApplication"]
        if not apps:
            fail(name, "missing SoftwareApplication JSON-LD.")
        elif apps[0].get("softwareVersion") != app_version():
            fail(name, "softwareVersion is %s but Info.plist says %s. Update the JSON-LD."
                 % (apps[0].get("softwareVersion"), app_version()))
        if "Organization" not in types:
            fail(name, "missing Organization JSON-LD.")


def app_version():
    plist = (ROOT / "Info.plist").read_text(encoding="utf-8")
    return re.search(r"<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>", plist).group(1)


def check_sitemap(pages):
    text = (SITE_DIR / "sitemap.xml").read_text(encoding="utf-8")
    entries = dict((loc, mod) for loc, mod in re.findall(r"<loc>([^<]+)</loc><lastmod>([^<]+)</lastmod>", text))
    if len(entries) != text.count("<loc>"):
        fail("sitemap.xml", "every <url> needs a <loc> and a <lastmod>.")
    indexable = {url_for(p) for p, page in pages.items()
                 if not any("noindex" in v for v in page.meta.get("robots", []))}
    for url in sorted(indexable - set(entries)):
        fail("sitemap.xml", "doesn't list %s." % url)
    for url in sorted(set(entries) - indexable):
        fail("sitemap.xml", "lists %s, which isn't an indexable page." % url)
    today = datetime.date.today()
    for url, mod in entries.items():
        try:
            if datetime.date.fromisoformat(mod) > today + datetime.timedelta(days=1):
                fail("sitemap.xml", "%s has a lastmod in the future." % url)
        except ValueError:
            fail("sitemap.xml", "%s has an invalid lastmod %r." % (url, mod))
    if "Sitemap: %s/sitemap.xml" % SITE not in (SITE_DIR / "robots.txt").read_text(encoding="utf-8"):
        fail("robots.txt", "should point at the sitemap.")


def main():
    pages = {}
    for path in sorted(SITE_DIR.rglob("*.html")):
        page = Page()
        page.feed(path.read_text(encoding="utf-8"))
        pages[path] = page
    if not pages:
        print("No pages found.")
        return 1
    for path, page in pages.items():
        check_page(path, page, pages)
    check_sitemap(pages)
    # Canonicals and descriptions must be unique across pages.
    for label, values in (("canonical", {p: [l["href"] for l in pg.links if l.get("rel") == "canonical"] for p, pg in pages.items()}),
                          ("description", {p: pg.meta.get("description", []) for p, pg in pages.items()})):
        seen = {}
        for path, vals in values.items():
            for v in vals:
                if v in seen:
                    fail(path.relative_to(SITE_DIR).as_posix(), "%s duplicates %s." % (label, seen[v]))
                seen[v] = path.relative_to(SITE_DIR).as_posix()
    for note in notes:
        print("note: " + note)
    for message in failures:
        print("FAIL: " + message)
    if failures:
        print("\n%d problem%s." % (len(failures), "" if len(failures) == 1 else "s"))
        return 1
    print("Site checks passed for %d pages." % len(pages))
    return 0


if __name__ == "__main__":
    sys.exit(main())
