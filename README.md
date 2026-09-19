# 🌿 plantid.sh — Multilingual Plant & Pesticide Identifier

**🇮🇳 India Edition v3.0** • Identify plants, crops, vegetables, pesticides, and packaged products from a NAME (any of the 22 scheduled Indian languages), a BARCODE, or a PHOTO.

---

## 📦 What's in this package

```
plantid.sh          # The script (executable, single-file, no install needed)
README.md           # This file
requirements.txt    # List of dependencies (system + optional)
```

---

## 🚀 Quick Start (3 steps)

### 1. Download
Save `plantid.sh` to any folder on your Linux machine, e.g. `~/plantid/`.

### 2. Make it executable
```bash
chmod +x plantid.sh
```

### 3. Run it
```bash
./plantid.sh
```

You'll see the interactive menu:
```
🌿 plantid.sh — Multilingual Plant & Pesticide Identifier
   🇮🇳 India Edition v3.0 • 2026-09-19 08:50:00

What would you like to identify?

  1) 🌱  A plant / crop by NAME         (any Indian language)
  2) 🧪  A PESTICIDE / agrochemical    (brand → ingredient)
  3) 📦  A packaged product by BARCODE
  4) 📷  A plant PHOTO  (or a photo containing a barcode)

Type "q" / "quit" / "exit" at any prompt to leave.

Pick 1/2/3/4  (h = help, q = quit):
```

---

## 🇮🇳 Indian APIs (no American services)

This script deliberately avoids all American APIs. Every lookup goes through an Indian service, a non-American non-profit, or Wikimedia projects authored by Indian contributor communities:

| Lookup path | Service used | Why it's Indian / non-American |
|---|---|---|
| Plant / crop name | **Indic Wikipedia** (`te.wikipedia.org`, `hi.wikipedia.org`, `ta.wikipedia.org`, …) | Per-language Wikimedia projects authored primarily by Indian contributor communities in their native scripts. |
| UI string translation | **AI4Bharat Bhashini** — `https://bhashini.gov.in` | The Government of India's National Language Translation Mission, run by MeitY. |
| Pesticide brand → active ingredient | Built-in static table of ~60 common Indian brands (Rallis, Bayer, Dhanuka, UPL, Crystal, etc.) | No external service — pure local lookup. |
| Barcode lookup | **GS1 India SmartSearch** (`https://smartsearch.gs1india.org`) → **Open Food Facts** (French non-profit) | GS1 India is the Indian government-backed barcode registry. Open Food Facts is a French non-profit with strong Indian product coverage. UPCitemdb (American) has been REMOVED. |
| Plant photo identification | **Pl@ntNet** (`https://plantnet.org`) | A French research organization (CIRAD + INRAE + INRIA + IRD). Non-American; the only fallback when no Indian service offers public image classification. |

### Static transliteration table (offline fallback)

When both Bhashini and `translate-shell` are unreachable from your network, the script falls back to a built-in table of ~100 common Indian agricultural terms across all 22 scripts. So `ಟಮಾಟೊ` (Kannada), `ટમેટો` (Gujarati), `मिर्च` (Hindi), `ഇഞ്ചി` (Malayalam), etc. all resolve to the correct English Wikipedia article even with no translation service available.

---

## 📋 Usage

### Interactive mode (no arguments)
```bash
./plantid.sh
```
Pick 1/2/3/4 from the menu. The script **loops until you type `q`/`quit`/`exit`** at any prompt — so you can identify multiple things in one session without restarting.

### Direct CLI mode
```bash
./plantid.sh --name "தக்காளி"              # Tamil name (auto-detected)
./plantid.sh --name "टमाटर" --lang mr      # Force Marathi output
./plantid.sh --name "Tata Rallis Rilon"    # Pesticide brand → AI
./plantid.sh --barcode 8901234567890       # Indian EAN-13 (890 = India)
./plantid.sh --photo leaf.jpg               # Plant photo or photo of a barcode
```

### Logs & history
```bash
./plantid.sh --log                          # Aligned colour table of last 10 matches
./plantid.sh --log-html                     # Open the HTML log in your browser
./plantid.sh --help                         # Full help
```

### Environment overrides
```bash
PLANTID_CONF=/path/to/conf  ./plantid.sh   # Custom config file path
PLANTID_DEBUG=1              ./plantid.sh   # Verbose debug on stderr
```

---

## 🌱 The 22 Scheduled Indian Languages

Auto-detected from the Unicode block of the first non-ASCII character you type. Override with `--lang <code>`:

