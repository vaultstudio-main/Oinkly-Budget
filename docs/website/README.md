# Website draft

A small static site for the domain. No build step and no dependencies: upload this folder as it is to any static host
(GitHub Pages, Netlify, Cloudflare Pages, or a web host).

| File | What it is |
|---|---|
| `index.html` | Home page and project list (add new apps as cards here) |
| `piggybank.html` | Piggybank Financial product page |
| `about.html` | About Vault Studio (hobbyist studio, no personal details). Photo is `images/profile-square.jpg` (square crop of `profile.jpeg`) |
| `support.html` | Support page (use this URL as the Support URL in App Store Connect) |
| `privacy.html` | Privacy policy (use this URL as the Privacy Policy URL in App Store Connect) |
| `style.css` | Shared look, follows light and dark mode |
| `images/` | App icon and screenshots (resized to 1600 px wide) |

## Already filled in
- Studio name: **Vault Studio**. Domain: **vaultstudio.dev**. Support email: **support@vaultstudio.dev**
  (create this address or forward it before launch, otherwise mail to it will bounce).
- Canonical links, `sitemap.xml` and `robots.txt` use `https://vaultstudio.dev`.

## Still to do before publishing
- The About page text is deliberately impersonal (a hobbyist studio, no name or location). The profile picture is
  `images/profile-square.jpg`, a 400 px square crop of `images/profile.jpeg`. To change the photo, replace
  `profile.jpeg` and make a new square crop.
- "Coming soon to the Mac App Store" on `index.html` and `piggybank.html`: when the app is live, swap each
  `<span class="button soon">` for `<a class="button" href="YOUR APP STORE LINK">Get it on the Mac App Store</a>`, and
  change the "Coming soon for Mac" badge on `index.html` to "Now available for Mac".
- The Windows "coming soon" lines on both pages: remove or change them if the Windows plan is dropped
  (`piggybank-windows/PLAN.md`).
- Optional: an `og:image` preview picture and a favicon at several sizes.

## Adding another project later
Copy the Piggybank card on `index.html`, give it its own page (copy `piggybank.html`) and add it to the nav in each
page's header and footer. Each app should have its own support and privacy page, or point to shared ones.

## Keep it honest
The privacy page says the app collects nothing and makes no network connections. That is true today. If a future
version adds anything that sends data (sync, analytics, crash reports, update checks), update `privacy.html`, the App
Privacy answers in App Store Connect, and `Piggybank/PrivacyInfo.xcprivacy` together.
