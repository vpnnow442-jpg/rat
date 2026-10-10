"""Builds the static pages that help people (and search engines) find each game.

Writes:
  reaction-test/play/<game>.html   one page per game and reaction mode
  reaction-test/play/index.html    a hub listing every game
  reaction-test/guides/*.html      the guides
  sitemap.xml and robots.txt       at the repository root

Usage:
  python3 tools/build_pages.py
  python3 tools/build_pages.py --name Reflexir --base https://yourdomain.com/reaction-test

Game data comes from tools/games.json (made by tools/extract_games.py), so the pages
always match the ranks and tips in the site itself.
"""
import argparse
import html
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITE = ROOT / "reaction-test"

ap = argparse.ArgumentParser()
ap.add_argument("--name", default="Reflexir")
ap.add_argument("--base", default="https://vpnnow442-jpg.github.io/rat/reaction-test",
                help="public address of the reaction-test folder, with no trailing slash")
args = ap.parse_args()
NAME = args.name
BASE = args.base.rstrip("/")
esc = html.escape

data = json.loads((ROOT / "tools" / "games.json").read_text(encoding="utf-8"))
GAMES = data["games"]
CUTS = data["cuts"]
RANK_NAMES = data["rankNames"]
RARITY = data["rarity"]
TIPS = data["tips"]

CAT_LABEL = {"brain": "Memory and speed", "vision": "Vision", "originals": "Originals", "classics": "Reaction classics"}

# Reaction modes are described here, with the research that exists for each.
MODES = [
    {"id": "simple", "name": "Simple Reaction Time Test",
     "desc": "Wait for the screen to change colour, then click as fast as you can. This is the classic reaction time test.",
     "facts": ["In a lab study of 1,469 adults aged 18 to 65, the average simple visual reaction time was about 231 ms, or about 213 ms after correcting for equipment delay. It got slower by about 0.55 ms for each year of age.",
               "Online tests usually read higher than lab tests, because your screen, mouse and browser each add a little delay. One reaction time site reports a median of about 270 ms."],
     "sources": [("Woods et al. 2015, Frontiers in Human Neuroscience", "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4374455/"),
                 ("Reaction time test benchmark article", "https://reactiontimetests.org/blog/human-benchmark-reaction-time")]},
    {"id": "audio", "name": "Audio Reaction Time Test",
     "desc": "No colours and no words. Listen for the beep, then click as soon as you hear it. A pure sound reaction test.",
     "facts": ["A review cited in one paper puts the time to detect a sound at roughly 140 to 160 ms, compared with about 180 to 200 ms for something you see.",
               "A small study of 14 people found about 284 ms for sound and 331 ms for sight. The numbers differ between studies, so treat them as rough."],
     "sources": [("Review cited in PMC4456887", "https://pmc.ncbi.nlm.nih.gov/articles/PMC4456887"),
                 ("Shelton and Kumar, auditory vs visual reaction times", "https://coachsci.sdsu.edu/csa/vol191/shelton.htm")]},
    {"id": "target", "name": "Target Click Reaction Test",
     "desc": "Wait for a target to appear in a random spot, then click it as fast as you can. Clicking empty space counts as a mistake.",
     "facts": ["We did not find published averages for this exact task, so the ranks on the site are our own estimates."],
     "sources": []},
    {"id": "arrows", "name": "Arrow Choice Reaction Test",
     "desc": "An arrow appears. Press that direction on your keyboard, or tap that side of the box. Wrong directions count as mistakes.",
     "facts": ["Choice tasks like this take longer than a simple click because you also have to decide which way to respond. We did not find published averages for four-way arrows, so the ranks on the site are our own estimates."],
     "sources": []},
]

GUIDES = [
    ("average-reaction-time", "Average reaction time: what the research says",
     "What is a normal reaction time? Numbers from published studies for adults, athletes and online tests, with sources."),
    ("how-to-improve-reaction-time", "How to improve your reaction time",
     "Practical, honest tips for a faster reaction time score, including what changes your result and what does not."),
]

