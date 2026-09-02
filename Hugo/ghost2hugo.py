#!/usr/bin/env python3
"""
ghost2hugo.py -- convert a Ghost 5.x/6.x admin JSON export into Hugo markdown.

Works off the export's rendered `html` column, so it is agnostic to whether the
post body is stored as mobiledoc (Ghost <=5.5x) or lexical (Ghost 5.60+/6.x).

Pipeline per post:
    export JSON -> normalise Koenig cards in HTML (BeautifulSoup)
                -> pandoc -f html -t gfm --wrap=none
                -> re-inject shortcodes, rewrite URLs
                -> YAML front matter + body

Requires: python3, beautifulsoup4, lxml, PyYAML, pandoc (>=2.11).

Usage:
    python3 ghost2hugo.py ghost-export.json --out ./site \
        --site-url https://blog.example.com

    # then fetch the images the posts actually reference:
    python3 ghost2hugo.py ghost-export.json --out ./site \
        --site-url https://blog.example.com --download-images
"""

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

from bs4 import BeautifulSoup, Comment, NavigableString

try:
    import yaml
except ImportError:
    sys.exit("pip install pyyaml beautifulsoup4 lxml")

TOKEN = "@@G2H{}@@"          # placeholder pandoc will carry through untouched
TOKEN_RE = re.compile(r"@@G2H(\d+)@@")

# Ghost's responsive-image URL segments we strip to get back to the original.
SIZE_RE = re.compile(r"/content/images/size/w\d+(?:h\d+)?/")
FORMAT_RE = re.compile(r"/content/images/format/[a-z0-9]+/")
SIZE_FORMAT_RE = re.compile(r"/content/images/size/w\d+(?:h\d+)?/format/[a-z0-9]+/")


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

def original_image_url(url: str) -> str:
    """Strip Ghost's /size/wNNN/ and /format/xxx/ segments -> original file."""
    if not url:
        return url
    url = SIZE_FORMAT_RE.sub("/content/images/", url)
    url = SIZE_RE.sub("/content/images/", url)
    url = FORMAT_RE.sub("/content/images/", url)
    return url


def rewrite_url(url: str, site_url: str) -> str:
    """__GHOST_URL__/x and https://site/x -> /x ; also de-size image URLs."""
    if not url:
        return url
    u = url.strip()
    u = u.replace("__GHOST_URL__/", "/").replace("__GHOST_URL__", "/")
    if site_url:
        for base in {site_url.rstrip("/"), site_url.rstrip("/").replace("https://", "http://")}:
            if u.startswith(base + "/"):
                u = u[len(base):]
            elif u == base:
                u = "/"
    u = original_image_url(u)
    u = re.sub(r"^//+", "/", u)
    return u


def clean_text(node) -> str:
    """Inline HTML of a node with Ghost's <span style=white-space> noise removed."""
    if node is None:
        return ""
    for span in node.find_all("span", style=True):
        span.unwrap()
    return "".join(str(c) for c in node.contents).strip()


def to_md_inline(html: str) -> str:
    """Convert a small inline HTML fragment to markdown (for captions)."""
    html = (html or "").strip()
    if not html:
        return ""
    flav = ENGINE["flavour"] + ("-raw_html" if ENGINE["flavour"].startswith(("gfm", "commonmark")) else "")
    out = pandoc(html, extra=["-t", flav, "--wrap=none"]).strip()
    return " ".join(out.split())


ENGINE = {"name": "pandoc", "flavour": "gfm"}


def _markdownify(html: str, raw_html=True) -> str:
    """pandoc-free fallback. NOTE the code_language_callback must look at the
    <code> child -- markdownify passes it the <pre>, whose class is empty in
    Ghost output, so the naive callback silently drops every language tag."""
    from markdownify import markdownify as _md

    def lang(el):
        cands = list(el.get("class") or [])
        c = el.find("code")
        if c:
            cands += list(c.get("class") or [])
        for x in cands:
            if x.startswith("language-"):
                return x[len("language-"):]
        return ""

    return _md(html, code_language_callback=lang, heading_style="ATX",
               bullets="-", strip=None if raw_html else ["figure", "div"])


