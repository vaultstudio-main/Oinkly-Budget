# Default account artwork: plan

Drafted 2026-10-18. A separate, self-contained project: new default pictures for accounts and bills, in several styles and colours, generated with AI (Draw Things) and used in the app. It is meant to be run from its own prompt in its own session; the ready-to-paste prompt is at the end of this file. Nothing here is started.

## 1. Goal

Today every account without a photo gets a small illustration drawn in code on a coloured gradient. It is clean but there is only one picture per kind and one colour per group. The goal is richer defaults that feel like album covers: **several pictures per subject, several colour themes, and a way to pick one per account.** Photos the person adds themselves (a car, a house) stay exactly as they are.

## 2. How it works today (from the code, 2026-10-18)

- `Views/AccountArtwork.swift` draws the default in a SwiftUI `Canvas`: a gradient, two soft circles, a soft shadow and a flat white object. There are **17 kinds** (`ArtworkKind`): bank, savings, wallet, card, medical, house, car, boat, graduation, loan, briefcase, chart, retirement, crypto, gem, box, and bill.
- `AccountType.artworkKind` maps the **37 account types** to those 17 kinds (for example checking, money market and CD all show the bank).
- The colours come from the account's group (`AccountGroup`): checking and savings (teal to blue), credit cards (pink to purple), loans (orange to red), investments (green to teal), assets (blue to indigo). A bill with no account is orange.
- `AccountPicture` shows the person's own photo (`Account.photoData`, stored outside the database) when there is one, and otherwise the default.
- The default is shown in the account details card (150 by 100 points, 3:2), on account setup, on bills, and in the debug Testing window's "Default pictures" grid.
- The asset catalog is 7.2 MB today, almost all Help screenshots.

## 3. What to make

### 3.1 Subjects
Start from the 17 kinds and split where the account types differ in feel. Proposed list (about 28 subjects), each with **3 style variants**:

| Subject | Used for |
|---|---|
| Bank building | Checking |
| Money market | Money market |
| Certificate | Certificate of deposit |
| Piggy bank | Savings |
| Wallet | Cash on Hand |
| Phone with a coin | Payment app balance |
| Debit card | Prepaid / debit card |
| Credit card | Credit card |
| Shopping bag | Store card |
| Medical cross or heart | HSA, FSA, medical debt |
| House | Mortgage, real estate |
| House with a key | Home equity loan / HELOC |
| Car | Auto loan, vehicle |
| Boat, RV or motorcycle | Boat / RV / motorcycle loan |
| Graduation cap | Student loan |
| Books | 529 / education savings |
| Handshake or hands holding a coin | Personal loan, other loan |
| Open line of credit (a ribbon or loop) | Line of credit |
| Briefcase | Business loan, business asset |
| Rising chart | Brokerage, other investment |
| Nest with a golden egg | 401(k), IRAs, pensions, annuities |
| Nest egg | Pension, annuity |
| Abstract coin | Cryptocurrency (no brand logos) |
| Gem | Collectibles and valuables |
| Box | Other asset, other debt |
| Calendar or envelope | A bill with no account |

The implementing session should confirm or change this list with the owner before generating (see 9).

### 3.2 Variants (the "multiple options")
- **Style variants per subject:** 3 (for example a front view, an angled view, and a simpler icon-like view). The picker shows them side by side.
- **Colour themes:** 10 gradients the person can choose, drawn **in code behind the picture**, not baked into the AI image. This keeps the file count and app size small, and makes new colours free later.