pages = []  # (relative path, title) for the sitemap


def layout(rel_path, title, description, body, depth):
    """Wrap page content in the shared header, footer and meta tags."""
    up = "../" * depth
    url = f"{BASE}/{rel_path}"
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)} | {esc(NAME)}</title>
<meta name="description" content="{esc(description)}">
<link rel="canonical" href="{esc(url)}">
<link rel="icon" type="image/svg+xml" href="{up}favicon.svg">
<link rel="stylesheet" href="{up}pages.css">
<meta property="og:type" content="website">
<meta property="og:title" content="{esc(title)} | {esc(NAME)}">
<meta property="og:description" content="{esc(description)}">
<meta property="og:url" content="{esc(url)}">
<meta name="twitter:card" content="summary">
</head>
<body>
<div class="wrap">
  <div class="top">
    <a class="brand" href="{up}index.html"><img src="{up}favicon.svg" alt="">{esc(NAME)}</a>
    <div class="nav"><a href="{up}play/">All games</a><a href="{up}guides/">Guides</a><a href="{up}index.html">Open the app</a></div>
  </div>
{body}
  <footer>
    <a href="{up}index.html">Home</a><a href="{up}play/">All games</a><a href="{up}guides/">Guides</a><a href="{up}terms.html">Terms</a>
    <p>{esc(NAME)} is for fun and self-tracking. It is not a medical test.</p>
  </footer>
</div>
</body>
</html>
"""


def write(rel_path, content):
    out = SITE / rel_path
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(content, encoding="utf-8")


def rank_table(game):
    cuts = CUTS[game["id"]]
    rows = []
    for i, name in enumerate(RANK_NAMES):
        need = f"{cuts[i]} {game['unit']} or more" if game["higherBetter"] else f"under {cuts[i]} {game['unit']}"
        rows.append(f"<tr><td>{esc(name)}</td><td>{esc(need)}</td><td>{esc(RARITY[i])}</td></tr>")
    return ("<table><thead><tr><th>Rank</th><th>Score needed</th><th>How rare (rough guide)</th></tr></thead><tbody>"
            + "".join(rows) + "</tbody></table>")


# ---- one page per game ----
for g in GAMES:
    cat = g.get("cat", "brain")
    same = [x for x in GAMES if x.get("cat", "brain") == cat and x["id"] != g["id"]][:6]
    related = "".join(f'<a href="{x["id"]}.html">{esc(x["name"])}<small>{esc(x["desc"])}</small></a>' for x in same)
    title = f"{g['name']}: free online game"
    desc = f"{g['desc']} Free to play in your browser, with ranks and progress tracking."
    better = "Higher scores are better." if g["higherBetter"] else "Lower scores are better."
    body = f"""
  <p class="crumbs"><a href="./">All games</a> / {esc(CAT_LABEL.get(cat, cat))}</p>
  <h1>{esc(g['name'])}</h1>
  <p class="lead">{esc(g['desc'])}</p>
  <a class="play" href="../index.html#game={esc(g['id'])}">Play {esc(g['name'])}</a>
  <h2>How to get a better score</h2>
  <div class="card"><p style="margin:0">{esc(TIPS.get(g['id'], 'Practise a little each day and stay relaxed.'))}</p></div>
  <h2>Ranks</h2>
  <p>Your score is measured in {esc(g['unit'])}. {better} Ranks run from {esc(RANK_NAMES[0])} up to {esc(RANK_NAMES[-1])}.</p>
  {rank_table(g)}
  <p class="note">The ranks and rarity labels are rough guides set by us. They are not measured norms from a study of players.</p>
  <h2>More {esc(CAT_LABEL.get(cat, cat)).lower()} games</h2>
  <div class="grid">{related}</div>"""
    write(f"play/{g['id']}.html", layout(f"play/{g['id']}.html", title, desc, body, 1))
    pages.append(f"play/{g['id']}.html")

# ---- one page per reaction mode ----
for m in MODES:
    facts = "".join(f"<li>{esc(f)}</li>" for f in m["facts"])
    sources = ("<h2>Sources</h2><ul>" + "".join(f'<li><a href="{esc(u)}" rel="noopener">{esc(t)}</a></li>' for t, u in m["sources"]) + "</ul>") if m["sources"] else ""
    desc = f"{m['desc']} Free in your browser, with your average and your best time tracked."
    body = f"""
  <p class="crumbs"><a href="./">All games</a> / Reaction tests</p>
  <h1>{esc(m['name'])}</h1>
  <p class="lead">{esc(m['desc'])}</p>
  <a class="play" href="../index.html#game=r-{esc(m['id'])}">Start the test</a>
  <h2>What the research says</h2>
  <ul>{facts}</ul>
  {sources}
  <p class="note">Results in a browser include a little delay from your device, so compare yourself with your own past scores more than with other people's.</p>"""
    write(f"play/r-{m['id']}.html", layout(f"play/r-{m['id']}.html", m["name"], desc, body, 1))
    pages.append(f"play/r-{m['id']}.html")

