#!/usr/bin/env python3
"""Confirms every blog post page says exactly what its Markdown source says.

For each post in docs/blog/posts.json this strips the HTML from
website/blog/<slug>.html and compares its words, in order, with
docs/blog/<slug>.md. It also compares the links and images, confirms the blog
index shows the post's first paragraph, and that the feed and sitemap list the
post. Finally it runs build-blog.py --check, so the committed pages can't fall
behind the Markdown.

The Markdown side deliberately doesn't share code with build-blog.py: if the
converter ever changed a word, this check would still see the original.
Standard library only.
"""
import html
import json
import re
import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "blog"
SITE_DIR = ROOT / "website"
BLOCK_TAGS = {"p", "li", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote",
              "br", "pre", "hr", "div", "figure", "figcaption", "header", "article", "time"}

failures = []


def fail(message):
    failures.append(message)
    print("FAIL: " + message)


class Words(HTMLParser):
    """Collects the visible text, the links and the images inside chosen containers."""

    def __init__(self, want):
        super().__init__(convert_charrefs=True)
        self.want = want  # a function(tag, attrs) -> True when a container starts
        self.depth = 0
        self.stack = []
        self.text = []
        self.links = []
        self.images = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if self.depth == 0 and self.want(tag, attrs):
            self.depth = 1
            self.stack = [tag]
            return
        if self.depth:
            if tag in BLOCK_TAGS:
                self.text.append(" ")
            if tag == "a" and "href" in attrs:
                self.links.append(attrs["href"])
            if tag == "img":
                self.images.append((attrs.get("alt", ""), Path(attrs.get("src", "")).name))
            if tag not in ("br", "img", "hr", "meta", "link"):
                self.stack.append(tag)
                self.depth += 1

    def handle_endtag(self, tag):
        if self.depth:
            if tag in BLOCK_TAGS:
                self.text.append(" ")
            self.depth -= 1
            if self.stack:
                self.stack.pop()

    def handle_data(self, data):
        if self.depth:
            self.text.append(data)

    def words(self):
        return "".join(self.text).split()