| Theme | Colours (top to bottom) |
|---|---|
| Lagoon | teal to blue (today's checking and savings) |
| Bubblegum | pink to purple (today's cards) |
| Sunset | orange to red (today's loans) |
| Meadow | green to teal (today's investments) |
| Sky | light blue to indigo (today's assets) |
| Gold | amber to orange |
| Berry | magenta to plum |
| Mint | mint to sea green |
| Slate | grey to charcoal |
| Sand | cream to tan |

Each account starts with its group's theme (so nothing changes for existing accounts) and the person can change the style and the theme.

## 4. Art direction

- **One consistent look:** flat or lightly shaded illustration, soft rounded shapes, a single clear object centred in the frame, gentle shadow under it, friendly and calm. It should look like the current artwork's older sibling, not a different app.
- **3:2 landscape**, with the subject inside the middle 70 percent so any crop (details card, a small thumbnail) keeps it whole.
- **Readable small:** the picture is often shown at about 150 by 100 points and smaller in lists. Avoid fine detail and thin lines.
- **No text, letters or numbers, no logos or brand marks, no real people or faces, no currency symbols that could read as a specific country's money.**
- **Light and dark:** the picture sits on its own gradient, so it works in both. The object itself should be light or white so it reads on every theme.

## 5. How to generate them with Draw Things

Draw Things runs the models on this Mac. The implementing session should:

1. **Pick a model and style helper that is allowed for commercial use in an App Store app.** Check the licence of every model and LoRA before using it, and record it in `docs/artwork-licences.md` (name, version, licence, link, date checked). As a guide: SDXL and Flux Schnell are generally usable commercially; Flux Dev is not. Do not rely on this summary; read each licence.
2. **Make the images as cut-outs.** Generate each subject on a plain flat background, then remove the background (Draw Things can run a background-removal step, or use the macOS Vision cut-out in a small script) and save as a transparent PNG. The gradient colour themes come from code.
3. **Fix the look first.** Make one subject (the piggy bank), tune the prompt, negative prompt, size, steps, guidance and sampler until it matches section 4, then keep those settings for every subject. Save the settings in the licences file so a later run can match.
4. **Batch.** Draw Things has an optional local API server (A1111-style `/sdapi/v1/txt2img`) and a scripting feature. A script can loop over subjects and variants, change the seed, and write files with a fixed naming pattern. Verify which Draw Things version and settings expose this before relying on it; fall back to generating by hand in the app.
5. **Review.** Generate several candidates per variant (for example 8), then choose the best by eye. Keep the rejects out of the repository.
6. **Prompt template (to refine):** `flat vector illustration of a {subject}, centered, soft rounded shapes, simple shading, white and light grey object, clean plain background, 3:2 composition, no text, no logo` with a negative prompt such as `text, letters, numbers, watermark, logo, brand, person, face, hands, photo, realistic, clutter, border, frame`.

## 6. Processing and file budget

- Final size: **900 by 600 pixels** (shown at 2x for 450 by 300 points; the details card is 150 by 100 points), transparent PNG or lossless HEIC, whichever the asset catalog and rendering handle better. Compress each to **under 120 KB** if possible.
- Count: about 26 subjects x 3 variants = **78 files**, roughly **6 to 9 MB**. That is a small addition to the app. If the files come out much bigger, reduce to 2 variants for the less common subjects.
- Naming: `Artwork-{subject}-{variant}` for example `Artwork-piggybank-2`, in an asset catalog folder named `Artwork`. A manifest `artwork.json` (or Swift code) lists subjects, variants and which account types use which subject.

## 7. Changes in the app

1. **A catalogue.** A small type that knows the subjects, the variants, the themes, and which subject each account type uses by default.
2. **Drawing.** `AccountArtwork` shows the chosen cut-out on the chosen gradient. If an image is missing, it falls back to today's drawn object, so nothing ever looks empty.
3. **Choosing.** In the account edit screen, under the photo: **Picture**, with choices **My photo** or **Default picture**, and for a default picture a grid of the style variants and a row of colour swatches. The same for bills.
4. **Storing the choice.** This needs one new stored text field with a default, for example `defaultArtwork` on `Account` (and on `Bill`), holding something like `piggybank-2-meadow`. **This is a database field.** V2 has not left the owner's Mac yet, so it can still be added to V2 without a V3, but only before V2 goes to TestFlight or the store. The implementing session must check this first and, if V2 has shipped, add a V3 with a tested migration instead (see `data-integrity-plan.md`). It must also go into the backup file as an optional field.
5. **Everywhere it shows.** Account details, setup, bills, the Planning cards, the debug Testing grid (replace its sample list with the new subjects).
6. **Accessibility.** The pictures stay decorative (hidden from VoiceOver), as today. The colour theme and style pickers need clear names for VoiceOver.
7. **Performance.** Load images lazily and cache the decoded image. The register and Summary must not slow down.
8. **Docs.** `feature-master-list-1.0.md` (a new entry, which also drives Help, screenshots, the website and the release notes), plus new shots for the picker.

## 8. Order of work

| Phase | Work | Output |
|---|---|---|
| 1. Decide | Confirm subjects, variants per subject, themes and the storage field with the owner. Check licences. | A signed-off list and `artwork-licences.md` |
| 2. Pilot | Make the piggy bank in all 3 variants. Tune until it matches section 4. Show the owner. | Approved look and settings |
| 3. Batch | Generate, review and process every subject. | The image set and the manifest |
| 4. App | Catalogue, drawing, picker, stored field and backup. | Working in the app |
| 5. Test | Every account type, every theme, light and dark, small sizes, missing image fallback, backup and restore of the choice, an existing account's picture unchanged. | Checklist signed off |
| 6. Docs and shots | Master list, Help, screenshots, release notes. | Updated documents |

Rough effort: 1 to 2 days of generation and review (mostly choosing among candidates), 2 to 3 days of app work, 1 day of testing and docs.

## 9. Decisions for the owner

1. The subject list in 3.1: keep, add or remove subjects.
2. Variants per subject: 3 (recommended) or fewer or more.
3. Colour themes: the 10 in 3.2, or a different set.
4. Cut-outs on code-drawn gradients (recommended: small, flexible) or full pictures with baked colours (more files, more control over the look).
5. Whether bills get the same picker.
6. Whether the new defaults replace today's drawn artwork for existing accounts automatically (recommended: yes, same colours, so they look similar but nicer) or only for new ones.
7. Whether to say in the release notes that the default pictures were made with AI (no rule is known that requires it for the App Store, but check the current guidelines at the time).

## 10. Risks

- **Licences.** An unsuitable model or LoRA licence would block shipping. Check first.
- **Consistency.** AI images vary. The pilot phase and the fixed settings exist to prevent a patchwork. If it can't be made consistent, fall back to fewer subjects.
- **Review.** Reject anything with text, a logo, a person or an odd artefact.
- **Database field.** Do not add it after V2 ships without a migration.
- **App size and speed.** Keep within the budget in section 6.

## 11. Prompt to start the project (paste into a new session)

```text
You are helping with Oinkly Budget (formerly code-named Piggybank), a Mac-only SwiftUI and SwiftData personal finance app, repository at /Users/dstibich/Documents/Code_Bank/Piggybank. The 1.0 work is on branch main. Do not touch main. Create a new branch from main called default-artwork and work there, committing only when I say yes.

Your job: carry out docs/default-account-artwork-plan.md. Read it first, then read docs/feature-master-list-1.0.md, OinklyBudget/OinklyBudget/Views/AccountArtwork.swift (today's code-drawn default pictures), docs/data-integrity-plan.md and docs/accessibility-audit.md.

Goal: replace the single code-drawn default picture per account kind with AI-generated artwork made in Draw Things on this Mac: about 26 subjects, 3 style variants each, as transparent 900x600 cut-outs, shown on one of 10 code-drawn colour-theme gradients, with a picker in the account edit screen. People's own photos must keep working exactly as today.

Rules:
1. Work in phases (plan section 8) and stop at the end of Phase 1 and Phase 2 to show me the subject list, the licences and the pilot piggy bank before generating anything else. Ask me the decisions in plan section 9 one short question at a time, with options.
2. Check the licence of every model and LoRA for commercial App Store use and record each in docs/artwork-licences.md before using it. If you are unsure, say so and ask.
3. No text, logos, brand marks, people or faces in any image. Keep each final image under about 120 KB and the whole set under about 10 MB.
4. The choice of picture needs a new stored field with a default (for example defaultArtwork on Account and Bill). Before adding it, check whether database schema V2 (Models/SchemaVersions.swift) has left my Mac. I have not shipped it; if that is still true, add the field to V2, otherwise stop and tell me. Add it to the backup file as an optional field (Logic/DataBackup.swift).
5. Keep the app building and the existing tests and data safe. The debug Testing window (Oinkly Budget > Testing) fills the app with test data; use it to check every account type, light and dark, and the fallback when an image is missing. Do not run Fill with Test Data against any real data.
6. Update docs/feature-master-list-1.0.md, and add screenshots to the shot register, when the feature works.
7. Write plain, short sentences. Report outcomes faithfully, including anything you could not verify.

Start with Phase 1: read the files, then propose the subject list, variants and themes, and ask me the decisions.
```