| Code | Language | Endonym | Script |
|---|---|---|---|
| `hi` | Hindi | हिन्दी | Devanagari |
| `bn` | Bengali | বাংলা | Bengali |
| `te` | Telugu | తెలుగు | Telugu |
| `mr` | Marathi | मराठी | Devanagari |
| `ta` | Tamil | தமிழ் | Tamil |
| `gu` | Gujarati | ગુજરાતી | Gujarati |
| `ur` | Urdu | اُردُو | Arabic |
| `kn` | Kannada | ಕನ್ನಡ | Kannada |
| `or` | Odia | ଓଡ଼ିଆ | Odia |
| `ml` | Malayalam | മലയാളം | Malayalam |
| `pa` | Punjabi | ਪੰਜਾਬੀ | Gurmukhi |
| `as` | Assamese | অসমীয়া | Bengali |
| `mai` | Maithili | मैथिली | Devanagari |
| `sa` | Sanskrit | संस्कृतम् | Devanagari |
| `ne` | Nepali | नेपाली | Devanagari |
| `kok` | Konkani | कोंकणी | Devanagari |
| `sd` | Sindhi | سنڌي | Arabic |
| `mni` | Manipuri | ꯃꯩꯇꯩꯔꯛ꯫ | Meitei Mayek |
| `brx` | Bodo | बड़ो | Devanagari |
| `doi` | Dogri | डोगरी | Devanagari |
| `sat` | Santali | ᱥᱟᱱᱛᱟᱞ | Ol Chiki |
| `ks` | Kashmiri | كٲشُر | Arabic |

---

## 🧪 Pesticide Mode (Option 2)

Wikipedia rarely has articles on pesticide **brand names** like "Tata Rallis Rilon" — but it usually has articles on the manufacturer ("Rallis India") and on the active ingredient ("Chlorantraniliprole"). The pesticide mode uses this fallback chain:

1. **Strip pesticide descriptors** — Insecticide / Fungicide / Herbicide / Pesticide / SC / EC / WG / GR
2. **Look up the brand in a static table** of ~60 well-known Indian brands → active ingredient
3. **Look up the active ingredient on Wikipedia** — returns the scientific compound article
4. **Fallback: try each word as a manufacturer name** — e.g., "Rallis" → "Rallis India"

### Examples that work out of the box:

| Brand input | Resolves to |
|---|---|
| `Tata Rallis Rilon` | Chlorantraniliprole |
| `Confidor Insecticide` | Imidacloprid |
| `Bavistin Fungicide` | Carbendazim |
| `Rallis Coragen` | Chlorantraniliprole |
| `Tata TAKUMI` | Buprofezin |
| `Tilt Propiconazole` | Propiconazole |

### Adding your own pesticide brands

Open `plantid.sh`, find the `PESTICIDE_BRAND_TO_AI` associative array, and add a 1-line entry:

```bash
[mybrand]="Active Ingredient Name"
```

Save the file and you're done — no other change needed.

---

## 📊 Logging

Every match is appended to three persistent files in the same folder as the script:

| File | Purpose |
|---|---|
| `plantid_log.html` | Self-contained HTML log with the matched image embedded as base64 — opens in any browser, fully offline-viewable. |
| `plantid_log.csv` | Timestamp, input type, input value, language, matched name, confidence, source API, image path, status. |
| `matched_images/` | Downloaded thumbnail images named by language + timestamp. |

Use `./plantid.sh --log` for an aligned colour table of the last 10 entries. Use `./plantid.sh --log-html` to open the HTML log in your browser.

---

## ⚙️ Dependencies

### Mandatory (the script will refuse to run without these)
- **`curl`** — HTTP client for all API calls
- **`jq`** — JSON parsing
- **`bash` 4.0+** — for associative arrays (`declare -A`)

### Recommended (makes everything work better)
- **`python3`** — for HTML escaping, sentence deduplication, regex-based descriptor stripping
- **`chafa`** — render matched images inline in the terminal (sudo apt install chafa)
- **`zbar-tools`** — detect a barcode inside a photo (sudo apt install zbar-tools)

### Optional (used only as translation fallbacks)
- **`translate-shell`** — the `trans` command, used if Bhashini is unreachable on your network (sudo apt install translate-shell)

### Pl@ntNet API key (only for photo identification)
If you want to use photo mode (option 4), get a free key at https://my.plantnet.org/account/ and create a `plantid.conf` file in the same folder as the script:

```bash
echo 'PLANTNET_API_KEY=your_key_here' > plantid.conf
chmod 600 plantid.conf   # protect the key
```

See `requirements.txt` for the exact install commands on Debian/Ubuntu.

---

## 🛠️ Installation on Debian / Ubuntu

