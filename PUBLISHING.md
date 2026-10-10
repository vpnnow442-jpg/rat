# Publishing guide

This is the checklist for taking the site from "works on my machine" to a real website, with accounts, leaderboards and a donate button. Nothing here needs you to write code.

## 1. Pick a name and a domain

Pick something short, easy to say, easy to spell, and related to reaction. A few ideas:

- Reflex Arena, Reflexa, ReflexHub, Reflex Forge
- React Arena, ReactRank, React Forge
- Blink Rank, Snap Rank, Twitch Lab
- Milli Arena (for milliseconds), Synapse Arena
- Quickfire Lab, Hair Trigger

I could not check whether any of these are free or trademarked. Before you commit:

1. Search the name on Google and in your country's trademark database (the UK IPO search is free) so you do not pick someone else's brand.
2. Check the `.com` at a registrar (Cloudflare Registrar, Namecheap, Porkbun). Expect roughly 10 to 15 pounds a year.
3. Check that the social handles (TikTok, YouTube, Instagram, Discord) are free, because you will want the same name everywhere.

The site is currently called **Reflexir** (reflex + elixir). The name is one setting, `siteName` in `reaction-test/config.js`, and you can pass `--name` to `tools/build_pages.py` to rename the generated pages. Check that Reflexir is free to use (Google, trademark search, domain, social handles) before you commit to it.

## 2. Put it on a real domain

1. Buy the domain.
2. GitHub repo: Settings > Pages. Add your domain under Custom domain and tick Enforce HTTPS.
3. At your registrar add the DNS records GitHub shows you (four A records for the apex and a CNAME for `www`).
4. Update `robots.txt` and `sitemap.xml` in the repo root with your final address.

## 3. DDoS and traffic protection

GitHub Pages already sits behind a large network. If you want more control, put **Cloudflare** (free plan) in front of your domain. It adds caching, bot filtering and DDoS protection. Set it up after the domain works, following Cloudflare's own steps for GitHub Pages.

## 4. Turn on accounts, usernames and leaderboards

Accounts need a small server. Supabase has a free plan and does the sign-in for you.

1. Create a project at supabase.com.
2. Open **SQL Editor**, paste the whole of `supabase/schema.sql`, and run it. This creates unique usernames, the leaderboards, and the anti-cheat checks.
3. In **Project Settings > API** copy the **Project URL** and the **anon public key**.
4. Put them in `reaction-test/config.js`. The anon key is meant to be public. **Never** paste the `service_role` key anywhere in the site.
5. In **Authentication > URL Configuration** set the Site URL to your final address.
6. In **Authentication > Providers > Email** keep email confirmation on.

What the setup enforces on the server:

- One username per person, case-insensitive (`Alice` and `alice` count as the same).
- Scores can only be written through `submit_score()`, which rejects impossible values for each game, limits how often you can submit, and caps submissions per day.

What it cannot do: a browser game can never be made fully cheat-proof, because the player controls their own browser. The checks stop the lazy cheats (fake scores, flooding). A determined cheater could still play perfectly with a script. Keep the leaderboard for fun, and do not offer prizes based on it.

## 5. Donations

1. Create a page at Ko-fi, Buy Me a Coffee, or GitHub Sponsors.
2. Put the link (starting with `https://`) in `reaction-test/config.js` as `donateUrl`.

The Support tab shows the button once the link is set. Payments are handled entirely by that service.

## 6. Getting visitors

There is no secret algorithm to beat. Search engines and social apps both reward the same thing: pages that people want, that load fast, and that other sites link to. What works:

- **Search (SEO).** People search for "reaction time test", "aim trainer", "CPS test", "memory test". Those are crowded, so aim at narrower phrases such as "reaction time test for gamers" or "average reaction time by age". Submit your sitemap to Google Search Console and Bing Webmaster Tools.
- **One page per game.** Right now the whole site is one page, which limits search traffic. Giving each game its own page and its own title and description is the biggest SEO upgrade available. Ask for this next.
- **Helpful content.** Short guides ("average reaction time by age", "how to improve your reaction time") that cite their sources, linked from the games.
- **Shareable results.** A "share my score" card makes every player an advertiser.
- **Short videos.** Challenge-style clips ("can you beat 200 ms?") on TikTok, YouTube Shorts and Instagram Reels send traffic fast if they take off.
- **Communities.** Post in gaming and productivity subreddits and Discord servers where it is allowed. Read each community's self-promotion rules first.
- **Speed and mobile.** Most visits come from phones. Keep pages fast.
- **Repeat visits.** Daily streaks and leaderboards give people a reason to come back.

Expect it to take months. Most new sites get very little traffic at first.

## 7. Making money, realistically

- **Donations** are simple and fit the privacy page, but usually bring in small amounts.
- **Ads** (for example Google AdSense) need steady traffic, original content, a privacy policy, and a cookie-consent banner in the UK and EU. Ads also track visitors, so the privacy text and the cookie banner must be updated before you switch them on. Earnings per visitor are low.
- **Paid extras** (a premium plan) mean payments, refunds and more rules. Leave this until the site has real users.

## 8. UK checklist (general information, not legal advice)

- **Data protection (UK GDPR).** With accounts on, you hold emails, usernames and scores. You need an accurate privacy notice, a way to delete an account on request, and you should check the ICO's free fee self-assessment at ico.org.uk.
- **Cookies and ads (PECR).** Essential storage needs no banner. Ads and analytics need consent first.
- **Children.** Games attract young people. The ICO's Children's Code may apply. The sign-up form asks users to confirm they are 13 or over. Think about whether you want to collect data from under-18s at all.
- **Online Safety Act.** Applies if users can post content to each other. Usernames and leaderboards are low risk, but adding chat or profile posts would add duties.
- **Tax.** The HMRC trading allowance covers up to 1,000 pounds a year of side income. Above that, register for Self Assessment.
- Have the Terms of Use (`reaction-test/terms.html`) and the privacy notice reviewed by a solicitor or a trusted template before you launch with accounts or ads.

## 9. Before you launch

- [ ] Name and domain chosen, and the site renamed
- [ ] `config.js` filled in
- [ ] `schema.sql` run, and a test account created
- [ ] Terms and privacy notice reviewed
- [ ] `robots.txt` and `sitemap.xml` updated to your domain
- [ ] Sitemap submitted to Google Search Console
- [ ] Tested on a real phone and a laptop
