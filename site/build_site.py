#!/usr/bin/env python3
"""Builds docs/index.html from site/template.html: FAQ + JSON-LD come from README.md so they never drift."""
import html, json, re, pathlib, math
root = pathlib.Path(__file__).resolve().parent.parent
readme = (root / "README.md").read_text()
faq_md = readme[readme.index("## Questions people ask"):readme.index("## On Windows?")]
faqs = [(q.strip(), a.strip()) for q, a in re.findall(r"### (.+?)\n(.+?)(?=\n### |\Z)", faq_md, re.S)]
BASE = "https://notshevvv.github.io/CallGuard/"
REL = "https://github.com/notshevvv/CallGuard/releases/latest"

def text(t):
    t = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", t).replace("**", "").replace("*", "")
    return " ".join(t.split())

def rich(t):
    t = html.escape(t, quote=False)
    def link(m):
        label, href = m.group(1), m.group(2)
        if href.startswith("../../"): href = "https://github.com/notshevvv/CallGuard/" + href[6:]
        elif not href.startswith("http"): href = "https://github.com/notshevvv/CallGuard/blob/main/" + href
        return f'<a href="{href}">{label}</a>'
    t = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, t)
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"\*(.+?)\*", r"<em>\1</em>", t)
    return " ".join(t.split())

ld = [{
    "@context": "https://schema.org", "@type": "SoftwareApplication", "name": "CallGuard",
    "description": "Free, open-source macOS menu bar app that stops call audio ducking, locks the microphone, keeps Bluetooth earbuds in hi-fi, and adds Studio Master bass, 8D audio and slowed + reverb effects to all Mac audio.",
    "operatingSystem": "macOS 14.4 or later", "applicationCategory": "MultimediaApplication", "softwareVersion": "3.3.0",
    "dateModified": "2026-11-16", "license": "https://opensource.org/licenses/MIT", "isAccessibleForFree": True,
    "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
    "downloadUrl": REL, "url": BASE, "image": BASE + "assets/og.jpg", "screenshot": BASE + "assets/panel.webp",
    "codeRepository": "https://github.com/notshevvv/CallGuard",
    "featureList": ["Stop macOS audio ducking during calls", "Hardware microphone lock with push-to-talk",
                    "Keep Bluetooth earbuds in stereo hi-fi on calls", "Studio Master premium sound with harmonic bass",
                    "8D audio", "Slowed + reverb, sped up, ambience and harmony effects",
                    "Volume boost to 300% and bass boost to +12 dB", "Sleep timer that fades media but keeps the call voice",
                    "Night Mode compressor"],
    "author": {"@type": "Person", "name": "notshevvv", "url": "https://github.com/notshevvv"}},
    {"@context": "https://schema.org", "@type": "FAQPage",
     "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": text(a)}} for q, a in faqs]}]

plus = '<span class="plus" aria-hidden="true"><svg width="14" height="14" viewBox="0 0 14 14"><path d="M7 1v12M1 7h12" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg></span>'
faq_html = "\n".join(f'<details><summary><h3>{html.escape(q)}</h3>{plus}</summary><p>{rich(a)}</p></details>' for q, a in faqs)

tick = '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3 8.5l3.2 3L13 4.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'

def svg(body, w=24):
    return f'<svg viewBox="0 0 24 24" width="{w}" height="{w}" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{body}</svg>'
