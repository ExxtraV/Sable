#!/usr/bin/env python3
"""Builds the Sable blog from the Markdown files in docs/blog/.

  docs/blog/posts.json        the list of posts: slug, date, optional modified/description
  docs/blog/<slug>.md         each post, exactly as the author wrote it (never edited here)

  website/blog/<slug>.html    one page per post
  website/blog/index.html     the post list, newest first
  website/blog/feed.xml       RSS feed
  website/index.html          the "From the blog" list between the blog-list markers
  website/sitemap.xml         the blog entries between the blog:start and blog:end markers,
                              and the home page's lastmod when a post is newer

Run `python3 scripts/build-blog.py` after adding a post. Run it with --check to
verify the committed output is current without writing anything (CI does this
through scripts/check-blog.py). Standard library only.
"""
import datetime
import html
import json
import re
import shutil
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "blog"
OUT = ROOT / "website" / "blog"
SITEMAP = ROOT / "website" / "sitemap.xml"
HOME = ROOT / "website" / "index.html"
HOME_POSTS = 3
SITE = "https://sablewriter.app"
CSS_VERSION = "17"

OG_ALT = ("The Sable logo, a sable asleep and curled nose to tail with a pen nib tucked into its body, "
          "beside the words Sable Markdown Writer: A Mac App about Focused Writing.")
ORGANIZATION = {"@type": "Organization", "@id": SITE + "/#org", "name": "Sable Markdown Writer",
                "url": SITE + "/", "logo": {"@type": "ImageObject", "url": SITE + "/icon-512.png",
                                            "width": 512, "height": 512},
                "sameAs": ["https://github.com/ExxtraV/Sable"]}
BLOG_DESCRIPTION = "News and notes from the Sable Markdown Writer project."
MONTHS = ["January", "February", "March", "April", "May", "June", "July",
          "August", "September", "October", "November", "December"]


class BuildError(Exception):
    pass


# --- Markdown -> HTML ------------------------------------------------------
# A small CommonMark subset: headings, paragraphs, emphasis, links, autolinks,
# images, code, block quotes, lists, rules. Anything else raises rather than
# guessing, so the author's writing is never silently altered.

LIST_RE = re.compile(r"^( {0,3})([-*+]|\d{1,9}[.)])( +|$)(.*)$")
HEADING_RE = re.compile(r"^ {0,3}(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$")
HR_RE = re.compile(r"^ {0,3}([-*_])( *\1){2,} *$")
FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})\s*([\w+-]*)\s*$")
INLINE_RE = re.compile(
    r"(?P<code>(?P<tick>`+)(?P<codetext>.+?)(?P=tick))"
    r"|(?P<image>!\[(?P<imgalt>[^\]]*)\]\((?P<imgsrc>[^)\s]+)(?:\s+\"(?P<imgtitle>[^\"]*)\")?\))"
    r"|(?P<link>\[(?P<linktext>(?:[^\[\]]|\[[^\]]*\])+)\]\((?P<linkurl>[^)\s]+)(?:\s+\"(?P<linktitle>[^\"]*)\")?\))"
    r"|(?P<autolink><(?P<autourl>https?://[^>\s]+|[^>\s@]+@[^>\s]+)>)"
    r"|(?P<bare>https?://[^\s<>\"]+)"
    r"|(?P<strong>(?P<sm>\*\*|__)(?=\S)(?P<strongtext>.+?)(?<=\S)(?P=sm))"
    r"|(?P<em>\*(?=\S)(?P<emstar>.+?)(?<=\S)\*|(?<!\w)_(?=\S)(?P<emunder>.+?)(?<=\S)_(?!\w))"
    r"|(?P<escape>\\(?P<esc>[\\`*_{}\[\]()#+\-.!>]))",
    re.S,
)


def esc(text):
    return html.escape(text, quote=False)


def attr(text):
    return html.escape(text, quote=True)


def safe_url(url):
    if re.match(r"^(https?://|mailto:|/|#|[\w./-]+$)", url, re.I) is None:
        raise BuildError("Link '%s' isn't http, https or mailto." % url)
    return url