def markdown_words(text):
    """Words, links and images of a Markdown file, using plain regex rules."""
    images = re.findall(r"!\[([^\]]*)\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)", text)
    text = re.sub(r"!\[[^\]]*\]\([^)]*\)", " ", text)
    links = re.findall(r"\[[^\]]+\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)
    autolinks = re.findall(r"<(https?://[^>\s]+)>", text)
    text = re.sub(r"<(https?://[^>\s]+)>", r"\1", text)
    bare = [u.rstrip(".,;:!?)\"'") for u in re.findall(r"https?://[^\s<>\"]+", text)]
    lines = []
    in_fence = False
    for line in text.replace("\r\n", "\n").split("\n"):
        if re.match(r"^\s{0,3}(```|~~~)", line):
            in_fence = not in_fence
            continue
        if not in_fence:
            while True:
                stripped = re.sub(r"^\s*(#{1,6}\s+|>\s?|[-*+]\s+|\d{1,9}[.)]\s+)", "", line)
                if stripped == line:
                    break
                line = stripped
            line = re.sub(r"[ \t]+#+[ \t]*$", "", line)
            if re.match(r"^\s*([-*_])( *\1){2,}\s*$", line):
                continue
        lines.append(line)
    text = "\n".join(lines)
    text = re.sub(r"`+", "", text)
    text = re.sub(r"(\*\*|__)(?=\S)(.+?)(?<=\S)\1", r"\2", text, flags=re.S)
    text = re.sub(r"\*(?=\S)(.+?)(?<=\S)\*", r"\1", text, flags=re.S)
    text = re.sub(r"(?<!\w)_(?=\S)(.+?)(?<=\S)_(?!\w)", r"\1", text, flags=re.S)
    text = re.sub(r"\\([\\`*_{}\[\]()#+\-.!>])", r"\1", text)
    return text.split(), sorted(links + autolinks + bare), sorted(images)


def check_post(entry):
    slug = entry["slug"]
    source = SRC / (slug + ".md")
    page = SITE_DIR / "blog" / (slug + ".html")
    if not source.is_file():
        return fail("docs/blog/%s.md is missing." % slug)
    if not page.is_file():
        return fail("website/blog/%s.html is missing." % slug)
    expected_words, expected_links, expected_images = markdown_words(source.read_text(encoding="utf-8"))
    markup = page.read_text(encoding="utf-8")

    # The title and the body; the date line and navigation aren't the author's words.
    body = Words(lambda tag, a: tag == "div" and a.get("class") == "post-body")
    body.feed(markup)
    title = Words(lambda tag, a: tag == "h1")
    title.feed(markup)
    actual_words = title.words() + body.words()
    if markup.count("<h1") != 1:
        fail("%s should have exactly one h1." % slug)
    if actual_words != expected_words:
        for n, (a, b) in enumerate(zip(actual_words, expected_words)):
            if a != b:
                fail("%s: word %d differs. Page has %r, Markdown has %r." % (slug, n + 1, a, b))
                break
        else:
            fail("%s: page has %d words, Markdown has %d." % (slug, len(actual_words), len(expected_words)))
    if sorted(body.links) != expected_links:
        fail("%s: the page's links %r don't match the Markdown's %r." % (slug, sorted(body.links), expected_links))
    if sorted(body.images) != [(alt.strip(), Path(src).name) for alt, src in expected_images]:
        fail("%s: the page's images or alt text don't match the Markdown." % slug)
    for _, src in expected_images:
        if not (SITE_DIR / "blog" / Path(src).name).is_file():
            fail("%s: image %s wasn't copied into website/blog/." % (slug, Path(src).name))

    # The index shows the first paragraph as the summary.
    first_paragraph = re.search(r"<p>(.*?)</p>", markup[markup.index('<div class="post-body">'):], re.S)
    index = (SITE_DIR / "blog" / "index.html").read_text(encoding="utf-8")
    card = re.search(r'href="/blog/%s".*?<p class="post-summary">(.*?)</p>' % re.escape(slug), index, re.S)
    if not card or not first_paragraph:
        fail("%s: the blog index has no summary for it." % slug)
    elif html.unescape(re.sub(r"<[^>]+>", "", card.group(1))).split() != \
            html.unescape(re.sub(r"<[^>]+>", "", first_paragraph.group(1))).split():
        fail("%s: the blog index summary isn't the post's first paragraph." % slug)

    url = "https://sablewriter.app/blog/" + slug
    if url not in (SITE_DIR / "blog" / "feed.xml").read_text(encoding="utf-8"):
        fail("%s isn't in the RSS feed." % slug)
    if "<loc>%s</loc>" % url not in (SITE_DIR / "sitemap.xml").read_text(encoding="utf-8"):
        fail("%s isn't in sitemap.xml." % slug)
    print("ok: %s (%d words)" % (slug, len(expected_words)))


def main():
    posts = json.loads((SRC / "posts.json").read_text(encoding="utf-8"))
    if not posts:
        fail("docs/blog/posts.json lists no posts.")
    for entry in posts:
        check_post(entry)
    listed = {e["slug"] + ".md" for e in posts}
    for stray in sorted(SRC.glob("*.md")):
        if stray.name not in listed:
            fail("docs/blog/%s isn't listed in posts.json, so it isn't published." % stray.name)
    built = subprocess.run([sys.executable, str(ROOT / "scripts" / "build-blog.py"), "--check"],
                           capture_output=True, text=True)
    if built.returncode != 0:
        fail("The blog pages are out of date with the Markdown.\n" + built.stderr.strip())
    if failures:
        print("\n%d problem%s." % (len(failures), "" if len(failures) == 1 else "s"))
        return 1
    print("Blog checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