MIC = svg('<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>')
MICSLASH = svg('<path d="M15 9.3V6a3 3 0 0 0-5.7-1.3M9 9v2a3 3 0 0 0 4.6 2.5M5 11a7 7 0 0 0 11.2 5.6M19 11a7 7 0 0 1-.6 2.8M12 18v3M3 3l18 18"/>')
ICONS = {
  "APPLE": '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.37 12.6c-.02-2.2 1.8-3.26 1.88-3.31-1.03-1.5-2.62-1.7-3.18-1.73-1.35-.14-2.64.8-3.33.8-.7 0-1.75-.78-2.88-.76-1.48.02-2.85.86-3.61 2.19-1.54 2.67-.39 6.62 1.1 8.79.74 1.06 1.61 2.25 2.75 2.2 1.11-.04 1.52-.71 2.86-.71 1.33 0 1.71.71 2.88.69 1.19-.02 1.94-1.08 2.66-2.15.84-1.23 1.19-2.43 1.2-2.49-.03-.01-2.3-.88-2.33-3.52zM14.2 6.13c.6-.74 1.01-1.75.9-2.77-.87.04-1.94.59-2.56 1.32-.56.64-1.05 1.68-.92 2.67.97.08 1.97-.49 2.58-1.22z"/></svg>',
  "GITHUB": '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 .5C5.65.5.5 5.65.5 12a11.5 11.5 0 0 0 7.86 10.92c.58.1.79-.25.79-.56v-2c-3.2.7-3.87-1.37-3.87-1.37-.52-1.33-1.28-1.69-1.28-1.69-1.05-.71.08-.7.08-.7 1.16.08 1.77 1.19 1.77 1.19 1.03 1.77 2.7 1.26 3.36.96.1-.75.4-1.26.73-1.55-2.56-.29-5.25-1.28-5.25-5.69 0-1.26.45-2.29 1.19-3.1-.12-.29-.52-1.46.11-3.05 0 0 .97-.31 3.17 1.18a11 11 0 0 1 5.77 0c2.2-1.49 3.17-1.18 3.17-1.18.63 1.59.23 2.76.11 3.05.74.81 1.19 1.84 1.19 3.1 0 4.42-2.7 5.39-5.27 5.68.41.36.78 1.06.78 2.14v3.17c0 .31.21.67.8.56A11.5 11.5 0 0 0 23.5 12C23.5 5.65 18.35.5 12 .5z"/></svg>',
  "MIC": MIC, "MICSLASH": svg('<path d="M15 9.3V6a3 3 0 0 0-5.7-1.3M9 9v2a3 3 0 0 0 4.6 2.5M5 11a7 7 0 0 0 11.2 5.6M19 11a7 7 0 0 1-.6 2.8M12 18v3M3 3l18 18"/>', 18),
  "SPEAKER": svg('<path d="M4 9v6h4l5 4V5L8 9H4z"/><path d="M16.5 8.5a5 5 0 0 1 0 7M19 6a8.5 8.5 0 0 1 0 12"/>', 18),
  "BUDS": svg('<path d="M7 4a3 3 0 0 0-3 3v2a3 3 0 0 0 3 3h1V4H7zM8 12v7a1.5 1.5 0 0 0 3 0V8M17 4a3 3 0 0 1 3 3v2a3 3 0 0 1-3 3h-1V4h1zM16 12v7a1.5 1.5 0 0 1-3 0V8"/>', 18),
  "SPARKLE": svg('<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8L12 3zM19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8L19 15z"/>', 18),
  "WAVE": svg('<path d="M3 12h2M7 8v8M11 5v14M15 9v6M19 7v10M21 12h0"/>', 18),
  "ORBIT": svg('<circle cx="12" cy="12" r="3"/><ellipse cx="12" cy="12" rx="10" ry="4.5" transform="rotate(-20 12 12)"/><circle cx="20" cy="9" r="1.4" fill="currentColor"/>', 18),
  "MOON": svg('<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/>', 18),
  "LEVELS": "".join('<span class="lvl"><i></i></span>' for _ in range(8)),
}
ICONS["MIC_JS"] = json.dumps(MIC)
ICONS["MICSLASH_JS"] = json.dumps(MICSLASH)

page = (root / "site/template.html").read_text()
page = (page.replace("{{JSONLD}}", json.dumps(ld, ensure_ascii=False))
            .replace("{{FAQ_HTML}}", faq_html).replace("{{TICK}}", tick))
for k, v in ICONS.items():
    page = page.replace("{{" + k + "}}", v)
assert "{{" not in page, "unfilled placeholder"
(root / "docs/index.html").write_text(page)
print(f"built docs/index.html with {len(faqs)} FAQs")