def image_info(src, images):
    """Records the image (relative to docs/blog/) and returns its site path and size."""
    if re.match(r"^[a-z]+:", src, re.I):
        raise BuildError("Image '%s' must be a file next to the post, not a web address." % src)
    source = (SRC / src).resolve()
    if not source.is_file():
        raise BuildError("Image '%s' wasn't found in docs/blog/." % src)
    name = source.name
    if images.get(name, source) != source:
        raise BuildError("Two different images are both named '%s'." % name)
    images[name] = source
    width, height = image_size(source)
    return "/blog/" + name, width, height


def image_size(path):
    data = path.read_bytes()
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", data[16:24])
    if data[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(data):
            if data[i] != 0xFF:
                i += 1
                continue
            marker = data[i + 1]
            if marker in (0xC0, 0xC1, 0xC2):
                height, width = struct.unpack(">HH", data[i + 5:i + 9])
                return width, height
            i += 2 + struct.unpack(">H", data[i + 2:i + 4])[0]
    raise BuildError("Couldn't read the size of %s. Use a PNG or JPEG." % path.name)


def inline(text, images):
    out = []
    pos = 0
    for m in INLINE_RE.finditer(text):
        out.append(esc(text[pos:m.start()]))
        pos = m.end()
        kind = m.lastgroup
        if m.group("code"):
            out.append("<code>%s</code>" % esc(m.group("codetext").strip()))
        elif m.group("image"):
            alt = m.group("imgalt").strip()
            if not alt:
                raise BuildError("Image '%s' has no alt text. Ask the author for it." % m.group("imgsrc"))
            src, width, height = image_info(m.group("imgsrc"), images)
            title = ' title="%s"' % attr(m.group("imgtitle")) if m.group("imgtitle") else ""
            out.append('<img src="%s" alt="%s" width="%d" height="%d" loading="lazy" decoding="async"%s>'
                       % (src, attr(alt), width, height, title))
        elif m.group("link"):
            title = ' title="%s"' % attr(m.group("linktitle")) if m.group("linktitle") else ""
            out.append('<a href="%s"%s>%s</a>' % (attr(safe_url(m.group("linkurl"))), title,
                                                  inline(m.group("linktext"), images)))
        elif m.group("autolink"):
            url = m.group("autourl")
            href = url if re.match(r"https?://", url) else "mailto:" + url
            out.append('<a href="%s">%s</a>' % (attr(href), esc(url)))
        elif m.group("bare"):
            url = m.group("bare")
            trail = ""
            while url and url[-1] in ".,;:!?)\"'":
                trail = url[-1] + trail
                url = url[:-1]
            out.append('<a href="%s">%s</a>%s' % (attr(url), esc(url), esc(trail)))
        elif m.group("strong"):
            out.append("<strong>%s</strong>" % inline(m.group("strongtext"), images))
        elif m.group("em"):
            out.append("<em>%s</em>" % inline(m.group("emstar") or m.group("emunder"), images))
        elif m.group("escape"):
            out.append(esc(m.group("esc")))
        else:
            raise BuildError("Unhandled inline match: %r" % kind)
    out.append(esc(text[pos:]))
    return "".join(out).replace("  \n", "<br>\n")


def starts_block(line):
    """True if this line begins something other than a paragraph continuation."""
    if HEADING_RE.match(line) or HR_RE.match(line) or FENCE_RE.match(line):
        return True
    if line.lstrip().startswith(">") and len(line) - len(line.lstrip()) < 4:
        return True
    m = LIST_RE.match(line)
    return bool(m and m.group(4).strip() and (m.group(2)[0] in "-*+" or m.group(2).rstrip(".)") == "1"))


def parse_blocks(lines, images):
    """Returns a list of (kind, html) so lists can unwrap paragraphs when tight."""
    blocks = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        if line.startswith("    ") or line.startswith("\t"):
            raise BuildError("Indented code blocks aren't supported (line: %r)." % line[:40])
        fence = FENCE_RE.match(line)
        if fence:
            i += 1
            code = []
            while i < len(lines) and not lines[i].strip().startswith(fence.group(1)):
                code.append(lines[i])
                i += 1
            i += 1
            blocks.append(("code", "<pre><code>%s</code></pre>" % esc("\n".join(code))))
            continue
        heading = HEADING_RE.match(line)
        if heading:
            level = len(heading.group(1))
            blocks.append(("h%d" % level, "<h%d>%s</h%d>" % (level, inline(heading.group(2), images), level)))
            i += 1
            continue
        if HR_RE.match(line):
            blocks.append(("hr", "<hr>"))
            i += 1
            continue
        if line.lstrip().startswith(">"):
            quote = []
            while i < len(lines) and lines[i].strip() and lines[i].lstrip().startswith(">"):
                quote.append(re.sub(r"^ {0,3}> ?", "", lines[i]))
                i += 1
            inner = "\n".join(render(parse_blocks(quote, images), tight=False))
            blocks.append(("blockquote", "<blockquote>\n%s\n</blockquote>" % inner))
            continue
        item = LIST_RE.match(line)
        if item:
            html_list, i = parse_list(lines, i, images)
            blocks.append(("list", html_list))
            continue
        para = [line]
        i += 1
        while i < len(lines) and lines[i].strip() and not starts_block(lines[i]):
            para.append(lines[i])
            i += 1
        # Trailing double spaces (a hard break) survive on every line but the last.
        text = "\n".join(p.strip() + ("  " if n < len(para) - 1 and p.endswith("  ") else "")
                         for n, p in enumerate(para))
        blocks.append(("p", inline(text, images)))
    return blocks


def parse_list(lines, i, images):
    first = LIST_RE.match(lines[i])
    ordered = first.group(2)[0].isdigit()
    start = int(first.group(2).rstrip(".)")) if ordered else 1
    items = []
    loose = False
    while i < len(lines):
        m = LIST_RE.match(lines[i])
        if not m or (m.group(2)[0].isdigit() != ordered):
            break
        content_indent = len(m.group(1)) + len(m.group(2)) + max(1, min(len(m.group(3)), 4))
        body = [m.group(4)]
        i += 1
        while i < len(lines):
            line = lines[i]
            if not line.strip():
                # A blank line continues the item only if an indented line follows.
                j = i
                while j < len(lines) and not lines[j].strip():
                    j += 1
                if j < len(lines) and len(lines[j]) - len(lines[j].lstrip()) >= content_indent:
                    body.extend([""] * (j - i))
                    i = j
                    continue
                break
            indent = len(line) - len(line.lstrip())
            if indent >= content_indent:
                body.append(line[content_indent:])
            elif LIST_RE.match(line) or starts_block(line):
                break
            elif body[-1].strip():
                body.append(line.strip())  # lazy paragraph continuation
            else:
                break
            i += 1
        # Blank lines between items make the list loose.
        j = i
        while j < len(lines) and not lines[j].strip():
            j += 1
        nxt = LIST_RE.match(lines[j]) if j < len(lines) else None
        if nxt and nxt.group(2)[0].isdigit() == ordered and j > i:
            loose = True
        if "" in body[:-1] and any(b.strip() for b in body[body.index(""):]):
            loose = True
        items.append(body)
        i = j if (nxt and nxt.group(2)[0].isdigit() == ordered) else i
    tag = "ol" if ordered else "ul"
    open_tag = '<ol start="%d">' % start if ordered and start != 1 else "<%s>" % tag
    rendered = []
    for body in items:
        content = "\n".join(render(parse_blocks(body, images), tight=not loose))
        rendered.append("<li>%s</li>" % content)
    return "%s\n%s\n</%s>" % (open_tag, "\n".join(rendered), tag), i


def render(blocks, tight):
    out = []
    for kind, content in blocks:
        out.append(content if (tight and kind == "p") else
                   "<p>%s</p>" % content if kind == "p" else content)
    return out


def markdown_to_html(text, images):
    lines = text.replace("\r\n", "\n").split("\n")
    return "\n".join(render(parse_blocks(lines, images), tight=False))


# --- Posts -------------------------------------------------------------------

def plain_text(fragment):
    return html.unescape(re.sub(r"<[^>]+>", "", fragment))


def load_posts():
    manifest = json.loads((SRC / "posts.json").read_text(encoding="utf-8"))
    posts = []
    images = {}
    for entry in manifest:
        slug = entry["slug"]
        if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", slug):
            raise BuildError("Slug '%s' should be lowercase words joined by hyphens." % slug)
        source = SRC / (slug + ".md")
        if not source.is_file():
            raise BuildError("docs/blog/%s.md is missing." % slug)
        text = source.read_text(encoding="utf-8")
        lines = text.replace("\r\n", "\n").split("\n")
        first = next((n for n, l in enumerate(lines) if l.strip()), None)
        heading = HEADING_RE.match(lines[first]) if first is not None else None
        if not heading or len(heading.group(1)) != 1:
            raise BuildError("%s must start with a '# Title' heading." % source.name)
        title_html = inline(heading.group(2), images)
        body_html = markdown_to_html("\n".join(lines[first + 1:]), images)
        paragraphs = re.findall(r"<p>(.*?)</p>", body_html, re.S)
        if not paragraphs:
            raise BuildError("%s has no paragraph to use as a summary." % source.name)
        summary_html = paragraphs[0]
        summary = plain_text(summary_html).replace("\n", " ").strip()
        description = entry.get("description")
        if not description:
            sentence = re.match(r"(.+?[.!?])(?:\s|$)", summary, re.S)
            description = sentence.group(1) if sentence else summary
        date = datetime.date.fromisoformat(entry["date"])
        modified = datetime.date.fromisoformat(entry.get("modified", entry["date"]))
        posts.append({
            "slug": slug, "title": plain_text(title_html).strip(), "title_html": title_html,
            "body_html": body_html, "summary_html": summary_html, "summary": summary,
            "description": description, "date": date, "modified": modified,
            "url": "%s/blog/%s" % (SITE, slug),
        })
    posts.sort(key=lambda p: (p["date"], p["slug"]), reverse=True)
    return posts, images


# --- Page templates ------------------------------------------------------------

def long_date(d):
    return "%s %d, %d" % (MONTHS[d.month - 1], d.day, d.year)


def json_ld(graph):
    if not graph:
        return ""
    data = json.dumps({"@context": "https://schema.org", "@graph": graph}, ensure_ascii=False, indent=1)
    return '<script type="application/ld+json">\n%s\n</script>\n' % data.replace("</", "<\\/")


def breadcrumbs(*crumbs):
    return {"@type": "BreadcrumbList", "itemListElement": [
        {"@type": "ListItem", "position": n + 1, "name": name, "item": url}
        for n, (name, url) in enumerate(crumbs)]}


def head(title, description, url, kind, extra="", graph=None):
    return """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%(title)s</title>
<meta name="description" content="%(desc)s">
<link rel="canonical" href="%(url)s">
<link rel="alternate" type="application/rss+xml" title="Sable Markdown Writer blog" href="/blog/feed.xml">
<meta name="color-scheme" content="light dark">
<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#242424">
<meta name="theme-color" media="(prefers-color-scheme: light)" content="#FAFAF8">
<meta name="robots" content="index,follow,max-image-preview:large">
<meta property="og:type" content="%(kind)s">
<meta property="og:site_name" content="Sable Markdown Writer">
<meta property="og:url" content="%(url)s">
<meta property="og:title" content="%(title)s">
<meta property="og:description" content="%(desc)s">
<meta property="og:image" content="%(site)s/og.jpg">
<meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">
<meta property="og:image:alt" content="%(alt)s">
%(extra)s<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="%(title)s">
<meta name="twitter:description" content="%(desc)s">
<meta name="twitter:image" content="%(site)s/og.jpg">
<meta name="twitter:image:alt" content="%(alt)s">
<link rel="icon" href="/favicon.ico" sizes="any"><link rel="icon" type="image/png" href="/icon-32.png" sizes="32x32"><link rel="apple-touch-icon" href="/icon-180.png">
<link rel="stylesheet" href="/site.css?v=%(css)s">
%(ld)s</head>
""" % {"title": attr(title), "desc": attr(description), "url": url, "kind": kind,
       "site": SITE, "extra": extra, "css": CSS_VERSION, "alt": attr(OG_ALT), "ld": json_ld(graph)}


HEADER = """<body>
<a class="skip" href="#main">Skip to content</a>
<header class="site"><div class="bar">
  <a class="brand" href="/"><img src="/icon-64.png" alt="" width="32" height="32"><span>Sable Markdown Writer</span></a>
  <nav aria-label="Main"><a href="/guide">Guide</a><a href="/blog" aria-current="page">Blog</a><a href="/#download">Download</a></nav>
</div></header>
"""

FOOTER = """
<footer class="site"><div class="bar"><span>Sable Markdown Writer — free and open source (MIT).</span><nav aria-label="Footer"><a href="/guide">Guide</a><a href="/blog">Blog</a><a href="/privacy">Privacy</a><a href="https://github.com/ExxtraV/Sable">GitHub</a><a href="https://buymeacoffee.com/sablewriter">Support Sable</a><a href="https://github.com/ExxtraV/Sable/releases">Releases</a><a href="https://github.com/ExxtraV/Sable/issues">Report a bug</a></nav></div></footer>
</body>
</html>
"""


def post_page(post):
    title_tag = post["title"] if "Sable" in post["title"] else post["title"] + " — Sable blog"
    extra = ('<meta property="article:published_time" content="%s">\n'
             '<meta property="article:modified_time" content="%s">\n'
             % (post["date"].isoformat(), post["modified"].isoformat()))
    graph = [
        breadcrumbs(("Sable Markdown Writer", SITE + "/"), ("Blog", SITE + "/blog"), (post["title"], post["url"])),
        {"@type": "BlogPosting", "@id": post["url"] + "#post", "headline": post["title"],
         "description": post["description"], "url": post["url"], "mainEntityOfPage": post["url"],
         "datePublished": post["date"].isoformat(), "dateModified": post["modified"].isoformat(),
         "inLanguage": "en", "wordCount": len(plain_text(post["body_html"]).split()),
         "image": SITE + "/og.jpg", "author": {"@id": SITE + "/#org"}, "publisher": {"@id": SITE + "/#org"},
         "isPartOf": {"@id": SITE + "/blog#blog"}},
        ORGANIZATION,
    ]
    return (head(title_tag, post["description"], post["url"], "article", extra, graph) + HEADER + """
<main id="main">
<article class="post article column">
  <p class="crumbs"><a href="/blog">← All posts</a></p>
  <header class="post-head">
    <h1>%(title)s</h1>
    <p class="post-meta"><time datetime="%(iso)s">%(date)s</time></p>
  </header>
  <div class="post-body">
%(body)s
  </div>
</article>
</main>
""" % {"title": post["title_html"], "iso": post["date"].isoformat(), "date": long_date(post["date"]),
       "body": post["body_html"]} + FOOTER)


def index_page(posts):
    items = []
    for p in posts:
        items.append("""    <article class="post-card">
      <h2><a href="/blog/%(slug)s">%(title)s</a></h2>
      <p class="post-meta"><time datetime="%(iso)s">%(date)s</time></p>
      <p class="post-summary">%(summary)s</p>
    </article>""" % {"slug": p["slug"], "title": p["title_html"], "iso": p["date"].isoformat(),
                     "date": long_date(p["date"]), "summary": p["summary_html"]})
    graph = [
        breadcrumbs(("Sable Markdown Writer", SITE + "/"), ("Blog", SITE + "/blog")),
        {"@type": "Blog", "@id": SITE + "/blog#blog", "name": "Sable Markdown Writer blog",
         "url": SITE + "/blog", "description": BLOG_DESCRIPTION, "inLanguage": "en",
         "publisher": {"@id": SITE + "/#org"},
         "blogPost": [{"@id": p["url"] + "#post"} for p in posts]},
        ORGANIZATION,
    ]
    return (head("Blog — Sable Markdown Writer", BLOG_DESCRIPTION, SITE + "/blog", "website", "", graph) + HEADER + """
<main id="main">
<section class="blog-index article column">
  <h1>Blog</h1>
  <div class="post-list">
%s
  </div>
</section>
</main>
""" % "\n".join(items) + FOOTER)


def rfc822(d):
    return datetime.datetime(d.year, d.month, d.day, 12, tzinfo=datetime.timezone.utc).strftime(
        "%a, %d %b %Y %H:%M:%S GMT")


def feed(posts):
    items = []
    for p in posts:
        content = p["body_html"].replace('src="/blog/', 'src="%s/blog/' % SITE)
        items.append("""    <item>
      <title>%(title)s</title>
      <link>%(url)s</link>
      <guid isPermaLink="true">%(url)s</guid>
      <pubDate>%(pub)s</pubDate>
      <description>%(summary)s</description>
      <content:encoded><![CDATA[%(content)s]]></content:encoded>
    </item>""" % {"title": esc(p["title"]), "url": p["url"], "pub": rfc822(p["date"]),
                  "summary": esc(p["summary"]), "content": content.replace("]]>", "]]]]><![CDATA[>")})
    latest = max(p["modified"] for p in posts)
    return """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Sable Markdown Writer blog</title>
    <link>%(site)s/blog</link>
    <description>%(desc)s</description>
    <language>en</language>
    <lastBuildDate>%(built)s</lastBuildDate>
    <atom:link href="%(site)s/blog/feed.xml" rel="self" type="application/rss+xml"/>
%(items)s
  </channel>
</rss>
""" % {"site": SITE, "desc": esc(BLOG_DESCRIPTION), "built": rfc822(latest), "items": "\n".join(items)}


def sitemap_block(posts):
    latest = max(p["modified"] for p in posts)
    rows = ["  <url><loc>%s/blog</loc><lastmod>%s</lastmod></url>" % (SITE, latest.isoformat())]
    for p in posts:
        rows.append("  <url><loc>%s</loc><lastmod>%s</lastmod></url>" % (p["url"], p["modified"].isoformat()))
    return "  <!-- blog:start -->\n%s\n  <!-- blog:end -->" % "\n".join(rows)


def home_list(posts):
    rows = "\n".join('    <li><a href="/blog/%s">%s</a><time datetime="%s">%s</time></li>'
                     % (p["slug"], p["title_html"], p["date"].isoformat(), long_date(p["date"]))
                     for p in posts[:HOME_POSTS])
    return """<!-- blog-list:start -->
  <section class="part column" id="blog" aria-labelledby="from-blog-h">
    <h2 id="from-blog-h">From the blog</h2>
    <ul class="posts">
%s
    </ul>
    <p class="quiet" style="margin-top:18px"><a href="/blog">All posts</a></p>
  </section>
  <!-- blog-list:end -->""" % rows


def updated_home(posts):
    text = HOME.read_text(encoding="utf-8")
    if "<!-- blog-list:start -->" not in text:
        raise BuildError("website/index.html has no blog-list markers.")
    return re.sub(r"<!-- blog-list:start -->.*?<!-- blog-list:end -->", lambda _: home_list(posts), text, flags=re.S)


def updated_sitemap(posts):
    text = SITEMAP.read_text(encoding="utf-8")
    block = sitemap_block(posts)
    newest = max(p["modified"] for p in posts).isoformat()
    text = re.sub(r"(<loc>%s/</loc><lastmod>)([\d-]+)(</lastmod>)" % re.escape(SITE),
                  lambda m: m.group(1) + max(m.group(2), newest) + m.group(3), text)
    if "<!-- blog:start -->" in text:
        return re.sub(r"  <!-- blog:start -->.*?<!-- blog:end -->", lambda _: block, text, flags=re.S)
    return text.replace("</urlset>", block + "\n</urlset>")


# --- Output -------------------------------------------------------------------

def outputs():
    """Everything this script owns, as {path: bytes}."""
    posts, images = load_posts()
    files = {OUT / "index.html": index_page(posts).encode(), OUT / "feed.xml": feed(posts).encode(),
             SITEMAP: updated_sitemap(posts).encode(), HOME: updated_home(posts).encode()}
    for p in posts:
        files[OUT / (p["slug"] + ".html")] = post_page(p).encode()
    for name, source in images.items():
        files[OUT / name] = source.read_bytes()
    return files, posts


def stale_pages(posts):
    keep = {p["slug"] + ".html" for p in posts} | {"index.html"}
    return [f for f in OUT.glob("*.html") if f.name not in keep]


def main(argv):
    check = "--check" in argv
    try:
        files, posts = outputs()
    except BuildError as error:
        print("Blog build stopped: %s" % error, file=sys.stderr)
        return 1
    problems = []
    for path, data in files.items():
        if not path.exists() or path.read_bytes() != data:
            problems.append(path.relative_to(ROOT))
    for path in stale_pages(posts):
        problems.append(path.relative_to(ROOT))
    if check:
        for p in problems:
            print("Out of date: %s" % p, file=sys.stderr)
        if problems:
            print("Run: python3 scripts/build-blog.py", file=sys.stderr)
        return 1 if problems else 0
    OUT.mkdir(parents=True, exist_ok=True)
    for path in stale_pages(posts):
        path.unlink()
    for path, data in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    print("Built %d post%s; wrote %d files." % (len(posts), "" if len(posts) == 1 else "s", len(files)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
