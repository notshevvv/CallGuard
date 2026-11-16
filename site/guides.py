#!/usr/bin/env python3
"""Builds the guide pages into docs/guides/<slug>/index.html.
Each guide answers one real search question: short answer first, then why, then fixes."""
import html, json, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASE = "https://notshevvv.github.io/CallGuard/"
REL = "https://github.com/notshevvv/CallGuard/releases/latest"
UPDATED = "2026-11-16"
UPDATED_TEXT = "16 November 2026"

GUIDES = [
  {
    "slug": "stop-mac-lowering-volume-during-calls",
    "title": "How to stop your Mac lowering music during calls",
    "seo_title": "How to stop your Mac lowering music and video volume during calls (audio ducking)",
    "description": "Why macOS turns YouTube and Spotify down when a call starts (audio ducking), why there's no setting for it, and how to keep media at full volume on WhatsApp and other calls.",
    "answer": "macOS lowers other audio during calls because the call app runs Apple's voice processing, which \"ducks\" every other sound on the same output. There is no switch for it in System Settings. The free app CallGuard keeps media at full volume by moving the call to a muted device, where the ducking lands harmlessly, and playing everything to your earbuds.",
    "body": """
<h2>Why your music gets quieter when a call starts</h2>
<p>Call apps such as WhatsApp use Apple's voice-processing audio unit to cancel echo. While it runs, it lowers ("ducks") all other audio playing on the same output device. How much it lowers is a setting inside that audio unit, and <strong>only the call app can change it</strong>. In our tests, the difference between the call engine's minimum and default ducking was <strong>19 dB</strong>, enough to turn a song into background noise.</p>
<p>That's why searching System Settings doesn't help: the setting isn't yours to change. Re-playing the sound through another app doesn't escape it either. Audio played by a second app on the same device was ducked by exactly the same amount.</p>

<h2>Fix it with CallGuard (free)</h2>
<ol>
<li><a href="{REL}">Download CallGuard</a>, unzip it, and drag it into Applications. On first launch, go to System Settings → Privacy &amp; Security → Open Anyway.</li>
<li>Click the mic icon in the menu bar and turn on <strong>No Ducking</strong>.</li>
<li>Allow "System Audio Recording" when macOS asks. CallGuard uses it to take each app's sound before it is ducked. Nothing is recorded or saved.</li>
</ol>
<p>During a call, CallGuard points the call app at the Mac's built-in speakers, muted in hardware, so the ducking lands on a device nobody is listening to. It then plays everything (your music and the other person's voice) to your earbuds from a copy taken before the drop. Your volume keys keep working, and everything switches back when the call ends.</p>

<h2>Good to know</h2>
<ul>
<li>It needs earbuds or headphones, because the Mac's own speakers are the decoy.</li>
<li>Verified with WhatsApp for Mac. It should work with any app that follows the system output (FaceTime, Zoom, Teams, Meet), but these are untested. If an app doesn't switch, CallGuard falls back to boosting your media instead.</li>
<li>The other person never hears your music: CallGuard only changes what you hear.</li>
</ul>
<p>On Windows? It has a built-in switch: see the <a href="https://github.com/notshevvv/CallGuard/blob/main/WINDOWS.md">Windows guide</a>.</p>
""",
    "faq": [
      ("Is there a setting in macOS to stop ducking during calls?", "No. The amount of ducking is set by the call app's own voice processing, and macOS has no user setting for it."),
      ("Will the other person hear my music?", "No. CallGuard only changes what you hear. Your microphone isn't mixed with your media."),
      ("Does No Ducking work on the MacBook speakers?", "No. The built-in speakers are used as the muted decoy, so No Ducking needs earbuds, headphones or another output."),
    ],
    "related": ["bluetooth-earbuds-muffled-on-mac-calls", "stop-earbuds-unmuting-you-on-calls"],
  },
  {
    "slug": "bluetooth-earbuds-muffled-on-mac-calls",
    "title": "Why Bluetooth earbuds sound muffled on Mac calls, and how to fix it",
    "seo_title": "Why Bluetooth earbuds and AirPods sound muffled on Mac calls (and how to fix it)",
    "description": "On a call, Bluetooth earbuds switch to a low-quality headset mode (16 kHz mono). Here's why, how to keep stereo hi-fi by using the Mac's microphone, and how to make it automatic.",
    "answer": "Earbuds sound muffled on calls because using their microphone switches Bluetooth into headset mode, which carries sound at low quality (16 kHz, mono) in both directions. To keep stereo hi-fi, make the Mac's built-in microphone the input for calls. CallGuard's Hi-Fi Buds does that automatically.",
    "body": """
<h2>What's happening</h2>
<p>Most Bluetooth earbuds have two modes. <strong>Music mode</strong> (A2DP) plays rich stereo sound, but only in one direction. <strong>Headset mode</strong> (HFP) also carries the earbud microphone, so it squeezes everything into a narrow channel. On the earbuds we tested, that meant <strong>16 kHz, mono</strong>. The moment any app records from the earbud mic, the earbuds switch to headset mode, and your music and videos start sounding like an old phone line.</p>

<h2>Fix it by hand</h2>
<ol>
<li>Before the call, open <strong>System Settings → Sound → Input</strong> and choose the Mac's own microphone (for example "MacBook Air Microphone").</li>
<li>In your call app's audio settings, choose the same microphone if it lets you.</li>
<li>Keep the earbuds as the output. They stay in stereo, because nothing is using their mic.</li>
</ol>
<p>The trade-off: the other person hears you through the Mac's microphone, so speak towards the laptop.</p>

<h2>Make it automatic with CallGuard</h2>
<p>Turn on <strong>Hi-Fi Buds</strong> in <a href="{REL}">CallGuard</a>. Whenever a Bluetooth mic becomes the input, it switches the input back to the Mac's built-in mic. In a live WhatsApp test, WhatsApp followed the change mid-call and the earbuds went from 16 kHz to 44.1 kHz stereo.</p>
<p>If you fall asleep on calls, pair it with <strong>Mic Lock</strong>, so nobody hears you whichever mic is in use.</p>
""",
    "faq": [
      ("Why does Spotify sound bad when I'm on a call with earbuds?", "Because the earbuds have switched to Bluetooth headset mode to use their microphone, which is low-quality mono. Using the Mac's microphone instead keeps them in stereo."),
      ("Can I use the earbud mic and still have hi-fi sound?", "Not with ordinary Bluetooth headset mode: using the earbud mic is what lowers the quality."),
      ("Will the other person hear me worse with the Mac mic?", "They hear the laptop's microphone instead of the earbud one, so sound is best when you're near the Mac."),
    ],
    "related": ["stop-mac-lowering-volume-during-calls", "stop-earbuds-unmuting-you-on-calls"],
  },
  {
    "slug": "stop-earbuds-unmuting-you-on-calls",
    "title": "How to stop AirPods or earbuds unmuting you on a call",
    "seo_title": "How to stop AirPods or earbuds unmuting you on a WhatsApp call (Mac)",
    "description": "Earbud taps can toggle a call's mute button, often while you sleep. How to stop it: change the tap action, and lock the Mac's microphone at the hardware level so nothing can unmute you.",
    "answer": "Earbud taps can toggle the call app's mute button, so an accidental tap (rolling over in your sleep, for example) unmutes you. Change the tap action in your earbuds' settings, and for a guarantee, lock the microphone at the hardware level with CallGuard's Mic Lock. Apps then receive digital silence whatever their own mute button says.",
    "body": """
<h2>Why a tap unmutes you</h2>
<p>In headset mode, an earbud tap is sent to the call app as a mute or unmute command. The app's own mute button is only a switch inside that app. Anything that flips it, a tap included, puts you back on the call.</p>

<h2>Step 1: change the tap action</h2>
<p>For AirPods, open <strong>System Settings</strong> and click your AirPods while they're connected to see their controls. For other brands, use the earbuds' companion app (for example, the maker's phone app). Set the tap you hit in your sleep to "None" or play/pause.</p>

<h2>Step 2: lock the microphone itself</h2>
<p><a href="{REL}">CallGuard</a>'s <strong>Mic Lock</strong> mutes every microphone at the hardware level, so every app receives digital silence. In testing, a locked mic recorded <strong>0 non-zero samples</strong>. Many "mute" tools only set the input volume to zero, which in our test still let sound through at about <strong>−64 dBFS</strong>. If anything un-mutes a locked mic, CallGuard mutes it again within milliseconds and counts it.</p>
<ul>
<li>One click on the red <strong>LOCKED</strong> menu bar icon unmutes you.</li>
<li>Hold <strong>Control + Option + T</strong> to talk while locked. <strong>Control + Option + M</strong> locks and unlocks from anywhere.</li>
<li>It can lock itself when you go quiet on a call, and unlock when the call ends.</li>
</ul>
<p>macOS doesn't let one app block another app's microphone, so while Mic Lock is on, no app can hear you. That's what makes it reliable.</p>
""",
    "faq": [
      ("Can a Mac app mute the microphone for only WhatsApp?", "No. macOS doesn't allow one app to block another app's microphone without resetting privacy permissions. Mic Lock mutes the microphones themselves, which covers every app."),
      ("Is the mic really off when locked?", "Yes. A locked mic delivered exact digital silence in testing (0 non-zero samples), and CallGuard re-mutes it if anything unmutes it."),
      ("How do I talk again quickly?", "Click the red LOCKED icon in the menu bar, or hold Control + Option + T to talk while it stays locked."),
    ],
    "related": ["stop-mac-lowering-volume-during-calls", "bluetooth-earbuds-muffled-on-mac-calls"],
  },
  {
    "slug": "8d-audio-and-slowed-reverb-on-mac",
    "title": "8D audio and slowed + reverb for any app on Mac",
    "seo_title": "8D audio and slowed + reverb on Mac for Spotify, YouTube and any app (free)",
    "description": "How to play any song in 8D or slowed + reverb on a Mac, live: Spotify, YouTube, Apple Music and more, with a free menu bar app. Plus Studio Master bass for small earbuds.",
    "answer": "To get 8D audio or slowed + reverb for any app on a Mac, use a system-wide audio app. CallGuard is free and works live on Spotify, YouTube, Apple Music or anything else: turn on 8D Audio to make the music circle your head, or pick the Slowed + Reverb preset in Effects.",
    "body": """
<h2>What 8D audio actually is</h2>
<p>"8D" songs move the music slowly around your head. CallGuard's <strong>8D Audio</strong> does it live, using the same cues your brain uses to place a sound. It's louder in the near ear, arrives a fraction of a millisecond later in the far ear (up to 0.6 ms), and sounds duller behind your head. One turn takes 5 to 18 seconds, set with a Speed slider. Use earphones: on speakers it only sounds like panning.</p>

<h2>Slowed + reverb, live</h2>
<p>Slowed + reverb edits lower a song's pitch and add a big room around it. Live audio can't actually play slower, because it would fall behind the video. So CallGuard's <strong>Slowed + Reverb</strong> preset lowers the pitch by 3 semitones and adds reverb, and the timing stays in sync. Other presets: <strong>Sped Up</strong> (pitch up), <strong>Ambience</strong>, <strong>Harmony</strong> (adds a soft octave layer) and <strong>Dreamy</strong>. You can fine-tune pitch, reverb, room size, harmony and stereo width.</p>

<h2>How to turn it on</h2>
<ol>
<li><a href="{REL}">Download CallGuard</a> and open it from the menu bar.</li>
<li>For 8D: switch on the <strong>8D Audio</strong> card and pick a speed.</li>
<li>For slowed + reverb: tap <strong>Slowed + Reverb</strong> in the Effects card.</li>
<li>Allow "System Audio Recording" the first time. Nothing is recorded or saved.</li>
</ol>

<h2>Make small earbuds sound bigger</h2>
<p><strong>Studio Master</strong> adds the overtones of each bass note, so earbuds and laptop speakers let you <em>hear</em> deep bass they can't physically play. It also tightens the low end, dips boxiness at 320 Hz and adds air to the highs. A limiter keeps everything below −1 dBFS, so nothing clips.</p>
<p>On a call, all of these effects change only your music and videos. The other person's voice stays clean and centred.</p>
""",
    "faq": [
      ("Does it work with Spotify and YouTube?", "Yes. CallGuard processes all Mac audio, so it works with any app that plays sound: Spotify, YouTube in any browser, Apple Music and more."),
      ("Does slowed + reverb change the song's speed?", "No, live audio can't be slowed without falling behind. It lowers the pitch and adds reverb, so it sounds slowed while staying in sync."),
      ("Will effects change the voice on my call?", "No. Effects, 8D and Studio Master apply to music and videos only. The call voice is left untouched."),
    ],
    "related": ["stop-mac-lowering-volume-during-calls", "bluetooth-earbuds-muffled-on-mac-calls"],
  },
]