# ---- hub page listing everything ----
sections = []
sections.append("<h2>Reaction tests</h2><div class=\"grid\">" + "".join(
    f'<a href="r-{m["id"]}.html">{esc(m["name"])}<small>{esc(m["desc"])}</small></a>' for m in MODES) + "</div>")
for key, label in CAT_LABEL.items():
    items = [g for g in GAMES if g.get("cat", "brain") == key]
    if not items:
        continue
    sections.append(f"<h2>{esc(label)}</h2><div class=\"grid\">" + "".join(
        f'<a href="{g["id"]}.html">{esc(g["name"])}<small>{esc(g["desc"])}</small></a>' for g in items) + "</div>")
hub_desc = f"Every reaction time test and brain game on {NAME}: memory, speed, vision and reflex games, all free in your browser."
hub_body = f"""
  <h1>All reaction tests and brain games</h1>
  <p class="lead">Pick a game to read how it works, see the ranks, and play it free in your browser.</p>
  {''.join(sections)}"""
write("play/index.html", layout("play/", "All reaction tests and brain games", hub_desc, hub_body, 1))
pages.append("play/")

# ---- guides ----
avg_body = f"""
  <p class="crumbs"><a href="./">Guides</a> / Average reaction time</p>
  <h1>Average reaction time: what the research says</h1>
  <p class="lead">There is no single "normal" reaction time. It depends on what you react to, how it is measured, and who is being tested. Here are the numbers we could find in published sources.</p>
  <a class="play" href="../index.html#game=r-simple">Test your own reaction time</a>
  <h2>Adults, simple visual reaction</h2>
  <p>A lab study of 1,469 adults aged 18 to 65 found an average simple visual reaction time of about 231 ms, or about 213 ms after correcting for equipment delay. Reaction time got slower by about 0.55 ms for each year of age. <a href="https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4374455/" rel="noopener">Woods et al. 2015</a>.</p>
  <p>Other lab samples from the UK, pooled in a published commentary, give averages of roughly 208 ms to 238 ms. The older figures come from very old equipment and are debated. <a href="https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4542533/" rel="noopener">Commentary on UK samples</a>.</p>
  <h2>Sound vs sight</h2>
  <p>Reacting to a sound is usually a little faster than reacting to something you see. A review cited in one paper gives roughly 140 to 160 ms for sound and 180 to 200 ms for sight. A small study of 14 people found about 284 ms for sound and 331 ms for sight, so the exact numbers vary a lot. <a href="https://pmc.ncbi.nlm.nih.gov/articles/PMC4456887" rel="noopener">Review</a>, <a href="https://coachsci.sdsu.edu/csa/vol191/shelton.htm" rel="noopener">small study</a>.</p>
  <h2>Elite sprinters</h2>
  <p>At the 2008 Beijing Olympics, an analysis of 425 sprinters found average fastest-start reaction times of 166 ms for men and 189 ms for women. The fastest possible reactions in that study were about 109 ms and 121 ms. <a href="https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0026141" rel="noopener">PLOS ONE sprinter study</a>.</p>
  <h2>Online tests</h2>
  <p>Browser tests usually read higher than lab tests, because your screen, mouse and browser each add delay. One reaction time site reports a median of about 270 ms. <a href="https://reactiontimetests.org/blog/human-benchmark-reaction-time" rel="noopener">Reaction time test benchmark article</a>. This is a website's own figure, not a controlled study.</p>
  <h2>What to take from this</h2>
  <p>Compare yourself mainly with your own past scores on the same device. Differences of 10 to 20 ms between tries are normal.</p>"""