def pandoc(html: str, extra=None) -> str:
    """html -> markdown. Named `pandoc` for history; dispatches on ENGINE."""
    if ENGINE["name"] == "markdownify":
        return _markdownify(html)
    cmd = ["pandoc", "-f", "html"] + (extra or ["-t", ENGINE["flavour"], "--wrap=none"])
    p = subprocess.run(cmd, input=html, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError("pandoc failed: " + p.stderr[:2000])
    return p.stdout


FENCE_RE = re.compile(r"^(?P<fence>`{3,}|~{3,}).*$", re.M)


def outside_fences(md: str, fn):
    """Apply fn() to the parts of `md` that are NOT inside a fenced code block.

    The naive alternative -- running str.replace/re.sub over the whole document --
    silently corrupts tutorials that quote their own site URL inside a code sample
    (e.g. `curl https://www.example.com/feed`), which is exactly the kind of thing
    a technical blog does. Verified against a real export: every occurrence of the
    site URL lived inside <pre>.
    """
    out, pos, fence = [], 0, None
    for m in FENCE_RE.finditer(md):
        marker = m.group("fence")
        if fence is None:
            # opening fence: everything before it is prose, transform it
            out.append(fn(md[pos:m.start()]))
            out.append(md[m.start():m.end()])
            fence = marker[0] * 3
        elif m.group(0).strip() == m.group("fence") and marker.startswith(fence):
            # closing fence: copy the code block through untouched
            out.append(md[pos:m.end()])
            fence = None
        else:
            continue
        pos = m.end()
    tail = md[pos:]
    out.append(tail if fence is not None else fn(tail))
    return "".join(out)


def shortcode_attrs(**kw) -> str:
    parts = []
    for k, v in kw.items():
        if v:
            parts.append('{}="{}"'.format(k, str(v).replace('"', "&quot;")))
    return " ".join(parts)


def parse_ts(v):
    if not v:
        return None
    if isinstance(v, (int, float)):          # some exports use epoch ms
        return datetime.fromtimestamp(v / 1000, tz=timezone.utc)
    s = str(v).strip().replace("Z", "+00:00")
    s = re.sub(r"(\.\d{3})\d+", r"\1", s)
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        try:
            dt = datetime.strptime(str(v), "%Y-%m-%d %H:%M:%S")
        except ValueError:
            return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def iso(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S%z").replace("+0000", "+00:00") if dt else None


# --------------------------------------------------------------------------
# Koenig card normalisation
# --------------------------------------------------------------------------

class CardNormaliser:
    """Rewrites Ghost/Koenig HTML into something pandoc converts cleanly.

    Cards that have no markdown equivalent are replaced with an @@G2Hn@@ token
    and the intended markdown/shortcode is substituted back after pandoc runs.
    """

    def __init__(self, site_url, use_shortcodes=True):
        self.site_url = site_url
        self.use_shortcodes = use_shortcodes
        self.subs = []
        self.notes = defaultdict(int)
        self.images = set()

    def _token(self, replacement):
        tok = TOKEN.format(len(self.subs))
        self.subs.append(replacement)
        return tok

    def _replace_with_token(self, el, replacement):
        p = el.find_parent()
        tok = self._token(replacement)
        # a bare paragraph keeps the token on its own block, which pandoc
        # emits as its own paragraph -> the shortcode ends up block-level.
        new = BeautifulSoup("<p>{}</p>".format(tok), "lxml").p
        el.replace_with(new)
        return new

    def _img_src(self, img):
        src = rewrite_url(img.get("src", ""), self.site_url)
        if "/content/images/" in src:
            self.images.add(src)
        return src

    # -- individual cards ---------------------------------------------------

    def _image_card(self, fig):
        img = fig.find("img")
        if not img:
            fig.decompose()
            return
        src = self._img_src(img)
        alt = img.get("alt", "") or ""
        cap_el = fig.find("figcaption")
        caption = to_md_inline(clean_text(cap_el)) if cap_el else ""
        link = fig.find("a", href=True)
        if caption or link or self.use_shortcodes:
            attrs = shortcode_attrs(src=src, alt=alt, caption=caption,
                                    link=(rewrite_url(link["href"], self.site_url) if link else ""))
            self._replace_with_token(fig, "{{< figure " + attrs + " >}}")
            self.notes["image_card_figure_shortcode"] += 1
        else:
            self._replace_with_token(fig, "![{}]({})".format(alt, src))
            self.notes["image_card_plain"] += 1

    def _gallery_card(self, fig):
        imgs = fig.find_all("img")
        lines = []
        for img in imgs:
            src = self._img_src(img)
            lines.append("{{< figure " + shortcode_attrs(src=src, alt=img.get("alt", "")) + " >}}")
        cap_el = fig.find("figcaption")
        if cap_el:
            lines.append("*" + to_md_inline(clean_text(cap_el)) + "*")
        self._replace_with_token(fig, "\n\n".join(lines))
        self.notes["gallery_card"] += 1

    def _bookmark_card(self, fig):
        a = fig.find("a", href=True)
        href = rewrite_url(a["href"], self.site_url) if a else ""
        title = fig.find(class_="kg-bookmark-title")
        desc = fig.find(class_="kg-bookmark-description")
        title = to_md_inline(clean_text(title)) if title else href
        desc = to_md_inline(clean_text(desc)) if desc else ""
        md = "> [**{}**]({})".format(title, href)
        if desc:
            md += "  \n> {}".format(desc)
        self._replace_with_token(fig, md)
        self.notes["bookmark_card"] += 1

    def _callout_card(self, div):
        emoji_el = div.find(class_="kg-callout-emoji")
        text_el = div.find(class_="kg-callout-text")
        emoji = emoji_el.get_text(strip=True) if emoji_el else ""
        body = to_md_inline(clean_text(text_el)) if text_el else ""
        md = "> {}{}".format(emoji + " " if emoji else "", body)
        self._replace_with_token(div, md)
        self.notes["callout_card"] += 1

    def _code_card(self, fig):
        """<figure class=kg-code-card><pre>..</pre><figcaption>..</figcaption>"""
        pre = fig.find("pre")
        cap_el = fig.find("figcaption")
        caption = to_md_inline(clean_text(cap_el)) if cap_el else ""
        if pre is None:
            fig.decompose()
            return
        pre = pre.extract()
        fig.replace_with(pre)
        if caption:
            new = BeautifulSoup("<p>{}</p>".format(self._token("*" + caption + "*")), "lxml").p
            pre.insert_after(new)
        self.notes["code_card_with_caption"] += 1 if caption else 0

    def _embed_card(self, fig):
        iframe = fig.find("iframe")
        if iframe and iframe.get("src"):
            src = iframe["src"]
            m = re.search(r"(?:youtube\.com/embed/|youtu\.be/)([\w-]{6,})", src)
            if m:
                self._replace_with_token(fig, '{{< youtube "%s" >}}' % m.group(1))
                self.notes["embed_youtube"] += 1
                return
            m = re.search(r"player\.vimeo\.com/video/(\d+)", src)
            if m:
                self._replace_with_token(fig, '{{< vimeo "%s" >}}' % m.group(1))
                self.notes["embed_vimeo"] += 1
                return
        # twitter/x, codepen, gist, generic: keep raw HTML, flag it
        self._replace_with_token(fig, "<!-- TODO manual: Ghost embed card -->\n\n" + str(fig))
        self.notes["embed_other_MANUAL"] += 1

    def _toggle_card(self, div):
        head = div.find(class_="kg-toggle-heading-text")
        content = div.find(class_="kg-toggle-content")
        h = clean_text(head) if head else "Details"
        body = to_md_inline(clean_text(content)) if content else ""
        self._replace_with_token(
            div, "<details>\n<summary>{}</summary>\n\n{}\n\n</details>".format(h, body))
        self.notes["toggle_card_details_html"] += 1

    def _button_card(self, div):
        a = div.find("a", href=True)
        if a:
            self._replace_with_token(
                div, "[{}]({})".format(a.get_text(strip=True),
                                       rewrite_url(a["href"], self.site_url)))
            self.notes["button_card"] += 1
        else:
            div.decompose()

    def _header_card(self, div):
        h = div.find(class_="kg-header-card-header") or div.find(["h2", "h3"])
        sub = div.find(class_="kg-header-card-subheader")
        parts = []
        if h:
            parts.append("## " + h.get_text(strip=True))
        if sub:
            parts.append(sub.get_text(strip=True))
        self._replace_with_token(div, "\n\n".join(parts))
        self.notes["header_card"] += 1

    def _html_card(self, div):
        inner = "".join(str(c) for c in div.contents).strip()
        self._replace_with_token(
            div, "<!-- TODO manual: Ghost HTML card, verify rendering -->\n\n" + inner)
        self.notes["html_card_MANUAL"] += 1

    # -- driver -------------------------------------------------------------

    def run(self, html: str) -> str:
        soup = BeautifulSoup(html, "lxml")

        # Ghost wraps raw-HTML regions in <!--kg-card-begin: html--> /
        # <!--kg-card-end: html--> comments. pandoc does not carry HTML comments
        # through to gfm -- it renders their text -- so these surface as literal
        # visible paragraphs reading "kg-card-begin: html" above and below every
        # affected table. Strip them before pandoc ever sees them.
        for c in soup.find_all(string=lambda t: isinstance(t, Comment)):
            if re.match(r"\s*kg-card-(begin|end)\b", str(c)):
                c.extract()
                self.notes["kg_card_comment_stripped"] += 1

        handlers = [
            ("kg-image-card", self._image_card),
            ("kg-gallery-card", self._gallery_card),
            ("kg-bookmark-card", self._bookmark_card),
            ("kg-callout-card", self._callout_card),
            ("kg-code-card", self._code_card),
            ("kg-embed-card", self._embed_card),
            ("kg-toggle-card", self._toggle_card),
            ("kg-button-card", self._button_card),
            ("kg-header-card", self._header_card),
            ("kg-html-card", self._html_card),
        ]
        for cls, fn in handlers:
            for el in soup.select("." + cls):
                if el.decomposed or el.find_parent(class_=re.compile("kg-.*-card")):
                    continue
                fn(el)

        # cards we don't model: leave them but flag for manual review
        for el in soup.select("[class*=kg-]"):
            if el.decomposed:
                continue
            classes = " ".join(el.get("class") or [])
            m = re.search(r"kg-([a-z-]+)-card", classes)
            if m and el.name in ("figure", "div"):
                self.notes["UNHANDLED_kg-{}-card_MANUAL".format(m.group(1))] += 1
                el.insert_before(BeautifulSoup(
                    "<p>{}</p>".format(self._token(
                        "<!-- TODO manual: unhandled Ghost card kg-{}-card -->".format(m.group(1)))),
                    "lxml").p)

        # code blocks with no language -> force a fenced block (pandoc would
        # otherwise emit a 4-space indented block and lose the fence)
        for code in soup.find_all("code"):
            if code.parent and code.parent.name == "pre" and not code.get("class"):
                code["class"] = ["language-text"]
                self.notes["code_block_no_language"] += 1

        # plain <img> outside cards + link/src rewriting
        for img in soup.find_all("img"):
            for attr in ("srcset", "sizes", "loading", "width", "height", "decoding"):
                img.attrs.pop(attr, None)
            img["src"] = self._img_src(img)
        for a in soup.find_all("a", href=True):
            a["href"] = rewrite_url(a["href"], self.site_url)

        body = soup.body or soup
        return "".join(str(c) for c in body.contents)

    def restore(self, md: str) -> str:
        def sub(m):
            return self.subs[int(m.group(1))]
        # pandoc may escape nothing in the token, but be defensive
        md = md.replace("\\@\\@", "@@").replace("@@G2H", "@@G2H")
        return TOKEN_RE.sub(sub, md)


# --------------------------------------------------------------------------
# front matter
# --------------------------------------------------------------------------

def load_ghost_redirects(path):
    """Ghost redirects.yaml -> {destination_path: [source_path, ...]}.

    Ghost schema:  {301: {"/from": "/to", ...}, 302: {...}}
    Only 301s are folded into Hugo aliases (aliases are always 'permanent'
    in intent); 302s and any regex sources are returned separately.
    """
    with open(path, encoding="utf-8") as f:
        doc = yaml.safe_load(f) or {}
    by_dest, leftovers = defaultdict(list), []
    for code in (301, "301"):
        for frm, to in (doc.get(code) or {}).items():
            frm, to = str(frm), str(to)
            if any(ch in frm for ch in "^$()*+?[]\\|"):        # Ghost regex source
                leftovers.append((frm, to, 301, "regex source"))
                continue
            # An external destination cannot become a Hugo alias: aliases are
            # meta-refresh pages generated ON a page of your own site, so there is
            # no page to hang them off. Previously these were filed under a
            # by_dest key that could never match a slug and vanished without a
            # word -- and a redirects.yaml can easily be ENTIRELY external.
            if re.match(r"^[a-z][a-z0-9+.-]*://", to, re.I):
                leftovers.append((frm, to, 301, "external destination"))
                continue
            by_dest[to.rstrip("/") + "/"].append(frm)
    for code in (302, "302"):
        for frm, to in (doc.get(code) or {}).items():
            leftovers.append((str(frm), str(to), 302, "302 is not an alias"))
    return by_dest, leftovers


def build_front_matter(post, meta, tags, authors, site_url, args):
    pub = parse_ts(post.get("published_at")) or parse_ts(post.get("created_at"))
    upd = parse_ts(post.get("updated_at"))
    meta = meta or {}

    excerpt = (post.get("custom_excerpt")
               or post.get("excerpt")
               or meta.get("meta_description"))
    if excerpt:
        excerpt = " ".join(str(excerpt).split())

    fm = {
        "title": post.get("title") or post.get("slug"),
        "slug": post.get("slug"),
        "date": iso(pub),
        "draft": post.get("status") != "published",
    }
    if upd and pub and upd > pub:
        fm["lastmod"] = iso(upd)
    if excerpt:
        fm["summary"] = excerpt
        fm["description"] = meta.get("meta_description") or excerpt
    elif meta.get("meta_description"):
        fm["description"] = meta["meta_description"]

    if post.get("feature_image"):
        img = rewrite_url(post["feature_image"], site_url)
        alt = meta.get("feature_image_alt")
        cap = meta.get("feature_image_caption")
        if args.image_key == "cover":
            # PaperMod reads .Params.cover.image -- a nested map, not a scalar.
            # Writing a flat `featured_image:` key leaves the theme blind to it,
            # so every post silently falls back to site.Params.images and every
            # social share renders the same generic card. That is the single
            # highest-cost front-matter mistake in this migration.
            cover = {"image": img, "relative": False}
            if alt:
                cover["alt"] = alt
            if cap:
                cover["caption"] = to_md_inline(cap)
            fm["cover"] = cover
        else:
            fm[args.image_key] = img
            if alt:
                fm["featured_image_alt"] = alt
            if cap:
                fm["featured_image_caption"] = to_md_inline(cap)

    if tags:
        fm["tags"] = tags
    if authors:
        fm["authors"] = authors
    if post.get("featured"):
        fm["featured"] = True
    if post.get("canonical_url"):
        fm["canonicalURL"] = post["canonical_url"]
    if post.get("visibility") and post["visibility"] != "public":
        fm["ghost_visibility"] = post["visibility"]

    # SEO / social -> Hugo's `params` bucket (theme-dependent) + _build hints
    params = {}
    for src, dst in (("meta_title", "meta_title"),
                     ("og_image", "og_image"), ("og_title", "og_title"),
                     ("og_description", "og_description"),
                     ("twitter_image", "twitter_image"),
                     ("twitter_title", "twitter_title"),
                     ("twitter_description", "twitter_description")):
        v = meta.get(src)
        if v:
            params[dst] = rewrite_url(v, site_url) if dst.endswith("_image") else v
    if params:
        fm["params"] = params

    if args.aliases and post.get("slug"):
        old = "/{}/".format(post["slug"])                      # Ghost's URL
        pl = "/{slug}/" if post.get("type") == "page" else args.permalink
        new = pl.replace("{slug}", post["slug"])               # Hugo's URL
        al = [old] if old.rstrip("/") != new.rstrip("/") else []
        for extra in args._redirects.get(old, []) + args._redirects.get(new, []):
            if extra.rstrip("/") + "/" not in [a.rstrip("/") + "/" for a in al] \
               and extra.rstrip("/") != new.rstrip("/"):
                al.append(extra)
        if al:
            fm["aliases"] = al

    fm["ghost_id"] = post.get("id")
    return fm


def dump_front_matter(fm):
    y = yaml.safe_dump(fm, sort_keys=False, allow_unicode=True,
                       default_flow_style=False, width=10**6)
    return "---\n" + y + "---\n\n"


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def load_export(path):
    with open(path, encoding="utf-8") as f:
        raw = json.load(f)
    if isinstance(raw, dict) and "db" in raw:
        node = raw["db"][0]
    else:
        node = raw
    data = node.get("data", node)
    meta = node.get("meta", {})
    return data, meta


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("export")
    ap.add_argument("--out", default="./hugo-out")
    ap.add_argument("--site-url", default="", help="e.g. https://blog.example.com")
    ap.add_argument("--posts-dir", default="content/posts")
    ap.add_argument("--pages-dir", default="content")
    ap.add_argument("--image-key", default="featured_image",
                    help="front matter key for feature_image (cover/image/featured_image)")
    ap.add_argument("--markdown", default="gfm",
                    choices=["gfm", "commonmark_x", "markdown_strict"])
    ap.add_argument("--no-shortcodes", action="store_true",
                    help="emit plain ![](), not {{< figure >}}")
    ap.add_argument("--aliases", action="store_true",
                    help="add aliases: [/slug/]; skipped when it equals --permalink")
    ap.add_argument("--permalink", default="/posts/{slug}/",
                    help="the URL Hugo will actually serve the post at; used only "
                         "to decide whether an alias is needed")
    ap.add_argument("--engine", default="pandoc", choices=["pandoc", "markdownify"],
                    help="html->markdown backend (pandoc strongly preferred)")
    ap.add_argument("--keep-internal-tags", action="store_true",
                    help="keep Ghost internal (#hash) tags")
    ap.add_argument("--redirects", help="Ghost redirects.yaml; 301 sources are "
                                        "folded into each page's aliases")
    ap.add_argument("--download-images", action="store_true")
    ap.add_argument("--images-from-zip", metavar="ZIP",
                    help="extract referenced images from a Ghost support content "
                         "archive instead of downloading them from the live site. "
                         "Strongly preferred: it is offline, exact, and keeps working "
                         "after the subscription is cancelled.")
    ap.add_argument("--static-dir", default="static")
    # NOTE: this was previously `action="store_true", default=True`, i.e. always on
    # and impossible to disable, while the docs presented it as opt-in.
    ap.add_argument("--tidy-fences", action=argparse.BooleanOptionalAction, default=True,
                    help="rewrite '``` lang' to '```lang' (default: on; "
                         "--no-tidy-fences to disable)")
    ap.add_argument("--tag-bundles", action="store_true",
                    help="write content/<plural>/<term>/_index.md with a slug override "
                         "for tags whose Ghost slug differs from what Hugo derives from "
                         "the name, so the existing /tag/<slug>/ URLs keep working")
    ap.add_argument("--taxonomy-plural", default="tags",
                    help="plural taxonomy name from hugo.toml [taxonomies] (default: "
                         "tags). This is the CONTENT directory, not the URL segment.")
    args = ap.parse_args()
    ENGINE["name"] = args.engine
    ENGINE["flavour"] = args.markdown
    args._redirects, leftover_redirects = ({}, [])
    if args.redirects:
        args._redirects, leftover_redirects = load_ghost_redirects(args.redirects)
        print("loaded {} 301 destinations from {}".format(len(args._redirects), args.redirects))

    data, exp_meta = load_export(args.export)
    print("Ghost export version:", exp_meta.get("version", "?"))

    posts = data.get("posts", [])
    metas = {m["post_id"]: m for m in data.get("posts_meta", [])}
    tags_by_id = {t["id"]: t for t in data.get("tags", [])}
    users_by_id = {u["id"]: u for u in data.get("users", [])}

    ptags = defaultdict(list)
    for row in sorted(data.get("posts_tags", []), key=lambda r: (r.get("sort_order") or 0)):
        t = tags_by_id.get(row["tag_id"])
        if not t:
            continue
        internal = (t.get("name") or "").startswith("#") or t.get("visibility") == "internal"
        if internal and not args.keep_internal_tags:
            continue
        ptags[row["post_id"]].append(t["name"])

    pauth = defaultdict(list)
    for row in sorted(data.get("posts_authors", []), key=lambda r: (r.get("sort_order") or 0)):
        u = users_by_id.get(row["author_id"])
        if u:
            pauth[row["post_id"]].append(u.get("name") or u.get("slug"))

    out = Path(args.out)
    all_images, report, missing_html = set(), defaultdict(int), []
    fence_braces, fence_siteurl, fence_badlang = [], [], []
    written = 0

    for post in posts:
        slug = post.get("slug")
        if not slug:
            print("  ! skipping post with no slug:", post.get("title"))
            continue
        html = post.get("html")
        if not html or not html.strip():
            missing_html.append(slug)
            html = "<p></p>"

        norm = CardNormaliser(args.site_url, use_shortcodes=not args.no_shortcodes)
        pre = norm.run(html)
        md = pandoc(pre, extra=["-t", args.markdown, "--wrap=none"])
        md = norm.restore(md)

        # Any URL that slipped through pandoc untouched. Scoped to prose only --
        # rewriting inside fenced blocks would mangle code samples that legitimately
        # quote the site's own URL. __GHOST_URL__ is rewritten everywhere because it
        # is a Ghost-internal sentinel that is never valid content.
        md = md.replace("__GHOST_URL__/", "/").replace("__GHOST_URL__", "/")

        def _derelativise(chunk):
            if args.site_url:
                chunk = chunk.replace(args.site_url.rstrip("/") + "/", "/")
            chunk = SIZE_FORMAT_RE.sub("/content/images/", chunk)
            chunk = SIZE_RE.sub("/content/images/", chunk)
            chunk = FORMAT_RE.sub("/content/images/", chunk)
            return chunk

        md = outside_fences(md, _derelativise)

        # Name the posts whose code blocks will break or degrade the Hugo build, so
        # you get a work list here instead of an unattributed failure at build time.
        blocks = re.findall(r"(?ms)^(?:`{3,}|~{3,}).*?^(?:`{3,}|~{3,})", md)
        if any("{{" in b for b in blocks):
            fence_braces.append(slug)
        if args.site_url and any(args.site_url.rstrip("/") in b for b in blocks):
            fence_siteurl.append(slug)
        for b in blocks:
            lang = b.splitlines()[0].lstrip("`~").strip()
            if lang and not re.fullmatch(r"[A-Za-z0-9_+#.-]+", lang):
                fence_badlang.append("{} -> '{}'".format(slug, lang))

        if args.tidy_fences:
            md = re.sub(r"^(`{3,})\s+([A-Za-z0-9_+.-]+)\s*$", r"\1\2", md, flags=re.M)
        md = re.sub(r"\n{3,}", "\n\n", md).strip() + "\n"

        fm = build_front_matter(post, metas.get(post["id"]), ptags.get(post["id"], []),
                                pauth.get(post["id"], []), args.site_url, args)

        subdir = args.pages_dir if post.get("type") == "page" else args.posts_dir
        path = out / subdir / (slug + ".md")
        path.parent.mkdir(parents=True, exist_ok=True)
        # newline="\n" keeps output LF on Windows, where write_text would otherwise
        # emit CRLF and churn the first git diff.
        path.write_text(dump_front_matter(fm) + md, encoding="utf-8", newline="\n")
        written += 1

        all_images |= norm.images
        for k, v in norm.notes.items():
            report[k] += v
        for key in ("feature_image", "og_image", "twitter_image"):
            v = post.get(key) or (metas.get(post["id"], {}) or {}).get(key)
            if v:
                u = rewrite_url(v, args.site_url)
                if "/content/images/" in u:
                    all_images.add(u)
        print("  wrote", path.relative_to(out))

    # Tag term bundles. Ghost stores a tag's display name and its URL slug
    # independently; Hugo derives the URL from the name. Where they diverge the
    # taxonomy URL silently changes, which is invisible until you diff sitemaps.
    divergent = []
    plural = args.taxonomy_plural
    for t in tags_by_id.values():
        name, gslug = (t.get("name") or ""), (t.get("slug") or "")
        if not name or not gslug or name.startswith("#") or t.get("visibility") == "internal":
            continue
        hugo_slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
        if hugo_slug != gslug:
            divergent.append((name, gslug, hugo_slug))
            if args.tag_bundles:
                # The bundle must live in the TAXONOMY tree, named for the
                # NORMALISED TERM, with `slug` overriding the URL segment:
                #
                #     content/tags/entra-id/_index.md   ->  slug: entra
                #
                # Writing content/tag/<slug>/ instead (the URL path) creates an
                # ordinary section called "tag" whose list page renders at /tag/,
                # colliding with the taxonomy list that permalinks.taxonomy puts
                # there -- "Duplicate target paths: /tag/index.html (2)".
                # Verified against a real build.
                p = out / "content" / plural / hugo_slug / "_index.md"
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(dump_front_matter({"title": name, "slug": gslug}),
                             encoding="utf-8", newline="\n")
                print("  wrote", p.relative_to(out))
    if divergent:
        print("\n!! {} tag(s) whose Ghost URL differs from Hugo's derived URL:"
              .format(len(divergent)))
        for name, gslug, hslug in divergent:
            print("   '{}'  /tag/{}/  ->  /tag/{}/".format(name, gslug, hslug))
        if args.tag_bundles:
            print("   (term bundles written -- VERIFY on a real build)")
        else:
            print("   Either re-run with --tag-bundles, or add a 301 per line above "
                  "at the host.")

    # Site-level images live in the `settings` table, not in any post, so walking
    # posts alone silently misses the logo, favicon and site-wide OG card. Those
    # are exactly the assets you need to rebuild the theme.
    site_images = {}
    for row in data.get("settings", []):
        key, val = row.get("key"), row.get("value")
        if key in ("logo", "icon", "og_image", "twitter_image", "cover_image") and val:
            u = rewrite_url(str(val), args.site_url)
            if "/content/images/" in u:
                site_images[key] = u
                all_images.add(u)
    if site_images:
        print("\n-- site-level images (from settings, not from any post) --")
        for k, v in sorted(site_images.items()):
            print("   {:<16} {}".format(k, v))
        if "og_image" in site_images:
            print("   ^ og_image is your ready-made og-default.png; see runbook 3.6")

    # image manifest
    manifest = out / "images.txt"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text("\n".join(sorted(all_images)) + "\n",
                        encoding="utf-8", newline="\n")

    if args.images_from_zip:
        import zipfile
        want = {r.lstrip("/") for r in all_images}
        got, missing, total = set(), [], 0
        with zipfile.ZipFile(args.images_from_zip) as zf:
            # A Ghost support archive can legitimately contain duplicate entry
            # names (two backup snapshots concatenated). Index by name and keep
            # the largest -- a truncated snapshot must never win.
            best = {}
            for info in zf.infolist():
                if info.is_dir():
                    continue
                if info.filename in want and \
                   info.file_size > best.get(info.filename, (None, -1))[1]:
                    best[info.filename] = (info, info.file_size)
            for rel in sorted(want):
                if rel not in best:
                    missing.append("/" + rel)
                    continue
                info = best[rel][0]
                dest = out / args.static_dir / rel
                dest.parent.mkdir(parents=True, exist_ok=True)
                with zf.open(info) as src, open(dest, "wb") as fh:
                    fh.write(src.read())
                got.add(rel)
                total += info.file_size
        print("\n-- images from archive --")
        print("   extracted {} file(s), {:.1f} MB -> {}"
              .format(len(got), total / 1048576.0, out / args.static_dir))
        if missing:
            print("   !! {} referenced image(s) NOT in the archive:".format(len(missing)))
            for rel in missing:
                print("     ", rel)
        else:
            print("   every referenced image was found -- no live-site fetch needed")

    if args.download_images:
        if not args.site_url:
            sys.exit("--download-images needs --site-url")
        for rel in sorted(all_images):
            dest = out / args.static_dir / rel.lstrip("/")
            if dest.exists():
                continue
            dest.parent.mkdir(parents=True, exist_ok=True)
            url = args.site_url.rstrip("/") + rel
            try:
                with urllib.request.urlopen(url, timeout=30) as r, open(dest, "wb") as f:
                    f.write(r.read())
                print("  img", rel)
            except Exception as e:                       # noqa: BLE001
                print("  ! FAILED", url, e)

    print("\n--- conversion report ---")
    print("files written:", written, "| images referenced:", len(all_images))
    if missing_html:
        print("!! EMPTY html column (needs lexical render):", ", ".join(missing_html))
    for k, v in sorted(report.items()):
        print("  {:<40} {}".format(k, v))

    if fence_braces:
        print("\n!! {} post(s) have '{{{{' inside a code fence -- these BREAK the Hugo "
              "build. Fix with a {{{{< highlight >}}}} shortcode or {{{{/* */}}}} "
              "escaping:".format(len(fence_braces)))
        for s in fence_braces:
            print("   ", s)
    if fence_siteurl:
        print("\n!! {} post(s) quote the site URL inside a code fence. These were left "
              "verbatim (correctly) -- confirm that is what you want:"
              .format(len(fence_siteurl)))
        for s in fence_siteurl:
            print("   ", s)
    if fence_badlang:
        print("\n!! {} code fence(s) have a language Chroma cannot parse and will "
              "silently render as plaintext:".format(len(fence_badlang)))
        for s in fence_badlang:
            print("   ", s)

    if leftover_redirects:
        print("\n!! {} redirect(s) could NOT become Hugo aliases -- these need real 301s "
              "at the host (staticwebapp.config.json / _redirects):"
              .format(len(leftover_redirects)))
        for frm, to, code, why in leftover_redirects:
            print("   {} {} -> {}   [{}]".format(code, frm, to, why))
    print("\nimage manifest ->", manifest)


if __name__ == "__main__":
    main()