CSS = """
:root{--night:#0d0b2e;--ink:#f6f3ff;--ink-2:#d6cff2;--ink-3:#a39bcf;--edge:rgba(255,255,255,.16);
--display:"Bricolage Grotesque",-apple-system,sans-serif;--body:"Onest",-apple-system,"Segoe UI",sans-serif}
*{box-sizing:border-box}html{background:var(--night)}
body{margin:0;color:var(--ink);font:400 18px/1.7 var(--body);-webkit-font-smoothing:antialiased;
background:radial-gradient(60vmax 60vmax at 0% 0%,#3a2bb0 0%,transparent 60%),radial-gradient(55vmax 55vmax at 100% 30%,#9c2f6f 0%,transparent 60%),radial-gradient(50vmax 50vmax at 40% 100%,#5a2bc0 0%,transparent 60%),var(--night);background-attachment:fixed}
::selection{background:#b061ff;color:#fff}:focus-visible{outline:2px solid #fff;outline-offset:3px;border-radius:8px}
a{color:#e2d4ff;text-underline-offset:3px}a:hover{color:#fff}
.wrap{width:min(860px,100% - 32px);margin-inline:auto}
.glass{border-radius:26px;background:linear-gradient(155deg,rgba(255,255,255,.13),rgba(255,255,255,.04) 60%);-webkit-backdrop-filter:blur(24px) saturate(160%);backdrop-filter:blur(24px) saturate(160%);border:1px solid var(--edge);box-shadow:0 1px 0 rgba(255,255,255,.3) inset,0 28px 60px -28px rgba(4,2,20,.85)}
.rail{position:sticky;top:12px;z-index:10;margin-top:12px}
.rail .glass{display:flex;justify-content:space-between;align-items:center;padding:10px 12px 10px 16px;border-radius:999px;background:linear-gradient(155deg,rgba(44,32,112,.84),rgba(18,14,54,.86))}
.brand{display:flex;align-items:center;gap:10px;color:var(--ink);text-decoration:none;font:800 18px/1 var(--display)}
.brand img{width:28px;height:28px;border-radius:7px}
.dl{color:#140f36;background:linear-gradient(180deg,#fff,#e9e4ff);padding:10px 18px;border-radius:999px;text-decoration:none;font-weight:600;font-size:15px}
.dl:hover{color:#140f36}
nav.crumbs{margin:44px 0 10px;font-size:14px;color:var(--ink-3)}nav.crumbs a{color:var(--ink-2)}
h1{font:800 clamp(34px,5.4vw,58px)/1.04 var(--display);letter-spacing:-.03em;margin:0 0 14px;text-wrap:balance}
.meta{color:var(--ink-3);font-size:14.5px;margin:0 0 26px}
.answer{padding:24px 26px;margin:0 0 34px}
.answer p{margin:0;font-size:19px;color:var(--ink)}
article h2{font:700 clamp(24px,3vw,32px)/1.2 var(--display);letter-spacing:-.02em;margin:44px 0 12px}
article p,article li{color:var(--ink-2)}article strong{color:var(--ink)}
article ol,article ul{padding-left:22px}article li{margin:6px 0}
.faq{margin-top:46px}.faq h3{font:700 19px/1.3 var(--display);margin:22px 0 4px;color:var(--ink)}.faq p{margin:0}
.cta{margin:48px 0 0;padding:28px;text-align:center}
.cta p{margin:0 0 16px;color:var(--ink-2)}
.related{margin:40px 0 0}.related ul{list-style:none;padding:0;margin:10px 0 0;display:grid;gap:8px}
.related a{display:block;padding:14px 18px;border-radius:16px;background:rgba(255,255,255,.06);box-shadow:inset 0 0 0 1px rgba(255,255,255,.1);text-decoration:none;color:var(--ink)}
.related a:hover{background:rgba(255,255,255,.11)}
footer{margin:60px 0 50px;color:var(--ink-3);font-size:14px;display:flex;flex-wrap:wrap;gap:10px 22px;justify-content:space-between}
footer a{color:var(--ink-2);text-decoration:none}
"""