write("guides/average-reaction-time.html", layout("guides/average-reaction-time.html", GUIDES[0][1], GUIDES[0][2], avg_body, 1))
pages.append("guides/average-reaction-time.html")

imp_body = f"""
  <p class="crumbs"><a href="./">Guides</a> / Improve your reaction time</p>
  <h1>How to improve your reaction time</h1>
  <p class="lead">Your basic reaction speed is mostly set by your nervous system, so big changes are unlikely. You can still improve how reliably you perform and remove things that slow your score down.</p>
  <a class="play" href="../index.html#game=r-simple">Try the reaction test</a>
  <p class="note">These are practical tips, not the findings of one specific study. We have not tested them for you.</p>
  <h2>Check your setup first</h2>
  <ul>
    <li>A screen with a higher refresh rate and a wired mouse usually add less delay than a slow screen and a wireless mouse.</li>
    <li>Close other tabs and apps, which can make a browser test less steady.</li>
    <li>Test on the same device each time so you can compare your scores fairly.</li>
  </ul>
  <h2>Practise in short sessions</h2>
  <ul>
    <li>A few minutes a day is easier to keep up than one long session.</li>
    <li>Do five or more tries and look at your average, not your single best.</li>
    <li>Stop if you feel dizzy or get a headache.</li>
  </ul>
  <h2>Stay relaxed and focused</h2>
  <ul>
    <li>Many people react more steadily when they are rested and not distracted.</li>
    <li>Keep your hand loose and ready. Tensing up tends to make timing worse.</li>
    <li>Look at the middle of the screen so you can see changes anywhere.</li>
  </ul>
  <h2>Train the skill you want</h2>
  <p>Reaction time is not one skill. Reacting to a sound, picking the right arrow, and hitting a moving target all use different parts of the task. Mix the <a href="../play/">games</a> to practise different kinds of reaction.</p>"""
write("guides/how-to-improve-reaction-time.html", layout("guides/how-to-improve-reaction-time.html", GUIDES[1][1], GUIDES[1][2], imp_body, 1))
pages.append("guides/how-to-improve-reaction-time.html")

guides_cards = "".join(f'<a href="{slug}.html">{esc(t)}<small>{esc(d)}</small></a>' for slug, t, d in GUIDES)
guides_body = f"""
  <h1>Reaction time guides</h1>
  <p class="lead">Short guides with the sources we used.</p>
  <div class="grid">{guides_cards}</div>"""
write("guides/index.html", layout("guides/", "Reaction time guides", "Guides about reaction time: what the research says and how to improve your score.", guides_body, 1))
pages.append("guides/")

# ---- sitemap and robots at the repository root ----
site_root = BASE[: -len("/reaction-test")] if BASE.endswith("/reaction-test") else BASE
urls = [f"{BASE}/"] + [f"{BASE}/{p}" for p in pages] + [f"{BASE}/terms.html"]
sitemap = ('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
           + "".join(f"  <url><loc>{esc(u)}</loc></url>\n" for u in urls) + "</urlset>\n")
(ROOT / "sitemap.xml").write_text(sitemap, encoding="utf-8")
(ROOT / "robots.txt").write_text(f"User-agent: *\nAllow: /\n\nSitemap: {site_root}/sitemap.xml\n", encoding="utf-8")

print(f"built {len(pages)} pages for '{NAME}' at {BASE}")