```bash
sudo apt update
sudo apt install -y curl jq python3 chafa zbar-tools
# Optional:
sudo apt install -y translate-shell

# Place the script
mkdir -p ~/plantid
cp plantid.sh ~/plantid/
cd ~/plantid
chmod +x plantid.sh
./plantid.sh
```

### Installation on Fedora / RHEL / CentOS
```bash
sudo dnf install -y curl jq python3 chafa zbar translate-shell
```

### Installation on Arch Linux
```bash
sudo pacman -S --needed curl jq python chafa zbar translate-shell
```

### Installation on macOS (Homebrew)
```bash
brew install curl jq python3 chafa zbar translate-shell
```

---

## 🎯 Example Sessions

### Example 1 — Telugu plant name
```bash
./plantid.sh --name "టమోటా" --lang te
```
Output:
```
╭──────────────────────────────────────────────────────────────╮
│ 📝 NAME Mode • Telugu                                    │
╰──────────────────────────────────────────────────────────────╯
==> Auto-detected language Telugu (తెలుగు) — script: Telugu, code: te
  🍅 ⠋ [█░░░░░░░░░░░░░░░░░]   5%  Searching … (0s)
==> 🍅  సరిపోలిక కనుగొనబడింది: టమాటో
🖼️  image: ./matched_images/name_te_1789807837.jpg
────────────────────────────────────────────────────────────────────────
టమాటో సొలనేసి కుటుంబములో జేరిన యొక విదేశీయపు కాయగూరజాతి ...
────────────────────────────────────────────────────────────────────────
✅ ok      నమోదు చేయబడింది
```

### Example 2 — Pesticide brand
```bash
./plantid.sh --name "Tata Rallis Rilon"
```
Output:
```
╭──────────────────────────────────────────────────────────────╮
│ 📝 NAME Mode • English                                   │
╰──────────────────────────────────────────────────────────────╯
==> Input language: English (ASCII), code: en
  🍅 ⠋ [█░░░░░░░░░░░░░░░░░]   5%  Searching … (1s)
==> 🔍  Looking deeper…
  🧪 ⠙ [██████░░░░░░░░░░░░] 33%  Resolving brand… (0s)
==> 🌱  Match found: Chlorantraniliprole
🖼️  image: ./matched_images/name_en_1789807848.jpg
────────────────────────────────────────────────────────────────────────
🏷️  Brand: Tata Rallis Rilon  →  Active ingredient: Chlorantraniliprole

Chlorantraniliprole is an insecticide of the diamide class used for
insects found on fruit and vegetable crops as well as ornamental plants.
────────────────────────────────────────────────────────────────────────
✅ ok      logged.
```

### Example 3 — Barcode (Indian product)
```bash
./plantid.sh --barcode 8901234567890
```

---

## 🐛 Troubleshooting

### The spinner/loader bar doesn't appear
Make sure you're running the script in a real terminal (not piped). The spinner is silenced when stdout is not a TTY.

### A specific Indic language returns "No match found"
Some Indic Wikipedias have gaps in their coverage (e.g., Kannada Wikipedia has no tomato article). The script automatically falls back to the English Wikipedia article via a static transliteration table for ~100 common crops. To add a new term:

1. Open `plantid.sh`
2. Find `INDIC_TO_EN_CROP` (a `declare -A` line near the top of the file)
3. Add an entry like `["your_term_here"]="English Wikipedia title"`
4. Save and re-run

### Bhashini is unreachable on my network
The script will silently fall back to the static transliteration table. For UI strings, it falls back to English. No error will appear — this is by design.

### Photo mode returns "Plant identification key not configured"
Create a `plantid.conf` file with your free Pl@ntNet API key (see the "Pl@ntNet API key" section above).

### The script exits silently with no error
This was a `set -e` bug in earlier versions (v2.0) that has been fixed in v3.0. Make sure you're running v3.0 or later — check the first line of `./plantid.sh --help` for the version number.

---

## 📜 Exit Codes

| Code | Meaning |
|---|---|
| 0 | Match found |
| 1 | No match found |
| 2 | API / network error |
| 3 | Bad input (invalid barcode, missing file, unknown --lang, etc.) |

---

## 📄 License

This script is released into the public domain. No warranty. Use at your own risk.

The Indian APIs it calls (Bhashini, GS1 India, Wikimedia) have their own terms of use — please respect them.

---

## 🙏 Acknowledgements

- **AI4Bharat / Bhashini** — MeitY, Govt of India, for the National Language Translation Mission.
- **Wikimedia India contributor communities** — for building the Indic-language Wikipedia editions.
- **GS1 India** — for the public barcode registry.
- **Open Food Facts** — for the Indian product database.
- **Pl@ntNet** — for the plant identification API.
- **chafa** — for inline terminal image rendering.
