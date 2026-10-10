"""Reads the game list, rank cut-offs and tips from the live site into tools/games.json.
Run this after changing games or ranks, then run tools/build_pages.py.
Needs: pip install playwright (and a Chromium browser)."""
import json, pathlib, sys
from playwright.sync_api import sync_playwright

root = pathlib.Path(__file__).resolve().parent.parent
page_url = (root / "reaction-test" / "index.html").as_uri()
chromium = sys.argv[1] if len(sys.argv) > 1 else None   # optional path to a Chromium executable

with sync_playwright() as p:
    browser = p.chromium.launch(args=["--no-sandbox"], executable_path=chromium) if chromium else p.chromium.launch(args=["--no-sandbox"])
    page = browser.new_page()
    page.goto(page_url)
    page.wait_for_timeout(500)
    data = page.evaluate("""() => {
      const g = window.ReactionLabGames;
      return { games: g.GAMES, cuts: g.RANK_CUTS, rankNames: g.RANK_NAMES, rarity: g.RARITY, tips: g.TIPS };
    }""")
    browser.close()

(root / "tools" / "games.json").write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("wrote tools/games.json with", len(data["games"]), "games")