def page(g):
    url = f"{BASE}guides/{g['slug']}/"
    by_slug = {x["slug"]: x for x in GUIDES}
    ld = [
        {"@context": "https://schema.org", "@type": "Article", "headline": g["seo_title"], "description": g["description"],
         "datePublished": UPDATED, "dateModified": UPDATED, "inLanguage": "en", "mainEntityOfPage": url,
         "image": BASE + "assets/og.jpg",
         "author": {"@type": "Person", "name": "notshevvv", "url": "https://github.com/notshevvv"},
         "about": {"@type": "SoftwareApplication", "name": "CallGuard", "operatingSystem": "macOS 14.4 or later",
                   "applicationCategory": "MultimediaApplication", "url": BASE,
                   "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"}}},
        {"@context": "https://schema.org", "@type": "FAQPage",
         "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in g["faq"]]},
        {"@context": "https://schema.org", "@type": "BreadcrumbList", "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "CallGuard", "item": BASE},
            {"@type": "ListItem", "position": 2, "name": "Guides", "item": BASE + "guides/"},
            {"@type": "ListItem", "position": 3, "name": g["title"], "item": url}]},
    ]
    faq = "".join(f"<h3>{html.escape(q)}</h3><p>{html.escape(a)}</p>" for q, a in g["faq"])
    rel = "".join(f'<li><a href="../{s}/">{html.escape(by_slug[s]["title"])} →</a></li>' for s in g["related"])
    body = g["body"].replace("{REL}", REL)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(g['seo_title'])}</title>
<meta name="description" content="{html.escape(g['description'])}">
<link rel="canonical" href="{url}">
<link rel="icon" href="../../assets/icon-256.png"><link rel="apple-touch-icon" href="../../assets/apple-touch-icon.png">
<meta name="theme-color" content="#0d0b2e">
<meta property="og:type" content="article"><meta property="og:site_name" content="CallGuard">
<meta property="og:title" content="{html.escape(g['title'])}"><meta property="og:description" content="{html.escape(g['description'])}">
<meta property="og:url" content="{url}"><meta property="og:image" content="{BASE}assets/og.jpg">
<meta property="article:modified_time" content="{UPDATED}">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:image" content="{BASE}assets/og.jpg">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,700;12..96,800&family=Onest:wght@400;600&display=swap" rel="stylesheet">
<script type="application/ld+json">{json.dumps(ld, ensure_ascii=False)}</script>
<style>{CSS}</style>
</head>
<body>
<div class="rail wrap"><div class="glass">
  <a class="brand" href="../../"><img src="../../assets/icon-128.webp" alt="" width="28" height="28">CallGuard</a>
  <a class="dl" href="{REL}">Download for Mac</a>
</div></div>
<main class="wrap">
<nav class="crumbs" aria-label="Breadcrumb"><a href="../../">CallGuard</a> / <a href="../">Guides</a></nav>
<article>
<h1>{html.escape(g['title'])}</h1>
<p class="meta">Updated {UPDATED_TEXT} · by notshevvv, maker of CallGuard</p>
<div class="answer glass"><p>{html.escape(g['answer'])}</p></div>
{body}
<section class="faq" aria-labelledby="faqh"><h2 id="faqh">Quick answers</h2>{faq}</section>
</article>
<div class="cta glass"><p>CallGuard is free and open source. macOS 14.4 or later, Apple silicon and Intel.</p><a class="dl" href="{REL}">Download CallGuard for Mac</a></div>
<section class="related" aria-labelledby="relh"><h2 id="relh" style="font:700 22px/1.2 var(--display)">Related guides</h2><ul>{rel}</ul></section>
<footer><span>CallGuard · MIT license</span><span><a href="../../">Home</a> · <a href="https://github.com/notshevvv/CallGuard">GitHub</a> · <a href="../../llms.txt">llms.txt</a></span></footer>
</main>
</body>
</html>
"""

def index_page():
    items = "".join(f'<li><a href="{g["slug"]}/"><strong>{html.escape(g["title"])}</strong><br><span style="color:#cfc8ee;font-size:15.5px">{html.escape(g["description"])}</span></a></li>' for g in GUIDES)
    ld = {"@context": "https://schema.org", "@type": "CollectionPage", "name": "CallGuard guides", "url": BASE + "guides/",
          "hasPart": [{"@type": "Article", "headline": g["seo_title"], "url": f"{BASE}guides/{g['slug']}/"} for g in GUIDES]}
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mac call and audio guides: ducking, muffled earbuds, mic mute, 8D audio | CallGuard</title>
<meta name="description" content="Plain-English guides to fixing Mac audio on calls: stop music ducking, fix muffled Bluetooth earbuds, stop earbuds unmuting you, and get 8D audio and slowed + reverb.">
<link rel="canonical" href="{BASE}guides/"><link rel="icon" href="../assets/icon-256.png"><meta name="theme-color" content="#0d0b2e">
<meta property="og:title" content="CallGuard guides"><meta property="og:image" content="{BASE}assets/og.jpg"><meta property="og:url" content="{BASE}guides/">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,700;12..96,800&family=Onest:wght@400;600&display=swap" rel="stylesheet">
<script type="application/ld+json">{json.dumps(ld, ensure_ascii=False)}</script>
<style>{CSS}</style></head>
<body>
<div class="rail wrap"><div class="glass"><a class="brand" href="../"><img src="../assets/icon-128.webp" alt="" width="28" height="28">CallGuard</a><a class="dl" href="{REL}">Download for Mac</a></div></div>
<main class="wrap"><nav class="crumbs" aria-label="Breadcrumb"><a href="../">CallGuard</a> / Guides</nav>
<h1>Guides</h1><p class="meta">Fixes for Mac audio on long calls, in plain English. Updated {UPDATED_TEXT}.</p>
<section class="related"><ul>{items}</ul></section>
<footer><span>CallGuard · MIT license</span><span><a href="../">Home</a> · <a href="https://github.com/notshevvv/CallGuard">GitHub</a></span></footer>
</main></body></html>
"""

if __name__ == "__main__":
    for g in GUIDES:
        d = ROOT / "docs" / "guides" / g["slug"]
        d.mkdir(parents=True, exist_ok=True)
        (d / "index.html").write_text(page(g))
    (ROOT / "docs" / "guides" / "index.html").write_text(index_page())
    print(f"built {len(GUIDES)} guides + guides index")
