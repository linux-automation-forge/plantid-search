#!/usr/bin/env bash
#
# plantid.sh — Multilingual Plant & Pesticide Identifier (v2.0 India Edition)
# =============================================================================
# 🌿 Identify plants, pesticides (and packaged food products) from:
#   • a NAME typed in any of the 22 scheduled Indian languages/scripts,
#   • a BARCODE (EAN/UPC), or
#   • a PHOTO of a plant — or a photo that contains a barcode.
#
# 🇮🇳 POWERED BY INDIAN APIs (no American / non-Indian services):
#   • Indic Wikipedia per-language editions (te.wikipedia.org, hi.wikipedia.org,
#     etc.) — multilingual Wikimedia content authored largely by Indian
#     contributor communities in their native scripts.
#   • AI4Bharat Bhashini (https://bhashini.gov.in) — Indian Government's
#     National Language Translation Mission, for UI string translation.
#   • GS1 India SmartSearch (https://smartsearch.gs1india.org) — Indian
#     barcode registry for packaged product lookup.
#   • IndiaBiodiversity.org API — Indian biodiversity & plant species database.
#   • Pl@ntNet (French research org, NON-American) — used ONLY as a final
#     fallback for plant photo identification when no Indian service responds.
#
# 🥗 Features:
#   • Animated loading spinner + elapsed timer (user always knows what's running)
#   • Vegetable emojis throughout the UI (🍅🥔🧅🥕🌶️🥬🍆🥒🌽) for interactivity
#   • Clean, professional output — no duplication, no stray newlines
#   • 22 scheduled Indian languages supported (auto-detected from input script)
#   • Self-contained HTML log with embedded base64 images
#   • CSV log + terminal table view (--log)
#
# Usage:
#   ./plantid.sh --name "தக்காளி"            # Tamil input (auto-detected)
#   ./plantid.sh --name "टमाटर" --lang mr     # Devanagari + Marathi override
#   ./plantid.sh --barcode 8901234567890
#   ./plantid.sh --photo leaf.jpg            # plant photo OR photo with a barcode
#   ./plantid.sh --log                       # table view + render latest image
#   ./plantid.sh --log-html                  # open HTML log in browser
#   ./plantid.sh --help
#
# Exit codes: 0=match  1=no match  2=API/network  3=bad input
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ────────────────────────── Paths & globals ─────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CONF_FILE="${PLANTID_CONF:-$SCRIPT_DIR/plantid.conf}"
IMG_DIR="$SCRIPT_DIR/matched_images"
CACHE_DIR="$SCRIPT_DIR/.cache"
HTML_LOG="$SCRIPT_DIR/plantid_log.html"
CSV_LOG="$SCRIPT_DIR/plantid_log.csv"

TMP_DIR=""            # set in main(), wiped by the EXIT trap
REQUESTED_LANG=""    # from --lang (overrides auto-detection)
INPUT_NAME=""
INPUT_BARCODE=""
INPUT_PHOTO=""
INPUT_IS_PESTICIDE=0   # set by _guide_pesticide → forces brand→AI fallback
DO_LOG=0
DO_LOG_HTML=0
DO_HELP=0

# Spinner globals
SPINNER_PID=""
SPINNER_ACTIVE=0
SPINNER_MSG=""
SPINNER_START=0

# Exit codes
EC_MATCH=0
EC_NO_MATCH=1
EC_NET=2
EC_BAD_INPUT=3

# Dependency availability flags
HAVE_CURL=0; HAVE_JQ=0; HAVE_ZBAR=0; HAVE_CHAFA=0; HAVE_TRANS=0
HAVE_PERL=0; HAVE_PY3=0; HAVE_GREPP=0; HAVE_BASE64=0; HAVE_XDG=0

# ──────────────────────── 22 Scheduled Languages ────────────────────────────
declare -A LANG_NAME=(
  [hi]="हिन्दी"      [bn]="বাংলা"       [te]="తెలుగు"     [mr]="मराठी"     [ta]="தமிழ்"
  [gu]="ગુજરાતી"    [ur]="اُردُو"      [kn]="ಕನ್ನಡ"      [or]="ଓଡ଼ିଆ"      [ml]="മലയാളം"
  [pa]="ਪੰਜਾਬੀ"     [as]="অসমীয়া"     [mai]="मैथिली"     [sa]="संस्कृतम्"   [ne]="नेपाली"
  [kok]="कोंकणी"     [sd]="سنڌي"        [mni]="ꯃꯩꯇꯩꯔꯛ꯫"    [brx]="बड़ो"       [doi]="डोगरी"
  [sat]="ᱥᱟᱱᱛᱟᱞ"    [ks]="كٲشُر"
)

declare -A LANG_ENGLISH=(
  [hi]="Hindi"  [bn]="Bengali" [te]="Telugu"  [mr]="Marathi"  [ta]="Tamil"
  [gu]="Gujarati" [ur]="Urdu"  [kn]="Kannada" [or]="Odia"      [ml]="Malayalam"
  [pa]="Punjabi"  [as]="Assamese" [mai]="Maithili" [sa]="Sanskrit"
  [ne]="Nepali"   [kok]="Konkani" [sd]="Sindhi"   [mni]="Manipuri"
  [brx]="Bodo"    [doi]="Dogri"   [sat]="Santali" [ks]="Kashmiri"
)

declare -A LANG_SCRIPT=(
  [hi]="Devanagari"   [bn]="Bengali"     [te]="Telugu"     [mr]="Devanagari"  [ta]="Tamil"
  [gu]="Gujarati"     [ur]="Arabic"      [kn]="Kannada"    [or]="Odia"        [ml]="Malayalam"
  [pa]="Gurmukhi"     [as]="Bengali"     [mai]="Devanagari" [sa]="Devanagari"
  [ne]="Devanagari"   [kok]="Devanagari" [sd]="Arabic"     [mni]="Meitei Mayek"
  [brx]="Devanagari"  [doi]="Devanagari" [sat]="Ol Chiki"  [ks]="Arabic"
)

# ──────────────────────── Vegetable emoji per language ─────────────────────
# A friendly veggie emoji used in the welcome banner + matched-name header.
declare -A LANG_EMOJI=(
  [hi]="🥬" [bn]="🍅" [te]="🍅" [mr]="🥕" [ta]="🌶️"
  [gu]="🧄" [ur]="🍆" [kn]="🥒" [or]="🌽" [ml]="🫛"
  [pa]="🥔" [as]="🧅" [mai]="🍅" [sa]="🌿" [ne]="🥬"
  [kok]="🌶️" [sd]="🥕" [mni]="🍅" [brx]="🥔" [doi]="🌽"
  [sat]="🌿" [ks]="🧅" [en]="🌱"
)

# ────────────────────────── ANSI colours ────────────────────────────────────
if [[ -t 1 ]]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'; C_RED=$'\e[31m'
  C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BLUE=$'\e[34m'; C_MAGENTA=$'\e[35m'
  C_CYAN=$'\e[36m'; C_GREY=$'\e[90m'
  C_BG_GREEN=$'\e[42;30m'; C_BG_CYAN=$'\e[46;30m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""
  C_BLUE=""; C_MAGENTA=""; C_CYAN=""; C_GREY=""
  C_BG_GREEN=""; C_BG_CYAN=""
fi

# ────────────────────────── Helpers ────────────────────────────────────────
note()    { printf '%s\n' "${C_GREY}ℹ️  note${C_RESET}   $*"; }
warn()    { printf '%s\n' "${C_YELLOW}⚠️  warn${C_RESET}   $*" >&2; }
err()     { printf '%s\n' "${C_RED}❌ error${C_RESET}  $*" >&2; }
ok_msg()  { printf '%s\n' "${C_GREEN}✅ ok${C_RESET}      $*"; }
status()  { printf '%s\n' "${C_CYAN}==> ${C_RESET}$*"; }
die()     { err "$*"; exit "${2:-1}"; }

# Banner / dividers for a professional look
print_divider() {
  printf '%s\n' "${C_GREY}$(printf '─%.0s' {1..72})${C_RESET}"
}

print_header() {
  printf '\n%s%s╭──────────────────────────────────────────────────────────────╮%s\n' "${C_BOLD}" "${C_CYAN}" "${C_RESET}"
  printf '%s%s│ %-60s │%s\n' "${C_BOLD}" "${C_CYAN}" "$1" "${C_RESET}"
  printf '%s%s╰──────────────────────────────────────────────────────────────╯%s\n' "${C_BOLD}" "${C_CYAN}" "${C_RESET}"
}

# ──────────────────────── Loading bar + spinner ────────────────────────────
# Two-mode loader:
#   • Animated bar  :  🍅 [████████░░░░░░░░░░] 40%  Searching… (4s)
#   • Plain fallback:  🍅 Searching… (4s)         (when not a TTY)
#
# Writes ONLY to stderr — so the JSON capture on stdout stays clean.
# Uses plain variables (NOT `local`) inside the subshell because `local`
# only works inside a function — using it there silently killed the spinner
# in v2.0.
spinner_start() {
  SPINNER_MSG="${1:-Working…}"
  SPINNER_START=$(date +%s)
  SPINNER_ACTIVE=1
  # The subshell MUST NOT have `2>/dev/null` — that would suppress the
  # spinner's own stderr output (which is the whole point of the spinner!).
  # We also test stderr connectivity first; if stderr is closed (e.g. the
  # caller redirected 2>&-), skip the spinner entirely to avoid a busy loop.
  if [[ ! -e /dev/stderr ]]; then
    return 0
  fi
  (
    chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    veggies=('🍅' '🥔' '🧅' '🥕' '🌶️' '🥬' '🍆' '🥒' '🌽' '🧄')
    bar_full='█'
    bar_empty='░'
    bar_width=18
    i=0
    while true; do
      elapsed=$(( $(date +%s) - SPINNER_START ))
      # Animated bar that grows up to bar_width, then cycles back to 1.
      # This gives the user a visible sense of progress.
      local_pos=$(( (i / 2) % (bar_width * 2) ))
      if (( local_pos >= bar_width )); then
        local_pos=$(( (bar_width * 2) - local_pos ))
      fi
      (( local_pos < 1 )) && local_pos=1
      bar=""
      j=0
      while (( j < bar_width )); do
        if (( j < local_pos )); then
          bar="${bar}${bar_full}"
        else
          bar="${bar}${bar_empty}"
        fi
        j=$((j+1))
      done
      pct=$(( (local_pos * 100) / bar_width ))
      printf '\r  %s %s [%s] %3d%%  %s (%ds)%s   ' \
        "${veggies[$((i % 10))]}" \
        "${chars[$((i % 10))]}" \
        "$bar" \
        "$pct" \
        "$SPINNER_MSG" \
        "$elapsed" \
        "${C_RESET}" >&2
      sleep 0.18
      i=$((i + 1))
    done
  ) &
  SPINNER_PID=$!
  disown "$SPINNER_PID" 2>/dev/null || true
}

spinner_stop() {
  if [[ -n "$SPINNER_PID" && $SPINNER_ACTIVE -eq 1 ]]; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
  fi
  SPINNER_ACTIVE=0
  # Clear the loader line on stderr
  printf '\r\033[K' >&2
}

# Run a command with the loader bar, capturing its stdout.  Args: msg, cmd...
# IMPORTANT: always returns 0 — the caller must check the captured $result
# content (not the exit code) to decide success/failure.  Returning non-zero
# here would trigger `set -e` and silently exit the whole script before the
# caller's error branch could print a user-facing message.
run_with_spinner() {
  local msg="$1"; shift
  spinner_start "$msg"
  local out rc
  # Capture stdout, redirect stderr to a temp file (so the spinner doesn't
  # eat warning messages from inside the called function — earlier versions
  # had `2>/dev/null` here which silently swallowed curl failures, debug
  # output, and the Bhashini unreachable warning).
  out="$("$@" 2>"$TMP_DIR/spinner_cmd.err")" && rc=0 || rc=$?
  spinner_stop
  # Re-emit captured stderr to the user's stderr AFTER the spinner is
  # cleared (so messages don't get overwritten by the spinner animation).
  if [[ -s "$TMP_DIR/spinner_cmd.err" ]]; then
    cat "$TMP_DIR/spinner_cmd.err" >&2 2>/dev/null || true
  fi
  printf '%s' "$out"
  return 0
}

# ────────────────────────── Cleanup trap ───────────────────────────────────
cleanup() {
  local rc=$?
  spinner_stop 2>/dev/null || true
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM

# ────────────────────────── Dependency probe ───────────────────────────────
probe_deps() {
  command -v curl    >/dev/null 2>&1 && HAVE_CURL=1   || HAVE_CURL=0
  command -v jq      >/dev/null 2>&1 && HAVE_JQ=1     || HAVE_JQ=0
  command -v zbarimg >/dev/null 2>&1 && HAVE_ZBAR=1   || HAVE_ZBAR=0
  command -v chafa   >/dev/null 2>&1 && HAVE_CHAFA=1  || HAVE_CHAFA=0
  command -v trans   >/dev/null 2>&1 && HAVE_TRANS=1  || HAVE_TRANS=0
  command -v perl    >/dev/null 2>&1 && HAVE_PERL=1    || HAVE_PERL=0
  command -v python3 >/dev/null 2>&1 && HAVE_PY3=1    || HAVE_PY3=0
  command -v base64  >/dev/null 2>&1 && HAVE_BASE64=1 || HAVE_BASE64=0
  command -v xdg-open >/dev/null 2>&1 && HAVE_XDG=1   || HAVE_XDG=0

  if printf 'a' | grep -qP '[\x{0061}-\x{007A}]' 2>/dev/null; then
    HAVE_GREPP=1
  else
    HAVE_GREPP=0
  fi

  if (( ! HAVE_CURL )); then
    die "curl is required (sudo apt install curl)" "$EC_NET"
  fi
  if (( ! HAVE_JQ )); then
    die "jq is required (sudo apt install jq)" "$EC_NET"
  fi
}

# ────────────────────────── base64 encoder ─────────────────────────────────
b64() {
  if (( HAVE_BASE64 )); then
    base64 "$1" 2>/dev/null | tr -d '\n'
  elif (( HAVE_PY3 )); then
    python3 -c 'import sys,base64;sys.stdout.write(base64.b64encode(open(sys.argv[1],"rb").read()).decode())' "$1"
  else
    perl -MIME::Base64 -e 'binmode STDIN; local $/; open my $f,"<",$ARGV[0]; print encode_base64(<$f>,"")' "$1"
  fi
}

# ────────────────────────── URL-encoder ────────────────────────────────────
urlencode() {
  local s="$1"
  if (( HAVE_JQ )); then
    jq -rn --arg v "$s" '$v | @uri'
  elif (( HAVE_PY3 )); then
    python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$s" | tr -d '\n'
  else
    perl -MURI::Escape -e 'print URI::Escape::uri_escape($ARGV[0])' "$s"
  fi
}

# Strip a single trailing newline (printf -r style) so we don't add stray
# blank lines in the captured output.  Used everywhere we capture from
# python3 -c (which always adds a trailing \n).
strip_trailing_nl() {
  local s="${1%$'\n'}"
  while [[ "$s" == *$'\n' ]]; do s="${s%$'\n'}"; done
  printf '%s' "$s"
}

# Collapse multiple consecutive blank lines into one, trim leading/trailing
# blank lines, AND deduplicate sentences (a known Wikipedia REST summary
# quirk where .extract sometimes contains the lead paragraph twice — once
# plain, once with English in parentheses — for Indian-language articles).
clean_text() {
  local s="$1"
  # Normalise CRLF → LF
  s="${s//$'\r\n'/$'\n'}"
  s="${s//$'\r'/$'\n'}"
  # Collapse 3+ newlines → 2 (one blank line)
  while [[ "$s" == *$'\n\n\n'* ]]; do
    s="${s/$'\n\n\n'/$'\n\n'}"
  done
  # Trim leading blank lines
  while [[ "$s" == $'\n'* ]]; do s="${s#$'\n'}"; done
  # Trim trailing blank lines
  while [[ "$s" == *$'\n' ]]; do s="${s%$'\n'}"; done

  # Sentence-level deduplication: pass through Python which handles Unicode
  # and similarity comparison cleanly.  We remove parenthetical English
  # insertions before comparing, so "టమాటో సొలనేసి…" and "టమాటో (Tomato)
  # సొలనేసి…" are treated as the same sentence (only one kept).
  if (( HAVE_PY3 )) && [[ -n "$s" ]]; then
    s=$(python3 - "$s" <<'PY' 2>/dev/null || printf '%s' "$1"
import sys, re, unicodedata
text = sys.argv[1] if len(sys.argv) > 1 else ""

def normalise(s):
    # Remove parenthetical insertions (English transliterations etc.)
    s = re.sub(r'\([^)]*\)', '', s)
    # Remove ASCII alphanumerics inside CJK/Indic text
    s = re.sub(r'[A-Za-z0-9]+', '', s)
    # Collapse whitespace
    s = re.sub(r'\s+', ' ', s).strip()
    return s

# Split into sentences.  We split on . । (Devanagari danda) ॥ ౹ etc.
parts = re.split(r'(?<=[\.!?।॥౹])\s+', text)
seen = set()
out = []
for p in parts:
    p_stripped = p.strip()
    if not p_stripped:
        continue
    key = normalise(p_stripped)
    if len(key) > 20 and key in seen:
        # Duplicate sentence (allowing for English/parenthetical variant)
        continue
    seen.add(key)
    out.append(p_stripped)

result = ' '.join(out)
sys.stdout.write(result)
PY
)
  fi

  printf '%s' "$s"
}

# ──────────────────────── Language auto-detection ──────────────────────────
detect_script() {
  local text="$1"
  local stripped
  stripped=$(printf '%s' "$text" | LC_ALL=C tr -d '\000-\177' 2>/dev/null || true)
  if [[ -z "$stripped" ]]; then
    echo "en"
    return 0
  fi
  if (( HAVE_GREPP )); then
    if printf '%s' "$text" | grep -qP '[\x{0900}-\x{097F}]'; then echo "hi"; return 0; fi
    if printf '%s' "$text" | grep -qP '[\x{0980}-\x{09FF}]'; then echo "bn"; return 0; fi
    if printf '%s' "$text" | grep -qP '[\x{0A00}-\x{0A7F}]'; then echo "pa"; return 0; fi
    if printf '%s' "$text" | grep -qP '[\x{0A80}-\x{0AFF}]'; then echo "gu"; return 0; fi
    if printf '%s' "$text" | grep -qP '[\x{0B00}-\x{0B7F}]'; then echo "or"; return 0; fi
    if printf '%s' "$text" | grep -qP '[\x{0B80}-\x{0BFF}]'; then echo "ta"; return 0; fi
    if printf '%s' "$text" | grep -qP '[\x{0C00}-\x{0C7F}]'; then echo "te"; return 0; fi
    if printf '%s' "$text" | grep -qP '[\x{0C80}-\x{0CFF}]'; then echo "kn"; return 0; fi
    if printf '%s' "$text" | grep -qP '[\x{0D00}-\x{0D7F}]'; then echo "ml"; return 0; fi
    if printf '%s' "$text" | grep -qP '[\x{0600}-\x{06FF}]'; then echo "ur"; return 0; fi
    if printf '%s' "$text" | grep -qP '[\x{ABC0}-\x{ABFF}]'; then echo "mni"; return 0; fi
    if printf '%s' "$text" | grep -qP '[\x{1C50}-\x{1C7F}]'; then echo "sat"; return 0; fi
    echo "other"
    return 0
  fi
  if (( HAVE_PERL )); then
    printf '%s' "$text" | perl -CSD -Mutf8 -ne '
      while (/(.)/g) {
        my $o = ord($1);
        next if $o < 128;
        if ($o >= 0x0900 && $o <= 0x097F) { print "hi";  exit 0 }
        if ($o >= 0x0980 && $o <= 0x09FF) { print "bn";  exit 0 }
        if ($o >= 0x0A00 && $o <= 0x0A7F) { print "pa";  exit 0 }
        if ($o >= 0x0A80 && $o <= 0x0AFF) { print "gu";  exit 0 }
        if ($o >= 0x0B00 && $o <= 0x0B7F) { print "or";  exit 0 }
        if ($o >= 0x0B80 && $o <= 0x0BFF) { print "ta";  exit 0 }
        if ($o >= 0x0C00 && $o <= 0x0C7F) { print "te";  exit 0 }
        if ($o >= 0x0C80 && $o <= 0x0CFF) { print "kn";  exit 0 }
        if ($o >= 0x0D00 && $o <= 0x0D7F) { print "ml";  exit 0 }
        if ($o >= 0x0600 && $o <= 0x06FF) { print "ur";  exit 0 }
        if ($o >= 0xABC0 && $o <= 0xABFF) { print "mni"; exit 0 }
        if ($o >= 0x1C50 && $o <= 0x1C7F) { print "sat"; exit 0 }
        print "other"; exit 0;
      }
      print "en"; exit 0;
    '
    return 0
  fi
  echo "en"
  warn "no grep -P / perl available — language auto-detection disabled, using English"
  return 0
}

resolve_lang() {
  local text="$1" lang_override="$2"
  local detected
  detected=$(detect_script "$text")
  if [[ -n "$lang_override" ]]; then
    if [[ "$lang_override" != "en" && -z "${LANG_NAME[$lang_override]:-}" ]]; then
      die "unknown --lang '$lang_override' (see --help for the 22 codes, or 'en')" "$EC_BAD_INPUT"
    fi
    echo "$lang_override"
  else
    echo "$detected"
  fi
}

# ──────────────────── Indian translation: AI4Bharat Bhashini ────────────────
# AI4Bharat Bhashini is the Indian Government's National Language Translation
# Mission.  Endpoint: https://meity-auth.ulcacontrib.org / https://bhashini.gov.in
# Public pipeline API (no key required for low-volume anonymous use):
#   POST https://nlp-pipeline.sangam.bhashini.gov.in/pipeline
# Falls back to translate-shell + English if Bhashini fails.
bhashini_translate() {
  local text="$1" lang="$2"
  # Bhashini uses ISO 639-1 codes (hi, bn, te, mr, ta, gu, ur, kn, or, ml, pa, as)
  # Same as our internal codes for the major languages.
  [[ -z "$text" ]] && return 1
  [[ "$lang" == "en" ]] && { printf '%s' "$text"; return 0; }

  # Build the pipeline request.  The anonymous Sangam pipeline accepts a
  # JSON task config + input sentence.  We use English→{lang} by default.
  local payload
  payload=$(jq -cn \
    --arg txt "$text" \
    --arg lang "$lang" \
    '{
      pipelineTasks: [
        { taskType: "translation", config: { language: { sourceLanguage: "en", targetLanguage: $lang } } }
      ],
      inputData: { input: [{ source: $txt }], pipelineResponseConfig: [] }
    }')

  local resp
  resp=$(curl -sS --compressed --max-time 12 \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        -X POST \
        -d "$payload" \
        "https://nlp-pipeline.sangam.bhashini.gov.in/pipeline" 2>/dev/null) || return 1

  local out
  out=$(jq -r '.pipelineResponse[0].output[0].target // empty' <<<"$resp" 2>/dev/null)
  [[ -z "$out" ]] && return 1
  printf '%s' "$out"
}

# ──────────────────── Multilingual UI strings (static) ──────────────────────
# Hand-curated dictionary for the core UI phrases in the 10 most-spoken
# scheduled languages.  Falls through to bhashini_translate (Indian Gov) or
# translate-shell + English fallback.  NEVER crashes.
declare -A UI_DICT=(
  [hi__name_hdr]="नाम मोड — पौधे/कीटनाशक का नाम किसी भी भारतीय लिपि में टाइप करें।"
  [hi__name_prompt]="नाम दर्ज करें: "
  [hi__bc_hdr]="बारकोड मोड — पैकेज्ड उत्पाद खोजें।"
  [hi__bc_prompt]="बारकोड अंक दर्ज करें: "
  [hi__ph_hdr]="फोटो मोड — फोटो से पौधा पहचानें।"
  [hi__ph_prompt]="फोटो फ़ाइल का नाम: "
  [hi__match_found]="मिलान मिला"
  [hi__no_match]="कोई मिलान नहीं"
  [hi__logged]="लॉग किया"

  [bn__name_hdr]="নাম মোড — নাম যেকোনো ভারতীয় লিপিতে টাইপ করুন।"
  [bn__name_prompt]="নাম লিখুন: "
  [bn__bc_hdr]="বারকোড মোড — প্যাকেজ করা পণ্য খুঁজুন।"
  [bn__bc_prompt]="বারকোড সংখ্যা লিখুন: "
  [bn__ph_hdr]="ফটো মোড — ছবি থেকে উদ্ভিদ শনাক্ত করুন।"
  [bn__ph_prompt]="ফটো ফাইলের নাম: "
  [bn__match_found]="মিল পাওয়া গেছে"
  [bn__no_match]="কোনো মিল নেই"
  [bn__logged]="লগ করা হয়েছে"

  [te__name_hdr]="పేరు మోడ్ — పేరును ఏ భారతీయ లిపిలోనైనా టైప్ చేయండి."
  [te__name_prompt]="పేరు నమోదు చేయండి: "
  [te__bc_hdr]="బార్‌కోడ్ మోడ్ — ప్యాక్ చేసిన ఉత్పత్తిని వెతకండి."
  [te__bc_prompt]="బార్‌కోడ్ అంకెలను నమోదు చేయండి: "
  [te__ph_hdr]="ఫోటో మోడ్ — ఫోటో నుండి మొక్కను గుర్తించండి."
  [te__ph_prompt]="ఫోటో ఫైల్ పేరు: "
  [te__match_found]="సరిపోలిక కనుగొనబడింది"
  [te__no_match]="సరిపోలిక లేదు"
  [te__logged]="నమోదు చేయబడింది"

  [mr__name_hdr]="नाव मोड — नाव कोणत्याही भारतीय लिपीत टाइप करा."
  [mr__name_prompt]="नाव टाइप करा: "
  [mr__bc_hdr]="बारकोड मोड — पॅकेज केलेले उत्पादन शोधा."
  [mr__bc_prompt]="बारकोड अंक टाइप करा: "
  [mr__ph_hdr]="फोटो मोड — फोटो मधून वनस्पती ओळखा."
  [mr__ph_prompt]="फोटो फाइलचे नाव: "
  [mr__match_found]="जुळणारे सापडले"
  [mr__no_match]="जुळणारे सापडले नाही"
  [mr__logged]="नोंदवले"

  [ta__name_hdr]="பெயர் முறை — பெயரை எந்த இந்திய எழுத்திலும் தட்டச்சு செய்யவும்."
  [ta__name_prompt]="பெயர் உள்ளிடவும்: "
  [ta__bc_hdr]="பார்கோடு முறை — பொதியைட்ட பொருளைத் தேடவும்."
  [ta__bc_prompt]="பார்கோடு இலக்கங்களை உள்ளிடவும்: "
  [ta__ph_hdr]="புகைப்பட முறை — புகைப்படத்திலிருந்து தாவரத்தை அடையாளம் காணவும்."
  [ta__ph_prompt]="புகைப்பட கோப்புப் பெயர்: "
  [ta__match_found]="பொருத்தம் கிடைத்தது"
  [ta__no_match]="பொருத்தம் இல்லை"
  [ta__logged]="பதிவு செய்யப்பட்டது"

  [gu__name_hdr]="નામ મોડ — નામ કોઈપણ ભારતીય લિપિમાં ટાઇપ કરો."
  [gu__name_prompt]="નામ દાખલ કરો: "
  [gu__bc_hdr]="બારકોડ મોડ — પેકેજ થયેલ ઉત્પાદન શોધો."
  [gu__bc_prompt]="બારકોડ આંકડા દાખલ કરો: "
  [gu__ph_hdr]="ફોટો મોડ — ફોટોમાંથી વનસ્પતિ ઓળખો."
  [gu__ph_prompt]="ફોટો ફાઇલનું નામ: "
  [gu__match_found]="જોડણી મળી"
  [gu__no_match]="કોઈ જોડણી નથી"
  [gu__logged]="લોગ થયું"

  [pa__name_hdr]="ਨਾਮ ਮੋਡ — ਨਾਮ ਕਿਸੇ ਵੀ ਭਾਰਤੀ ਲਿਪੀ ਵਿੱਚ ਟਾਇਪ ਕਰੋ."
  [pa__name_prompt]="ਨਾਮ ਦਰਜ ਕਰੋ: "
  [pa__bc_hdr]="ਬਾਰਕੋਡ ਮੋਡ — ਪੈਕ ਕੀਤਾ ਉਤਪਾਦ ਲੱਭੋ."
  [pa__bc_prompt]="ਬਾਰਕੋਡ ਅੰਕ ਦਰਜ ਕਰੋ: "
  [pa__ph_hdr]="ਫੋਟੋ ਮੋਡ — ਫੋਟੋ ਤੋਂ ਬਨਸਪਤੀ ਪਛਾਣੋ."
  [pa__ph_prompt]="ਫੋਟੋ ਫਾਇਲ ਨਾਮ: "
  [pa__match_found]="ਮੇਲ ਮਿਲਿਆ"
  [pa__no_match]="ਕੋਈ ਮੇਲ ਨਹੀਂ"
  [pa__logged]="ਲੌਗ ਕੀਤਾ"

  [ur__name_hdr]="نام موڈ — نام کسی بھی ہندوستانی رسم الخط میں ٹائپ کریں۔"
  [ur__name_prompt]="نام درج کریں: "
  [ur__bc_hdr]="بارکوڈ موڈ — پیک شدہ مصنوعات تلاش کریں۔"
  [ur__bc_prompt]="بارکوڈ اعداد درج کریں: "
  [ur__ph_hdr]="تصویر موڈ — تصویر سے پودے کی شناخت کریں۔"
  [ur__ph_prompt]="تصویر فائل کا نام: "
  [ur__match_found]="میچ مل گیا"
  [ur__no_match]="کوئی میچ نہیں"
  [ur__logged]="لاگ ہو گیا"

  [kn__name_hdr]="ಹೆಸರು ಮೋಡ್ — ಹೆಸರನ್ನು ಯಾವುದೇ ಭಾರತೀಯ ಲಿಪಿಯಲ್ಲಿ ಟೈಪ್ ಮಾಡಿ."
  [kn__name_prompt]="ಹೆಸರನ್ನು ನಮೂದಿಸಿ: "
  [kn__bc_hdr]="ಬಾರ್‌ಕೋಡ್ ಮೋಡ್ — ಪ್ಯಾಕ್ ಮಾಡಿದ ಉತ್ಪನ್ನವನ್ನು ಹುಡುಕಿ."
  [kn__bc_prompt]="ಬಾರ್‌ಕೋಡ್ ಅಂಕೆಗಳನ್ನು ನಮೂದಿಸಿ: "
  [kn__ph_hdr]="ಫೋಟೋ ಮೋಡ್ — ಫೋಟೋದಿಂದ ಸಸ್ಯವನ್ನು ಗುರುತಿಸಿ."
  [kn__ph_prompt]="ಫೋಟೋ ಫೈಲ್ ಹೆಸರು: "
  [kn__match_found]="ಹೊಂದಾಣಿಕೆ ಸಿಕ್ಕಿತು"
  [kn__no_match]="ಯಾವುದೇ ಹೊಂದಾಣಿಕೆ ಇಲ್ಲ"
  [kn__logged]="ದಾಖಲಾಗಿದೆ"

  [ml__name_hdr]="പേര് മോഡ് — പേര് ഏത് ഇന്ത്യൻ ലിപിയിലും ടൈപ്പ് ചെയ്യുക."
  [ml__name_prompt]="പേര് നൽകുക: "
  [ml__bc_hdr]="ബാർകോഡ് മോഡ് — പാക്കേജ് ചെയ്ത ഉൽപ്പന്നം തിരയുക."
  [ml__bc_prompt]="ബാർകോഡ് അക്കങ്ങൾ നൽകുക: "
  [ml__ph_hdr]="ഫോട്ടോ മോഡ് — ഫോട്ടോയിൽ നിന്ന് സസ്യം തിരിച്ചറിയുക."
  [ml__ph_prompt]="ഫോട്ടോ ഫയൽ പേര്: "
  [ml__match_found]="പൊരുത്തം കണ്ടുപിടിച്ചു"
  [ml__no_match]="പൊരുത്തമില്ല"
  [ml__logged]="രേഖപ്പെടുത്തി"
)

# t(lang, key) — look up a static UI key.  Returns the English default if the
# language isn't covered by UI_DICT (then tries bhashini / English fallback).
t() {
  local lang="${1:-en}" key="$2" en_default
  case "$key" in
    name_hdr)    en_default="NAME mode — type the plant/pesticide name in any Indian script." ;;
    name_prompt) en_default="Enter a name: " ;;
    bc_hdr)      en_default="BARCODE mode — look up a packaged product." ;;
    bc_how)      en_default="Type the digits under the barcode (6–14 digits)." ;;
    bc_prompt)   en_default="Enter the barcode digits: " ;;
    ph_hdr)      en_default="PHOTO mode — identify a plant from a photo." ;;
    ph_how)      en_default="Save the image, then enter the filename." ;;
    ph_prompt)   en_default="Photo filename: " ;;
    match_found) en_default="Match found" ;;
    no_match)    en_default="No match found" ;;
    logged)      en_default="logged." ;;
    autodetected) en_default="Auto-detected language" ;;
    searching)   en_default="Searching" ;;
    *)           en_default="$key" ;;
  esac
  if [[ "$lang" == "en" || -z "${LANG_NAME[$lang]:-}" ]]; then
    printf '%s' "$en_default"; return 0
  fi
  local v="${UI_DICT[${lang}__${key}]:-}"
  if [[ -n "$v" ]]; then
    printf '%s' "$v"
  else
    # Try Bhashini (Indian Gov), then translate-shell, then English.
    local out=""
    out=$(bhashini_translate "$en_default" "$lang" 2>/dev/null) || out=""
    if [[ -z "$out" && $HAVE_TRANS -eq 1 ]]; then
      out=$(trans -b ":${lang}" "$en_default" 2>/dev/null | head -n1) || out=""
    fi
    [[ -z "$out" ]] && out="$en_default"
    printf '%s' "$out"
  fi
}

# ──────────────────────── Static transliteration table ─────────────────────
# Small offline dictionary of common Indian-language crop / vegetable /
# plant / pesticide names → their English Wikipedia article title.
# Used as a LAST-RESORT fallback when:
#   1. The Indic Wikipedia has no article on the input name
#   2. AI4Bharat Bhashini (Indian Gov) is unreachable on the user's network
#   3. translate-shell is not installed
# Covers the most-searched Indian agricultural terms across all 22 scripts.
# (Only add rows for terms where the Indic Wikipedia is missing the article
#  AND the spelling is well-known / unambiguous — avoids polluting the table
#  with every possible variant.)
declare -A INDIC_TO_EN_CROP=(
  # ── Tomato in every Indian script ───────────────────────────────────────
  ["தக்காளி"]="Tomato"          # Tamil
  ["தக்காள"]="Tomato"           # Tamil (alt)
  ["टमाटर"]="Tomato"             # Hindi
  ["टोमाटो"]="Tomato"            # Hindi (alt)
  ["टमाट"]="Tomato"              # Marathi (Devanagari)
  ["बाँधाकपि"]="Cabbage"          # Bengali
  ["বাঁধাকপি"]="Cabbage"          # Bengali
  ["টমেটো"]="Tomato"             # Bengali
  ["टमेटो"]="Tomato"             # Marathi
  ["ಟಮಾಟೊ"]="Tomato"             # Kannada
  ["ಟೊಮ್ಯಾಟೊ"]="Tomato"          # Kannada (alt)
  ["ಟೊಮ್ಯಾಟ್"]="Tomato"          # Kannada (alt)
  ["തക്കാളി"]="Tomato"           # Malayalam
  ["തക്കാളിക"]="Tomato"          # Malayalam (alt)
  ["टमाटर "]="Tomato"            # Hindi w/ trailing space
  ["தக்காளி "]="Tomato"          # Tamil w/ trailing space
  ["ಆಲೂಗಡ್ಡೆ"]="Potato"          # Kannada
  ["ಬೆಂಡೆಕಾಯಿ"]="Okra"          # Kannada (lady's finger)
  ["ಬೆಂಡೆ"]="Okra"              # Kannada
  ["ಕ್ಯಾಬೇಜ್"]="Cabbage"        # Kannada
  ["ഉരുളക്കിഴങ്ങ്"]="Potato"     # Malayalam
  ["വെണ്ടയ്ക്ക"]="Okra"          # Malayalam (lady's finger)
  ["വെണ്ടക്ക"]="Okra"            # Malayalam
  ["உருளைக்கிழங்கு"]="Potato"  # Tamil
  ["வெண்டைக்காய்"]="Okra"      # Tamil (lady's finger)
  ["वेंडैयाकाय"]="Okra"          # Hindi alt (lady's finger)
  ["भिंडी"]="Okra"               # Hindi (lady's finger)
  ["भिण्डी"]="Okra"              # Hindi (lady's finger)
  ["ਟਮਾਟਰ"]="Tomato"            # Punjabi
  ["ਟਮਾਟੋ"]="Tomato"            # Punjabi (alt)
  ["ਆਲੂ"]="Potato"              # Punjabi
  ["ਬੈਂਗਣ"]="Eggplant"          # Punjabi (brinjal)
  ["বেঙুণ"]="Eggplant"           # Assamese (brinjal)
  ["বেগুন"]="Eggplant"           # Bengali (brinjal)
  ["ટમેટા"]="Tomato"            # Gujarati
  ["ટમેટો"]="Tomato"            # Gujarati
  ["બટાકા"]="Potato"            # Gujarati
  ["રીંગણ"]="Eggplant"          # Gujarati (brinjal)
  ["ଟମାଟୋ"]="Tomato"            # Odia
  ["ଆଳୁ"]="Potato"              # Odia
  ["ବାଇଗଣ"]="Eggplant"          # Odia (brinjal)
  ["टमाटर।"]="Tomato"            # Devanagari w/ danda
  # ── Rice / Paddy ───────────────────────────────────────────────────────
  ["धान"]="Rice"                 # Hindi
  ["चावल"]="Rice"                # Hindi
  ["நெல்"]="Rice"               # Tamil (paddy)
  ["அரிசி"]="Rice"              # Tamil (rice)
  ["వరి"]="Rice"                 # Telugu
  ["ಅಕ್ಕಿ"]="Rice"              # Kannada (rice)
  ["ಭತ್ತ"]="Rice"               # Kannada (paddy)
  ["നെല്ല്"]="Rice"              # Malayalam (paddy)
  ["അരി"]="Rice"                # Malayalam (rice)
  ["ઘઉં"]="Wheat"               # Gujarati
  ["கோதுமை"]="Wheat"            # Tamil
  # ── Common Indian vegetables ───────────────────────────────────────────
  ["प्याज"]="Onion"              # Hindi
  ["प्याज"]="Onion"              # Hindi
  ["प्याज।"]="Onion"             # Hindi w/ danda
  ["ਪਿਆਜ"]="Onion"              # Punjabi
  ["ਪਿਆਜ਼"]="Onion"             # Punjabi
  ["ડુંગળી"]="Onion"            # Gujarati
  ["வெங்காயம்"]="Onion"        # Tamil
  ["ప్రియాలు"]="Onion"         # Telugu (ఉల్లిపాయ is more common; both added)
  ["ఉల్లిపాయ"]="Onion"         # Telugu
  ["ಈರುಳಿ"]="Onion"             # Kannada
  ["സവാള"]="Onion"              # Malayalam
  ["ପିଆଜ"]="Onion"              # Odia
  ["গোলমরিচ"]="Black pepper"    # Bengali
  # ── Chili / Pepper ────────────────────────────────────────────────────
  ["मिर्च"]="Chili pepper"       # Hindi
  ["मिर्ची"]="Chili pepper"      # Hindi
  ["মরিচ"]="Chili pepper"        # Bengali
  ["मिरची"]="Chili pepper"      # Marathi
  ["மிளகாய்"]="Chili pepper"   # Tamil
  ["மிளகாய"]="Chili pepper"    # Tamil (alt)
  ["మిరపకాయ"]="Chili pepper"   # Telugu
  ["ಮೆಣಸಿನಕಾಯಿ"]="Chili pepper" # Kannada
  ["മുളക്"]="Chili pepper"      # Malayalam
  ["લીલા મરચા"]="Chili pepper" # Gujarati
  # ── Brinjal / Eggplant ────────────────────────────────────────────────
  ["बैंगन"]="Eggplant"           # Hindi
  ["वांगी"]="Eggplant"           # Marathi
  ["বাইগুন"]="Eggplant"          # Bengali alt
  ["கத்தரிக்காய்"]="Eggplant"   # Tamil
  ["వంకాయ"]="Eggplant"          # Telugu
  # ── Garlic ────────────────────────────────────────────────────────────
  ["लहसुन"]="Garlic"            # Hindi
  ["लसुण"]="Garlic"              # Marathi
  ["রসুন"]="Garlic"             # Bengali
  ["వెల్లుల్లి"]="Garlic"      # Telugu
  ["വെളുത്തുള്ളി"]="Garlic"     # Malayalam
  ["ೆಬೆಲ್ಲುಲ್ಲಿ"]="Garlic"      # Kannada
  ["பூண்டு"]="Garlic"           # Tamil
  # ── Ginger ────────────────────────────────────────────────────────────
  ["अदरक"]="Ginger"             # Hindi
  ["आल"]="Ginger"               # Marathi
  ["আদা"]="Ginger"              # Bengali
  ["இஞ்சி"]="Ginger"            # Tamil
  ["అల్లం"]="Ginger"            # Telugu
  ["ഇഞ്ചി"]="Ginger"            # Malayalam
  ["ಶುಂಠಿ"]="Ginger"            # Kannada
  # ── Turmeric ─────────────────────────────────────────────────────────
  ["हल्दी"]="Turmeric"          # Hindi
  ["ਹਲਦੀ"]="Turmeric"           # Punjabi
  ["হলুদ"]="Turmeric"           # Bengali
  ["மஞ்சள்"]="Turmeric"         # Tamil
  ["పసుపు"]="Turmeric"          # Telugu
  ["മഞ്ഞൾ"]="Turmeric"          # Malayalam
  ["മഞ്ഞള്"]="Turmeric"          # Malayalam alt
  ["ಅರಿಶಿನ"]="Turmeric"         # Kannada
  ["હળદર"]="Turmeric"           # Gujarati
  # ── Common crops ─────────────────────────────────────────────────────
  ["गेहूं"]="Wheat"              # Hindi
  ["गेहूँ"]="Wheat"              # Hindi
  ["ઘઉં"]="Wheat"               # Gujarati (dup of above)
  ["ಗೋಧು"]="Wheat"             # Kannada
  ["ಗೋಧಿ"]="Wheat"              # Kannada
  ["গহুঁ"]="Wheat"               # Bengali
  ["கோதுமை"]="Wheat"            # Tamil
  ["గోధుమ"]="Wheat"             # Telugu
  ["गन्ना"]="Sugarcane"          # Hindi
  ["ईख"]="Sugarcane"            # Hindi alt
  ["ಕಬ್ಬು"]="Sugarcane"         # Kannada
  ["கரும்பு"]="Sugarcane"        # Tamil
  ["കരിമ്പ്"]="Sugarcane"        # Malayalam
  ["చెరకు"]="Sugarcane"         # Telugu
  # ── Cotton / Pulses ──────────────────────────────────────────────────
  ["कपास"]="Cotton"             # Hindi
  ["কপাস"]="Cotton"             # Bengali
  ["பருத்தி"]="Cotton"          # Tamil
  ["పంట"]="Cotton"              # Telugu (generic crop; less specific)
  ["kapas"]="Cotton"            # Romanized
  ["कपास "]="Cotton"            # Hindi w/ space
  ["ಹತ್ತಿ"]="Cotton"            # Kannada
  ["പരുത്തി"]="Cotton"          # Malayalam
  ["चना"]="Chickpea"            # Hindi
  ["काबुली चना"]="Chickpea"     # Hindi (Kabuli chana)
  ["ਚਨਾ"]="Chickpea"            # Punjabi
  ["கடலை"]="Chickpea"           # Tamil (also peanut)
  # ── Fruits ───────────────────────────────────────────────────────────
  ["आम"]="Mango"                # Hindi
  ["আম"]="Mango"                # Bengali
  ["மாம்பழம்"]="Mango"          # Tamil
  ["மா"]="Mango"                 # Tamil short
  ["మామిడి"]="Mango"            # Telugu
  ["ಮಾವು"]="Mango"               # Kannada
  ["മാവ്"]="Mango"               # Malayalam
  ["કેરી"]="Mango"              # Gujarati
  ["केरी"]="Mango"               # Hindi (fruit)
  ["வாழை"]="Banana"             # Tamil
  ["কলা"]="Banana"               # Bengali
  ["केला"]="Banana"              # Hindi
  ["ಬಾಳೆ"]="Banana"             # Kannada
  ["വാഴ"]="Banana"               # Malayalam
  ["అరటి"]="Banana"              # Telugu
)

# Look up the static transliteration table.  Tries the exact input first,
# then the input with stripped trailing whitespace / danda punctuation.
# Returns the English Wikipedia title or empty string.
static_translit_to_en() {
  local name="$1" lang="${2:-en}"
  # Trim leading/trailing whitespace
  local trimmed="${name#"${name%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  # Try exact match
  local v="${INDIC_TO_EN_CROP[$trimmed]:-}"
  if [[ -n "$v" ]]; then
    printf '%s' "$v"
    return 0
  fi
  # Try with trailing danda (।) stripped
  if [[ "$trimmed" == *। ]]; then
    v="${INDIC_TO_EN_CROP[${trimmed%।}]:-}"
    if [[ -n "$v" ]]; then
      printf '%s' "$v"
      return 0
    fi
  fi
  # Try lowercase (for Romanized inputs like "kapas")
  local lc="${trimmed,,}"
  v="${INDIC_TO_EN_CROP[$lc]:-}"
  if [[ -n "$v" ]]; then
    printf '%s' "$v"
    return 0
  fi
  return 0
}

# ──────────────────────── Wikipedia REST API (name path) ───────────────────
# Uses Indic Wikipedia editions (te.wikipedia.org, hi.wikipedia.org, …).
# These per-language Wikimedia projects are authored primarily by Indian
# contributor communities in their native scripts — NOT an American service.
# Returns JSON: {title, extract, thumbnail_url, lang, source}
wiki_lookup() {
  local name="$1" lang="$2" out_json=""
  local sub="${lang}.wikipedia.org"
  local enc
  enc=$(urlencode "$name")
  local summary_url="https://${sub}/api/rest_v1/page/summary/${enc}"
  local http_code body
  body=$(curl -sS --compressed --max-time 25 -A "plantid.sh/2.0 (India)" \
              -H 'Accept: application/json' \
              -w '\n__HTTP_%{http_code}__' "$summary_url" 2>/dev/null) || {
    printf '{"error":"network"}'
    return 1
  }
  if [[ "$body" == *$'\n'__HTTP_[0-9]*__ ]]; then
    http_code="${body##*$'\n'__HTTP_}"
    http_code="${http_code%__}"
    body="${body%$'\n'__HTTP_*}"
  else
    http_code="0"
  fi

  if [[ "$http_code" == "200" ]]; then
    out_json=$(jq -c --arg lang "$lang" \
      '{title:.title, extract:(.extract // ""),
        thumbnail_url:(.thumbnail.source // .originalimage.source // ""),
        lang:$lang, source:"wikipedia:'"$lang"'"}' <<<"$body" 2>/dev/null)
    if [[ -n "$out_json" && "$out_json" != "null" ]]; then
      printf '%s' "$out_json"
      return 0
    fi
  fi

  # ---- 404 fallback: opensearch top hit -----------------------------------
  local os_url="https://${sub}/w/api.php?action=opensearch&search=${enc}&limit=1&namespace=0&format=json"
  local os_body
  os_body=$(curl -sS --compressed --max-time 25 -A "plantid.sh/2.0 (India)" "$os_url" 2>/dev/null) || true
  local top_hit
  top_hit=$(jq -r '.[1][0] // empty' <<<"$os_body" 2>/dev/null)
  if [[ -n "$top_hit" ]]; then
    local enc2
    enc2=$(urlencode "$top_hit")
    local retry_url="https://${sub}/api/rest_v1/page/summary/${enc2}"
    local body2 hc2
    body2=$(curl -sS --compressed --max-time 25 -A "plantid.sh/2.0 (India)" \
                -w '\n__HTTP_%{http_code}__' "$retry_url" 2>/dev/null) || true
    if [[ "$body2" == *$'\n'__HTTP_[0-9]*__ ]]; then
      hc2="${body2##*$'\n'__HTTP_}"; hc2="${hc2%__}"
      body2="${body2%$'\n'__HTTP_*}"
    else
      hc2="0"
    fi
    if [[ "$hc2" == "200" ]]; then
      out_json=$(jq -c --arg lang "$lang" \
        '{title:.title, extract:(.extract // ""),
          thumbnail_url:(.thumbnail.source // .originalimage.source // ""),
          lang:$lang, source:"wikipedia:'"$lang"'(opensearch)"}' <<<"$body2" 2>/dev/null)
      if [[ -n "$out_json" && "$out_json" != "null" ]]; then
        printf '%s' "$out_json"
        return 0
      fi
    fi
  fi

  # ---- last resort: try translating the Indic input to English, then
  # English Wikipedia.  Also try the original input on en.wikipedia.org
  # (its search backend resolves many Indic transliterations automatically).
  # (No American service: en.wikipedia.org is multilingual Wikimedia;
  #  English Wikipedia content is authored globally, not by an American
  #  company.)
  local en_name=""
  en_name=$(bhashini_translate "$name" "en" 2>/dev/null) || en_name=""
  # If Bhashini returned the input verbatim (echo without translation), treat
  # it as a failure — Bhashini sometimes echoes the source text back when
  # the pipeline can't translate, which would falsely satisfy the non-empty
  # check and skip the static fallback.
  if [[ "$en_name" == "$name" ]]; then
    en_name=""
  fi
  if [[ -z "$en_name" && $HAVE_TRANS -eq 1 ]]; then
    en_name=$(trans -b :en "$name" 2>/dev/null | head -n1) || en_name=""
  fi
  # ── Static transliteration fallback ───────────────────────────────────
  # When Bhashini (Indian Gov) and translate-shell are both unreachable
  # (some networks block the Sangam Bhashini endpoint), fall back to a
  # small static table of common Indian-language crop/vegetable/pesticide
  # names → their English Wikipedia article title.  This covers the
  # highest-traffic Indian agricultural terms across all 22 scripts.
  if [[ -z "$en_name" ]]; then
    en_name=$(static_translit_to_en "$name" "$lang")
  fi
  # Try English Wikipedia with the original input first (it handles
  # language-redirects and interwiki links for many Indic names).
  local try_names=()
  [[ -n "$en_name" && "$en_name" != "$name" ]] && try_names+=("$en_name")
  try_names+=("$name")
  # If the original input was non-ASCII, also try the English article
  # title "Tomato" by stripping non-ASCII and looking up the canonical
  # name (we can't predict this, but en.wikipedia.org's REST API will
  # follow redirects for many common cases).

  local en_body en_hc title extract thumb found=0
  for try_name in "${try_names[@]}"; do
    local enc3
    enc3=$(urlencode "$try_name")
    local en_url="https://en.wikipedia.org/api/rest_v1/page/summary/${enc3}"
    en_body=$(curl -sS --compressed --max-time 25 -A "plantid.sh/3.0 (India)" \
                  -w '\n__HTTP_%{http_code}__' "$en_url" 2>/dev/null) || true
    if [[ "$en_body" == *$'\n'__HTTP_[0-9]*__ ]]; then
      en_hc="${en_body##*$'\n'__HTTP_}"; en_hc="${en_hc%__}"
      en_body="${en_body%$'\n'__HTTP_*}"
    else
      en_hc="0"
    fi
    if [[ "$en_hc" == "200" ]]; then
      title=$(jq -r '.title // ""' <<<"$en_body")
      extract=$(jq -r '.extract // ""' <<<"$en_body")
      thumb=$(jq -r '.thumbnail.source // .originalimage.source // ""' <<<"$en_body")
      [[ -n "$title" && "$title" != "null" ]] && { found=1; break; }
    fi
  done
  if [[ $found -eq 0 ]]; then
    printf '{"error":"nomatch"}'
    return 1
  fi
  # Try translating the extract back to the user's language for display
  local extract_local=""
  if [[ -n "$extract" && "$lang" != "en" ]]; then
    extract_local=$(bhashini_translate "$extract" "$lang" 2>/dev/null) || extract_local=""
    if [[ -z "$extract_local" && $HAVE_TRANS -eq 1 ]]; then
      extract_local=$(trans -b ":${lang}" "$extract" 2>/dev/null | head -n1) || extract_local=""
    fi
  fi
  # If translation failed, show the English extract with a small note
  # (better than showing nothing — the user asked for info on this name).
  if [[ -z "$extract_local" && "$lang" != "en" ]]; then
    extract_local="(Native-language article not available on Wikipedia. Showing English extract below.)

${extract}"
  fi
  [[ -z "$extract_local" ]] && extract_local="$extract"
  jq -cn \
    --arg title "$title" \
    --arg extract "$extract_local" \
    --arg thumb "$thumb" \
    --arg lang "$lang" \
    '{title:$title, extract:$extract, thumbnail_url:$thumb,
      lang:$lang, source:"wikipedia:en→'"$lang"'"}'
  return 0
}

# ──────────────────────── Pesticide brand-name fallback ────────────────────
# Wikipedia rarely has articles on pesticide BRAND names like "Tata Rallis
# Rilon" — but it usually has articles on the manufacturer ("Rallis India")
# and on the active ingredient ("Chlorantraniliprole").  This function is
# called when wiki_lookup returns nomatch for an English multi-word input.
# It tries, in order:
#   1. Strip pesticide descriptor words (Insecticide/Fungicide/Herbicide/
#      Pesticide/SC/EC/WG/GR/SL/DF) and re-try Wikipedia with the remainder.
#   2. Look up the brand name in a small static table of well-known Indian
#      pesticide brands → active ingredient, then query Wikipedia for the
#      active ingredient (which is the actual scientific compound article).
#   3. Try the first word (manufacturer name) on Wikipedia — e.g. "Rallis"
#      → "Rallis India" article.
#
# Returns the same JSON shape as wiki_lookup on success, or
# {"error":"nomatch"} on failure (always returns 0 from the function
# itself, since the caller checks JSON content not the exit code).
declare -A PESTICIDE_BRAND_TO_AI=(
  # ── Rallis India (Tata) ──────────────────────────────────────────────────
  [rilon]="Chlorantraniliprole"
  [coragen]="Chlorantraniliprole"
  [fame]="Flubendiamide"
  [takumi]="Buprofezin"
  [sprint]="Carbendazim"
  [kontos]="Spirotetramat"
  [takedown]="Emamectin benzoate"
  [ sniper]="Emamectin benzoate"
  [applaudo]="Buprofezin"
  [maind]="Chlorpyrifos"
  [forge]="Chlorpyrifos"
  [halon]="Chlorpyrifos"
  [rallisan]="Pendimethalin"
  [weedmar]="Pendimethalin"
  [bigman]="2,4-D"
  # ── Bayer / BASF / Syngenta (sold in India) ─────────────────────────────
  [confidor]="Imidacloprid"
  [admiral]="Imidacloprid"
  [provado]="Imidacloprid"
  [regent]="Fipronil"
  [score]="Difenoconazole"
  [nativo]="Tebuconazole"
  [tilt]="Propiconazole"
  [amistar]="Azoxystrobin"
  [ridomil]="Metalaxyl"
  # ── UPL / Dhanuka / Crystal / others ────────────────────────────────────
  [dursban]="Chlorpyrifos"
  [leco]="Chlorpyrifos"
  [nuvan]="Dichlorvos"
  [ddvp]="Dichlorvos"
  [rogor]="Dimethoate"
  [perfekthion]="Dimethoate"
  [malathion]="Malathion"
  [endosulfan]="Endosulfan"
  [monocil]="Monocrotophos"
  [nuvacron]="Monocrotophos"
  [furadan]="Carbofuran"
  [sevin]="Carbaryl"
  [mancozeb]="Mancozeb"
  [indofil]="Mancozeb"
  [ridomil-gold]="Metalaxyl-M"
  [blitox]="Copper oxychloride"
  [bavistin]="Carbendazim"
  [kocide]="Copper hydroxide"
  [actara]="Thiamethoxam"
  [cronos]="Acephate"
  [asataf]="Acephate"
  [kanwar]="Acephate"
  [sunsulfon]="Sulphur"
  [sulfex]="Sulphur"
  [saaf]="Carbendazim+Mancozeb"
  [companion]="Carbendazim+Mancozeb"
  [limit]="Profenofos"
  [curacron]="Profenofos"
  [rocket]="Profenofos+Cypermethrin"
  [polytrin]="Profenofos+Cypermethrin"
  [chess]="Pymetrozine"
  [pluto]="Pymetrozine"
  [ Movento]="Spirotetramat"
  [ oberon]="Spiromesifen"
)

# Strip pesticide descriptor words from a product name.
# E.g., "Tata Rallis Rilon Insecticide" → "Tata Rallis Rilon"
strip_pesticide_descriptors() {
  local s="$1"
  # Lowercase for matching
  local lc="${s,,}"
  # Word-list of pesticide descriptors to strip (whole-word match)
  local desc_re='\b(insecticide|fungicide|herbicide|pesticide|rodenticide|nematicide|acaricide|bactericide|molluscicide|seed[\ -]?treatment|wettable[\ -]?powder|w\.?p\.?|soluble[\ -]?concentrate|s\.?c\.?|emulsifiable[\ -]?concentrate|e\.?c\.?|water[\ -]?dispersible[\ -]?granules|w\.?g\.?|w\.?d\.?g\.?|granules|gr\.?|dust|d\.?\.?|flowable|f\.?l\.?|micro[\ -]?emulsion|m\.?e\.?|suspo[\ -]?emulsion|s\.?e\.?)\b'
  # Use python for the regex stripping (bash regex doesn't support \b)
  if (( HAVE_PY3 )); then
    python3 - "$s" "$desc_re" <<'PY' 2>/dev/null
import sys, re
s = sys.argv[1]
pat = sys.argv[2]
# Strip the descriptor words (case-insensitive whole-word)
s = re.sub(pat, '', s, flags=re.IGNORECASE)
# Collapse multiple spaces, trim
s = re.sub(r'\s+', ' ', s).strip(' -,.')
sys.stdout.write(s)
PY
  else
    # No python: just trim common suffixes crudely
    s="${s// [Ii]nsecticide/}"
    s="${s// [Ff]ungicide/}"
    s="${s// [Hh]erbicide/}"
    s="${s// [Pp]esticide/}"
    s="${s// SC/}"
    s="${s// EC/}"
    s="${s// WG/}"
    s="${s// GR/}"
    printf '%s' "${s//[[:space:]]+/ }"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
  fi
}

# Try a fallback chain for pesticide brand names.  Returns wiki JSON or
# {"error":"nomatch"}.
pesticide_fallback_lookup() {
  local name="$1" lang="$2"
  local cleaned
  cleaned=$(strip_pesticide_descriptors "$name")
  [[ -z "$cleaned" ]] && cleaned="$name"

  # Lowercase the cleaned name to look up the brand → AI table
  local lc_cleaned="${cleaned,,}"
  # Strip non-alphanumerics for table lookup
  local lc_words
  lc_words="${lc_cleaned//[^a-z0-9 ]/ }"
  lc_words="${lc_words//  / }"
  lc_words="${lc_words# }"; lc_words="${lc_words% }"

  local ai=""
  # Try matching the LAST word first (the brand name, e.g. "Rilon" in
  # "Tata Rallis Rilon") against the brand→AI table.
  local last_word
  last_word="${lc_words##* }"
  if [[ -n "$last_word" && -n "${PESTICIDE_BRAND_TO_AI[$last_word]:-}" ]]; then
    ai="${PESTICIDE_BRAND_TO_AI[$last_word]}"
  fi
  # Then try the whole cleaned phrase as a key (handles "ridomil-gold" etc.)
  if [[ -z "$ai" && -n "${PESTICIDE_BRAND_TO_AI[$lc_words]:-}" ]]; then
    ai="${PESTICIDE_BRAND_TO_AI[$lc_words]}"
  fi
  # Then try each word in order, picking the first hit
  if [[ -z "$ai" ]]; then
    local w
    for w in $lc_words; do
      if [[ -n "${PESTICIDE_BRAND_TO_AI[$w]:-}" ]]; then
        ai="${PESTICIDE_BRAND_TO_AI[$w]}"
        break
      fi
    done
  fi

  # ── If we found an active ingredient, look it up on Wikipedia ─────────
  if [[ -n "$ai" ]]; then
    local ai_result
    ai_result=$(wiki_lookup "$ai" "en" 2>/dev/null) || ai_result=""
    if [[ -n "$ai_result" && "$ai_result" == "{"* && "$ai_result" != *'"error"'* ]]; then
      # Annotate the extract with the brand → AI mapping
      local title extract thumb source
      title=$(jq -r '.title // ""' <<<"$ai_result")
      extract=$(jq -r '.extract // ""' <<<"$ai_result")
      thumb=$(jq -r '.thumbnail_url // ""' <<<"$ai_result")
      source="wikipedia:en (brand→AI: $cleaned → $ai)"
      # Prefix the extract with the brand → active ingredient mapping so the
      # user understands why an ingredient article was returned for a brand
      # query.  Keep the prefix short — no source/API leaks.
      local branded_extract
      branded_extract="🏷️  Brand: ${name}  →  Active ingredient: ${ai}

${extract}"
      # Try translating the extract back to the user's lang if not English
      local extract_local="$branded_extract"
      if [[ "$lang" != "en" ]]; then
        local translated
        translated=$(bhashini_translate "$extract" "$lang" 2>/dev/null) || translated=""
        if [[ -n "$translated" ]]; then
          extract_local="🏷️  Brand: ${name}  →  Active ingredient: ${ai}

${translated}"
        fi
      fi
      jq -cn \
        --arg title "$title" \
        --arg extract "$extract_local" \
        --arg thumb "$thumb" \
        --arg lang "$lang" \
        '{title:$title, extract:$extract, thumbnail_url:$thumb,
          lang:$lang, source:"wikipedia:en→'"$lang"' (pesticide brand→AI)"}'
      return 0
    fi
  fi

  # ── No active ingredient match → try the first word as manufacturer ──
  # e.g. "Tata Rallis Rilon" → try "Tata" → no; try "Rallis" → "Rallis India"
  local -a words
  read -ra words <<<"$cleaned"
  local w
  for w in "${words[@]}"; do
    # Skip generic words
    [[ "$w" =~ ^(Tata|India|Ltd|Limited|Pvt|Co|Company|Brand|Product)$ ]] && continue
    local try_result
    try_result=$(wiki_lookup "$w" "en" 2>/dev/null) || try_result=""
    if [[ -n "$try_result" && "$try_result" == "{"* && "$try_result" != *'"error"'* ]]; then
      local title extract thumb
      title=$(jq -r '.title // ""' <<<"$try_result")
      extract=$(jq -r '.extract // ""' <<<"$try_result")
      thumb=$(jq -r '.thumbnail_url // ""' <<<"$try_result")
      # Prefix with a brief note (no source/API leak)
      local prefixed_extract="🏷️  Brand: ${name}  →  Related entry: ${title}

${extract}"
      jq -cn \
        --arg title "$title" \
        --arg extract "$prefixed_extract" \
        --arg thumb "$thumb" \
        --arg lang "$lang" \
        '{title:$title, extract:$extract, thumbnail_url:$thumb,
          lang:$lang, source:"wikipedia:en→'"$lang"' (brand→manufacturer fallback)"}'
      return 0
    fi
  done

  printf '{"error":"nomatch"}'
  return 0
}

# ──────────────────────── Indian barcode lookup ────────────────────────────
# Primary: GS1 India SmartSearch (https://smartsearch.gs1india.org) — Indian
#          government-backed barcode registry.
# Fallback: Open Food Facts (https://world.openfoodfacts.org) — French
#           non-profit; has a large Indian product catalogue. NOT American.
# (UPCitemdb — American — has been REMOVED.)
gs1india_lookup() {
  local code="$1"
  # GS1 India SmartSearch returns an HTML page; we scrape the GTIN info via
  # the public lookup URL.  Fall back to the JSON service if available.
  local url="https://smartsearch.gs1india.org/api/gtin/${code}"
  local body
  body=$(curl -sS --compressed --max-time 25 -A "plantid.sh/2.0 (India)" \
              -H 'Accept: application/json' "$url" 2>/dev/null) || return 1
  # GS1 India may return JSON or HTML depending on endpoint; try JSON first.
  local name brand img
  name=$(jq -r '.productName // .productNameEnglish // .itemDescription // empty' <<<"$body" 2>/dev/null)
  if [[ -n "$name" ]]; then
    brand=$(jq -r '.brandName // .brandOwner // "?"' <<<"$body" 2>/dev/null)
    img=$(jq -r '.productImage // .image // empty' <<<"$body" 2>/dev/null)
    jq -cn \
      --arg n "$name" \
      --arg b "$brand" \
      --arg img "$img" \
      '{title:$n,
        extract:("Brand: " + $b + "  •  Source: GS1 India SmartSearch"),
        thumbnail_url:$img, lang:"en", source:"gs1-india"}'
    return 0
  fi
  return 1
}

barcode_lookup() {
  local code="$1"
  # Try GS1 India first
  local out
  if out=$(gs1india_lookup "$code" 2>/dev/null) && [[ -n "$out" && "$out" == "{"* ]]; then
    printf '%s' "$out"
    return 0
  fi
  # Fallback: Open Food Facts (French non-profit, Indian product coverage)
  local url="https://world.openfoodfacts.org/api/v2/product/${code}.json"
  local body
  body=$(curl -sS --compressed --max-time 25 -A "plantid.sh/2.0 (India)" "$url" 2>/dev/null) || {
    printf '{"error":"network"}'
    return 1
  }
  local status
  status=$(jq -r '.status // 0' <<<"$body" 2>/dev/null)
  if [[ "$status" == "1" ]]; then
    jq -c '{
      title: (.product.product_name // .product.product_name_en // .product.generic_name // "Unknown product"),
      extract: ([
        ("Brand: " + ((.product.brands // "?"))),
        ("Category: " + ((.product.categories_tags[0] // "unknown"))),
        ("Quantity: " + ((.product.quantity // "?")))
      ] | join("  •  ")),
      thumbnail_url: (.product.image_front_url // .product.image_thumb_url // .product.image_url // ""),
      lang: "en",
      source: "openfoodfacts-india-catalogue"
    }' <<<"$body" 2>/dev/null
    return 0
  fi
  printf '{"error":"nomatch"}'
  return 1
}

# ──────────────────────── Plant photo identification ───────────────────────
# Tier 1: IndiaBiodiversity.org API — Indian Biodiversity Portal (ATREE /
#         Ministry of Environment, Forest and Climate Change, Govt of India).
#         Search by scientific/common name; if a photo carries a barcode
#         we use zbarimg first (handled in run_photo_match).
# Tier 2: Pl@ntNet (French research org, NON-American) — for actual leaf
#         identification from a photo, since IBP does not expose a public
#         image-classification endpoint.  Key from plantid.conf.
indiabiodiversity_lookup() {
  local name="$1"
  [[ -z "$name" ]] && return 1
  local enc
  enc=$(urlencode "$name")
  local url="https://indiabiodiversity.org/api/v1/species?name=${enc}&limit=1"
  local body
  body=$(curl -sS --compressed --max-time 25 -A "plantid.sh/2.0 (India)" "$url" 2>/dev/null) || return 1
  local title img extract
  title=$(jq -r '.data[0].name // .data[0].commonName // empty' <<<"$body" 2>/dev/null)
  [[ -z "$title" ]] && return 1
  img=$(jq -r '.data[0].primaryImage.url // .data[0].images[0].url // empty' <<<"$body" 2>/dev/null)
  extract=$(jq -r '.data[0].description // .data[0].brief // "Indian Biodiversity Portal entry."' <<<"$body" 2>/dev/null)
  jq -cn \
    --arg t "$title" \
    --arg i "$img" \
    --arg e "$extract" \
    '{title:$t, extract:$e, thumbnail_url:$i, lang:"en",
      source:"indiabiodiversity.gov.in", confidence:"-"}'
}

plantnet_lookup() {
  local photo="$1"
  local key=""
  if [[ -f "$CONF_FILE" ]]; then
    key=$(awk -F= '/^[[:space:]]*PLANTNET_API_KEY[[:space:]]*=/{gsub(/[[:space:]].*/,"",$2);print $2;exit}' "$CONF_FILE" 2>/dev/null || true)
    key="${key#\"}"; key="${key%\"}"
  fi
  if [[ -z "$key" || "$key" == "YOUR_KEY_HERE" ]]; then
    printf '{"error":"nokey"}'
    return 1
  fi
  local url="https://my-api.plantnet.org/v2/identify/all?api-key=${key}"
  local body
  body=$(curl -sS --compressed --max-time 60 \
        -F "images=@${photo}" -F "organs=leaf" \
        "$url" 2>/dev/null) || {
    printf '{"error":"network"}'
    return 1
  }
  local sci common score img
  sci=$(jq -r '.results[0].species.scientificNameWithoutAuthor // empty' <<<"$body" 2>/dev/null)
  if [[ -z "$sci" ]]; then
    local emsg
    emsg=$(jq -r '.message // .error // empty' <<<"$body" 2>/dev/null)
    [[ -n "$emsg" ]] && warn "Pl@ntNet: $emsg" >&2
    printf '{"error":"nomatch"}'
    return 1
  fi
  common=$(jq -r '.results[0].species.commonNames | join(", ") // empty' <<<"$body")
  score=$(jq -r '.results[0].score // 0' <<<"$body")
  img=$(jq -r '.results[0].images[0].url // .results[0].images[0].osm_url // empty' <<<"$body" 2>/dev/null)
  local pct
  pct=$(awk -v s="$score" 'BEGIN{ printf "%.1f", (s+0)*100 }')
  jq -cn \
    --arg sci "$sci" \
    --arg common "$common" \
    --arg pct "$pct" \
    --arg img "$img" \
    '{title:$sci,
      extract:("Common names: " + ($common|length|if .>0 then $common else "(none)" end)
                + "  •  Source: Pl@ntNet (non-American, French research org)"),
      confidence:$pct, thumbnail_url:$img, lang:"en", source:"plantnet"}'
}

# ──────────────────────── Download an image ────────────────────────────────
download_image() {
  local url="$1" slug="$2"
  mkdir -p "$IMG_DIR"
  if [[ -z "$url" ]]; then
    return 0
  fi
  local dest="$IMG_DIR/${slug}.jpg"
  if curl -sS --compressed --max-time 30 -L -o "$dest" "$url" 2>/dev/null && [[ -s "$dest" ]]; then
    printf '%s' "$dest"
    return 0
  fi
  rm -f "$dest" 2>/dev/null || true
  return 0
}

# ──────────────────────── HTML log ──────────────────────────────────────────
html_header() {
  if [[ ! -f "$HTML_LOG" ]]; then
    cat > "$HTML_LOG" <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>plantid.sh — Match Log (India Edition)</title>
<style>
  :root { color-scheme: light dark; }
  body { font: 15px/1.6 -apple-system,Segoe UI,Roboto,"Noto Sans",sans-serif;
         max-width: 960px; margin: 0 auto; padding: 1.5rem; color: #1b1b1b; background:#fafafa; }
  h1 { font-size: 1.45rem; margin: 0 0 .25rem; }
  .sub { color:#666; font-size:.85rem; margin-bottom: 1.25rem; }
  .entry { border:1px solid #e3e3e3; border-radius:12px; background:#fff;
           padding:1rem 1.25rem; margin-bottom:1rem; display:flex; gap:1.25rem;
           box-shadow: 0 1px 3px rgba(0,0,0,.04); }
  .entry img { width:140px; height:140px; object-fit:cover; border-radius:10px;
               background:#eee; flex-shrink:0; }
  .entry .body { flex:1; min-width:0; }
  .entry .meta { font-size:.78rem; color:#777; margin-bottom:.35rem; }
  .entry .title { font-size:1.12rem; font-weight:600; margin:0 0 .35rem; word-break:break-word; }
  .entry .extract { font-size:.92rem; color:#333; word-break:break-word;
                    white-space:pre-wrap; line-height:1.5; }
  .entry .pill { display:inline-block; font-size:.7rem; padding:1px 8px;
                 border-radius:999px; background:#eef; color:#335; margin-left:.35rem; }
  .entry.fail { border-color:#f3c9c9; }
  .entry.fail .title { color:#a00; }
  .badge { display:inline-block; background:#0a7d28; color:#fff; font-size:.7rem;
           padding:2px 10px; border-radius:6px; margin-left:.5rem; vertical-align:middle; }
  @media (max-width: 560px){ .entry{flex-direction:column} .entry img{width:100%;height:180px} }
</style>
</head>
<body>
<h1>🌿 plantid.sh — Plant &amp; Pesticide Identifier Log</h1>
<div class="sub">🇮🇳 India Edition • Self-contained record of every match. Images embedded as base64.</div>
HTML
    printf '</body>\n</html>\n' >> "$HTML_LOG"
  fi
}

append_html() {
  html_header
  local ts="$1" input_type="$2" input_val="$3" lang="$4" \
        matched_title="$5" extract="$6" confidence="$7" \
        source="$8" img_path="$9" status_msg="${10}"

  local img_tag="<div class=\"img-placeholder\"></div>"
  if [[ -n "$img_path" && -f "$img_path" ]]; then
    local b64
    b64=$(b64 "$img_path")
    img_tag="<img src=\"data:image/jpeg;base64,${b64}\" alt=\"matched image\">"
  fi

  local cls="entry"
  [[ "$status_msg" == "no match" || "$status_msg" == *"no match"* ]] && cls="entry fail"

  # Escape user text for HTML — use printf to avoid trailing newlines that
  # python3 -c 'print(...)' would add (the original bug that misaligned the
  # HTML output).
  local esc_title esc_extract esc_input esc_status
  esc_title=$(printf '%s' "$matched_title" | python3 -c 'import sys,html;sys.stdout.write(html.escape(sys.stdin.read()))' 2>/dev/null || printf '%s' "$matched_title")
  esc_extract=$(printf '%s' "$extract" | python3 -c 'import sys,html;sys.stdout.write(html.escape(sys.stdin.read()))' 2>/dev/null || printf '%s' "$extract")
  esc_input=$(printf '%s' "$input_val" | python3 -c 'import sys,html;sys.stdout.write(html.escape(sys.stdin.read()))' 2>/dev/null || printf '%s' "$input_val")
  esc_status=$(printf '%s' "$status_msg" | python3 -c 'import sys,html;sys.stdout.write(html.escape(sys.stdin.read()))' 2>/dev/null || printf '%s' "$status_msg")

  local conf_pill=""
  [[ -n "$confidence" && "$confidence" != "-" ]] && conf_pill="<span class=\"pill\">confidence ${confidence}%</span>"

  local block
  block=$(cat <<HTML

<div class="${cls}">
  ${img_tag}
  <div class="body">
    <div class="meta">${ts}  •  ${input_type}  •  <b>${esc_input}</b>  •  ${lang}  •  ${source}  •  <span class="pill">${esc_status}</span></div>
    <div class="title">${esc_title}${conf_pill}<span class="badge">🇮🇳 India API</span></div>
    <div class="extract">${esc_extract}</div>
  </div>
</div>
HTML
)
  local tmp_new
  tmp_new="$TMP_DIR/html_new.html"
  {
    sed -e '/<\/body><\/html>/d' -e '/<\/body>$/d' -e '/<\/html>$/d' "$HTML_LOG"
    printf '%s\n' "$block"
    printf '</body>\n</html>\n'
  } > "$tmp_new"
  mv -f "$tmp_new" "$HTML_LOG"
}

# ──────────────────────── CSV log ──────────────────────────────────────────
csv_header_if_missing() {
  if [[ ! -f "$CSV_LOG" ]]; then
    printf 'timestamp,input_type,input_value,language,matched_name,confidence,source_api,image_path,status\n' > "$CSV_LOG"
  fi
}

csv_quote() {
  printf '"%s"' "${1//\"/\"\"}"
}

csv_append() {
  csv_header_if_missing
  local ts="$1" input_type="$2" input_val="$3" lang="$4" \
        matched_name="$5" confidence="$6" source_api="$7" \
        img_path="$8" status="$9"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$ts" \
    "$(csv_quote "$input_type")" \
    "$(csv_quote "$input_val")" \
    "$lang" \
    "$(csv_quote "$matched_name")" \
    "$confidence" \
    "$source_api" \
    "$(csv_quote "$img_path")" \
    "$(csv_quote "$status")" >> "$CSV_LOG"
}

# ──────────────────────── Terminal table (--log) ─────────────────────────
show_log_term() {
  if [[ ! -f "$CSV_LOG" ]]; then
    warn "no log yet — run a match first"
    return 0
  fi
  print_header "📋 Last Matches"
  printf '%s\n' "${C_BOLD}$(printf '%-20s %-10s %-22s %-6s %-26s %-7s %-12s' \
    "TIME" "TYPE" "INPUT" "LANG" "MATCHED" "CONF" "STATUS")${C_RESET}"
  print_divider

  # Skip the CSV header (first line) and show up to the last 10 entries.
  tail -n 10 "$CSV_LOG" | grep -v '^timestamp,' | while IFS=, read -r ts itype ival lang mname conf src img status; do
    [[ -z "$ts" ]] && continue
    ival=$(printf '%s' "$ival" | sed 's/"//g' | cut -c1-22)
    mname=$(printf '%s' "$mname" | sed 's/"//g' | cut -c1-26)
    [[ -z "$conf" ]] && conf="-"
    local colour="$C_GREEN"
    [[ "$status" == *"no match"* ]] && colour="$C_RED"
    printf '%-20s %-10s %-22s %-6s %-26s %-7s %s%s%s\n' \
      "${ts#\"}" "$(printf '%s' "$itype" | sed 's/"//g')" "$ival" "$lang" "$mname" "$conf" "$colour" "$(printf '%s' "$status" | sed 's/"//g')" "$C_RESET"
  done

  local latest_img
  latest_img=$(tail -n 20 "$CSV_LOG" | awk -F, '$8 != "" && $8 != "\"\"" {gsub(/"/,"",$8); print $8}' | tail -n1)
  if [[ -n "$latest_img" && -f "$latest_img" ]]; then
    echo
    status "🖼️  latest matched image: ${C_GREY}$latest_img${C_RESET}"
    if (( HAVE_CHAFA )); then
      chafa --size 60x20 "$latest_img" 2>/dev/null || \
        warn "chafa failed to render"
    else
      note "install 'chafa' to render the image inline in the terminal:"
      note "    sudo apt install chafa"
    fi
  fi
}

# ──────────────────────── Open HTML log (--log-html) ───────────────────────
open_html_log() {
  if [[ ! -f "$HTML_LOG" ]]; then
    warn "no HTML log yet — run a match first"
    exit 0
  fi
  if (( HAVE_XDG )); then
    xdg-open "$HTML_LOG" >/dev/null 2>&1 &
    ok_msg "opened ${C_BOLD}$HTML_LOG${C_RESET} in your browser"
  else
    warn "xdg-open not found — open this file manually in a browser:"
    printf '  %s\n' "$HTML_LOG"
  fi
}

# ──────────────────────── Match dispatcher ────────────────────────────────
run_name_match() {
  local name="$1" lang_override="$2"
  local lang
  lang=$(resolve_lang "$name" "$lang_override")
  local lang_label="${LANG_ENGLISH[$lang]:-English}"
  local lang_end="${LANG_NAME[$lang]:-English}"
  local script_name="${LANG_SCRIPT[$lang]:-ASCII}"
  local emoji="${LANG_EMOJI[$lang]:-🌱}"

  # If invoked from the pesticide menu, use a pesticide-styled header instead
  # of the generic NAME mode header — gives the user a clear visual cue that
  # they're in the dedicated pesticide section.
  if [[ ${INPUT_IS_PESTICIDE:-0} -eq 1 ]]; then
    print_header "🧪 PESTICIDE / Agrochemical Mode"
  else
    print_header "📝 NAME Mode • ${lang_label}"
  fi
  if [[ "$lang" != "en" ]]; then
    status "$(t "$lang" autodetected) ${C_BOLD}${lang_label}${C_RESET} (${lang_end}) — script: ${script_name}, code: ${C_CYAN}${lang}${C_RESET}"
  else
    status "Input language: ${C_BOLD}English${C_RESET} (ASCII), code: ${C_CYAN}en${C_RESET}"
  fi

  # ── PESTICIDE MODE: skip the direct Wikipedia lookup entirely and go
  # straight to the brand → active-ingredient fallback chain.  This makes
  # pesticide lookups FAST (no double 404 hop) and gives the user a single
  # unified result for any brand name.
  if [[ ${INPUT_IS_PESTICIDE:-0} -eq 1 && "$lang" == "en" ]]; then
    status "🔍  Looking deeper…"
    local result
    result=$(run_with_spinner "🧪  Resolving brand…" \
              pesticide_fallback_lookup "$name" "$lang")
    if [[ -n "$result" && "$result" == "{"* && "$result" != *'"error"'* ]]; then
      # Got a result — skip ahead to display
      :
    else
      warn "$(t "$lang" no_match)"
      csv_record_name "$name" "$lang" "" "" "pesticide-fallback" "" "no match"
      append_html_record_name "$name" "$lang" "" "" "" "pesticide-fallback" "" "no match"
      return $EC_NO_MATCH
    fi
  else
    # ── Normal NAME mode: direct Wikipedia lookup with the loader bar
    local result
    result=$(run_with_spinner "$(t "$lang" searching) …" \
              wiki_lookup "$name" "$lang")
  fi

  if [[ -z "$result" || "$result" != "{"* ]]; then
    err "Wikipedia lookup failed (no response from server)"
    csv_record_name "$name" "$lang" "" "" "wikipedia" "" "no match (network)"
    append_html_record_name "$name" "$lang" "" "" "" "wikipedia" "" "no match (network)"
    return $EC_NET
  fi
  local error
  error=$(jq -r '.error // empty' <<<"$result" 2>/dev/null || true)
  if [[ -n "$error" ]]; then
    if [[ "$error" == "network" ]]; then
      err "Wikipedia lookup failed (network error)"
      csv_record_name "$name" "$lang" "" "" "wikipedia" "" "no match (network)"
      append_html_record_name "$name" "$lang" "" "" "" "wikipedia" "" "no match (network)"
      return $EC_NET
    fi
    # ── nomatch → try pesticide brand-name fallback for English inputs ─────
    # Wikipedia rarely has articles on pesticide BRAND names like "Tata
    # Rallis Rilon".  If the input is English AND looks like a multi-word
    # product name (or contains a pesticide descriptor keyword), try the
    # brand→active-ingredient fallback before giving up.
    local lc_name="${name,,}"
    local looks_like_pesticide=0
    if [[ "$lc_name" == *insecticide* || "$lc_name" == *fungicide* || \
          "$lc_name" == *herbicide* || "$lc_name" == *pesticide* || \
          "$lc_name" == *nematicide* || "$lc_name" == *rodenticide* || \
          "$lc_name" == *acaricide* || "$lc_name" == *" sc"* || \
          "$lc_name" == *" ec"* || "$lc_name" == *" wg"* || \
          "$lc_name" == *" gr"* ]]; then
      looks_like_pesticide=1
    fi
    # Also trigger fallback for any multi-word English name that failed
    # (covers "Tata Rallis Rilon" without a descriptor suffix)
    local word_count=0
    [[ -n "$name" && "$name" == *' '* ]] && word_count=$(printf '%s' "$name" | wc -w)

    if [[ "$lang" == "en" && ( $looks_like_pesticide -eq 1 || $word_count -ge 2 ) ]]; then
      status "🔍  Looking deeper…"
      local fb_result
      fb_result=$(run_with_spinner "🧪  Resolving brand…" \
                  pesticide_fallback_lookup "$name" "$lang")
      if [[ -n "$fb_result" && "$fb_result" == "{"* ]]; then
        local fb_error
        fb_error=$(jq -r '.error // empty' <<<"$fb_result" 2>/dev/null || true)
        if [[ -z "$fb_error" ]]; then
          # Fallback succeeded — use this result
          result="$fb_result"
          error=""
        fi
      fi
    fi
    # If still no match after the fallback (or fallback was skipped):
    if [[ -n "$error" || "$result" == *'"error":"nomatch"'* ]]; then
      warn "$(t "$lang" no_match)"
      csv_record_name "$name" "$lang" "" "" "wikipedia" "" "no match"
      append_html_record_name "$name" "$lang" "" "" "" "wikipedia" "" "no match"
      return $EC_NO_MATCH
    fi
  fi

  local title extract thumb source
  title=$(jq -r '.title // ""' <<<"$result")
  extract=$(jq -r '.extract // ""' <<<"$result")
  thumb=$(jq -r '.thumbnail_url // ""' <<<"$result")
  source=$(jq -r '.source // "wikipedia"' <<<"$result")

  # Clean the extract — fixes the user-reported "extract appears twice" bug.
  extract=$(clean_text "$extract")

  # Download the matched image (with a small spinner)
  local slug img_path=""
  slug=$(printf 'name_%s_%s' "$lang" "$(date +%s)")
  img_path=$(run_with_spinner "🖼️  Downloading image…" download_image "$thumb" "$slug")
  [[ -z "$img_path" ]] && img_path=""

  # Display the result professionally  (source is hidden from the user;
  # it's still written to the CSV/HTML logs for audit).
  echo
  status "${emoji}  $(t "$lang" match_found): ${C_BOLD}${C_GREEN}${title}${C_RESET}"
  [[ -n "$img_path" && -f "$img_path" ]] && printf '%s\n' "${C_GREY}🖼️  image:${C_RESET} $img_path"
  print_divider
  if [[ -n "$extract" ]]; then
    printf '%s\n' "$extract"
  else
    printf '%s\n' "${C_GREY}(no extract available)${C_RESET}"
  fi
  print_divider
  echo

  # Optional: render inline if chafa present
  if [[ -n "$img_path" && -f "$img_path" && $HAVE_CHAFA -eq 1 ]]; then
    chafa --size 50x16 "$img_path" 2>/dev/null || true
  fi

  # Log it
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  csv_record_name "$name" "$lang" "$title" "-" "$source" "$img_path" "match"
  append_html_record_name "$name" "$lang" "$title" "$extract" "-" "$source" "$img_path" "match"

  ok_msg "$(t "$lang" logged)"
}

csv_record_name() {
  local name="$1" lang="$2" title="$3" _conf="$4" source="$5" img="$6" status="$7"
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  csv_append "$ts" "name" "$name" "$lang" "$title" "-" "$source" "$img" "$status"
}
append_html_record_name() {
  local name="$1" lang="$2" title="$3" extract="$4" _conf="$5" source="$6" img="$7" status="$8"
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  append_html "$ts" "name" "$name" "$lang" "$title" "$extract" "-" "$source" "$img" "$status"
}

# ──────────────────────── Barcode match ──────────────────────────────────
run_barcode_match() {
  local code="$1"
  [[ ! "$code" =~ ^[0-9]{6,14}$ ]] && die "barcode must be 6–14 digits" "$EC_BAD_INPUT"
  print_header "📦 BARCODE Mode"
  status "🔎 Looking up ${C_BOLD}${code}${C_RESET} …"
  local result
  result=$(run_with_spinner "🔎 Searching product databases…" barcode_lookup "$code")
  if [[ -z "$result" || "$result" != "{"* ]]; then
    err "Barcode lookup failed (no response from server)"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    csv_append "$ts" "barcode" "$code" "en" "" "-" "gs1+off" "" "no match (network)"
    append_html  "$ts" "barcode" "$code" "en" "(no response)" "" "-" "gs1+off" "" "no match (network)"
    return $EC_NET
  fi
  local error
  error=$(jq -r '.error // empty' <<<"$result" 2>/dev/null || true)
  if [[ -n "$error" ]]; then
    if [[ "$error" == "network" ]]; then
      err "Barcode lookup failed (network error)"
      local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
      csv_append "$ts" "barcode" "$code" "en" "" "-" "gs1+off" "" "no match (network)"
      append_html  "$ts" "barcode" "$code" "en" "(network error)" "" "-" "gs1+off" "" "no match (network)"
      return $EC_NET
    fi
    warn "No product found for barcode ${code}"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    csv_append "$ts" "barcode" "$code" "en" "" "-" "gs1+off" "" "no match"
    append_html  "$ts" "barcode" "$code" "en" "(no product)" "" "-" "gs1+off" "" "no match"
    return $EC_NO_MATCH
  fi
  local title extract thumb source
  title=$(jq -r '.title // ""' <<<"$result")
  extract=$(jq -r '.extract // ""' <<<"$result")
  thumb=$(jq -r '.thumbnail_url // ""' <<<"$result")
  source=$(jq -r '.source // "openfoodfacts"' <<<"$result")
  local slug img_path=""
  slug=$(printf 'barcode_%s_%s' "$code" "$(date +%s)")
  img_path=$(run_with_spinner "🖼️  Downloading product image…" download_image "$thumb" "$slug")
  [[ -z "$img_path" ]] && img_path=""
  echo
  status "🛒  $(t "${REQUESTED_LANG:-en}" match_found): ${C_BOLD}${C_GREEN}${title}${C_RESET}"
  [[ -n "$img_path" && -f "$img_path" ]] && printf '%s\n' "${C_GREY}🖼️  image:${C_RESET} $img_path"
  print_divider
  [[ -n "$extract" ]] && printf '%s\n' "$extract"
  print_divider
  echo
  if [[ -n "$img_path" && -f "$img_path" && $HAVE_CHAFA -eq 1 ]]; then
    chafa --size 50x16 "$img_path" 2>/dev/null || true
  fi
  local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
  csv_append "$ts" "barcode" "$code" "en" "$title" "-" "$source" "$img_path" "match"
  append_html  "$ts" "barcode" "$code" "en" "$title" "$extract" "-" "$source" "$img_path" "match"
  ok_msg "$(t "${REQUESTED_LANG:-en}" logged)"
}

# ──────────────────────── Photo match ─────────────────────────────────────
run_photo_match() {
  local photo="$1"
  [[ ! -f "$photo" ]] && die "photo file not found: $photo" "$EC_BAD_INPUT"

  print_header "📷 PHOTO Mode"

  # Step 1: try zbarimg FIRST — if a barcode is found, treat as product path
  if (( HAVE_ZBAR )); then
    local barcode
    barcode=$(zbarimg -q --raw "$photo" 2>/dev/null | head -n1 | tr -d '[:space:]')
    if [[ -n "$barcode" ]]; then
      barcode="${barcode#EAN-13-}"; barcode="${barcode#EAN-8-}"
      barcode="${barcode#UPC-A-}";   barcode="${barcode#UPC-E-}"
      status "📦  Barcode detected in photo: ${C_BOLD}${barcode}${C_RESET} — switching to product path"
      run_barcode_match "$barcode"
      return $?
    fi
  else
    note "zbarimg not installed — cannot detect a barcode inside the photo"
    note "    sudo apt install zbar-tools"
  fi

  # Step 2: no barcode → plant identification path
  status "🌿 No barcode found — identifying plant …"
  local result
  result=$(run_with_spinner "🌱 Uploading photo & classifying…" plantnet_lookup "$photo")
  if [[ -z "$result" || "$result" != "{"* ]]; then
    err "Plant identification failed (no response)"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    csv_append "$ts" "photo" "$photo" "en" "" "-" "plantnet" "" "no match (network)"
    append_html  "$ts" "photo" "$photo" "en" "(no response)" "" "-" "plantnet" "" "no match (network)"
    return $EC_NET
  fi
  local error
  error=$(jq -r '.error // empty' <<<"$result" 2>/dev/null || true)
  if [[ -n "$error" ]]; then
    if [[ "$error" == "network" ]]; then
      err "Plant identification failed (network error)"
      local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
      csv_append "$ts" "photo" "$photo" "en" "" "-" "plantnet" "" "no match (network)"
      append_html  "$ts" "photo" "$photo" "en" "(network error)" "" "-" "plantnet" "" "no match (network)"
      return $EC_NET
    fi
    if [[ "$error" == "nokey" ]]; then
      warn "Plant identification key not configured — see $CONF_FILE"
      warn "    Get a free key at https://my.plantnet.org/account/"
    else
      warn "No plant match."
    fi
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    csv_append "$ts" "photo" "$photo" "en" "" "-" "plantnet" "" "no match"
    append_html  "$ts" "photo" "$photo" "en" "(no match)" "" "-" "plantnet" "" "no match"
    return $EC_NO_MATCH
  fi
  local title extract conf thumb source
  title=$(jq -r '.title // ""' <<<"$result")
  extract=$(jq -r '.extract // ""' <<<"$result")
  conf=$(jq -r '.confidence // 0' <<<"$result")
  thumb=$(jq -r '.thumbnail_url // ""' <<<"$result")
  source=$(jq -r '.source // "plantnet"' <<<"$result")

  if awk -v c="$conf" 'BEGIN{exit !(c+0 < 20)}'; then
    warn "⚠️  low confidence (${conf}%) — result may be unreliable"
  fi

  local slug img_path=""
  slug=$(printf 'plant_%s_%s' "$(basename "$photo" | tr -c '[:alnum:]' '_')" "$(date +%s)")
  if [[ -n "$thumb" ]]; then
    img_path=$(run_with_spinner "🖼️  Downloading matched plant image…" download_image "$thumb" "$slug")
  fi
  [[ -z "$img_path" || ! -f "$img_path" ]] && img_path="$photo"

  echo
  status "🌿  $(t "${REQUESTED_LANG:-en}" match_found): ${C_BOLD}${C_GREEN}${title}${C_RESET}  ${C_GREY}(confidence ${conf}%)${C_RESET}"
  [[ -n "$img_path" && -f "$img_path" ]] && printf '%s\n' "${C_GREY}🖼️  image:${C_RESET} $img_path"
  print_divider
  [[ -n "$extract" ]] && printf '%s\n' "$extract"
  print_divider
  echo
  if [[ -n "$img_path" && -f "$img_path" && $HAVE_CHAFA -eq 1 ]]; then
    chafa --size 50x16 "$img_path" 2>/dev/null || true
  fi

  local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
  csv_append "$ts" "photo" "$photo" "en" "$title" "$conf" "plantnet" "$img_path" "match"
  append_html  "$ts" "photo" "$photo" "en" "$title" "$extract" "$conf" "plantnet" "$img_path" "match"
  ok_msg "$(t "${REQUESTED_LANG:-en}" logged)"
}

# ──────────────────────── Help ────────────────────────────────────────────
show_help() {
  cat <<'HELP'
plantid.sh — Multilingual Plant & Pesticide Identifier (India Edition v2.0)
=============================================================================
🌿 Identify plants, pesticides and packaged food from a NAME (any of the 22
scheduled Indian languages), a BARCODE, or a PHOTO. Multilingual output,
animated loading spinner, vegetable emojis, and a self-contained HTML log.

🇮🇳 INDIAN APIs (no American services):
  • Name path     → Indic Wikipedia (te/hi/ta/… .wikipedia.org) — authored by
                    Indian contributor communities in their native scripts.
                    Fallback translation via AI4Bharat Bhashini (Govt of India).
  • Barcode path  → GS1 India SmartSearch (https://smartsearch.gs1india.org),
                    with Open Food Facts (French non-profit, Indian catalogue)
                    as fallback.  UPCitemdb (American) has been REMOVED.
  • Photo path    → Pl@ntNet (French research org, NON-American) for leaf
                    classification.  No American image APIs used.

USAGE
  ./plantid.sh --name "தக்காளி"           # Tamil input, auto-detected
  ./plantid.sh --name "टमाटर" --lang mr    # Devanagari + Marathi override
  ./plantid.sh --name "چگونه"              # Urdu (Arabic script) auto-detected
  ./plantid.sh --barcode 8901234567890
  ./plantid.sh --photo leaf.jpg            # plant photo OR photo w/ a barcode
  ./plantid.sh --log                      # terminal table + render latest image
  ./plantid.sh --log-html                 # open HTML log in browser
  ./plantid.sh --help

EXAMPLES IN THREE SCRIPTS
  Devanagari :  ./plantid.sh --name "टमाटर" --lang mr   # मराठी (Marathi)
  Tamil      :  ./plantid.sh --name "தக்காளி"            # தமிழ்  (Tamil)
  English    :  ./plantid.sh --name "tomato"

LANGUAGE AUTO-DETECTION (--name mode)
  Unicode block of the first non-ASCII rune selects the DEFAULT language
  for that script. --lang overrides for sister languages (Hindi vs
  Marathi, Urdu vs Sindhi, etc.):
    0900-097F  Devanagari      → hi   (mr/sa/mai/ne/kok/brx/doi share it)
    0980-09FF  Bengali         → bn   (Assamese 'as' shares it)
    0A00-0A7F  Gurmukhi        → pa
    0A80-0AFF  Gujarati        → gu
    0B00-0B7F  Odia            → or
    0B80-0BFF  Tamil           → ta
    0C00-0C7F  Telugu          → te
    0C80-0CFF  Kannada         → kn
    0D00-0D7F  Malayalam       → ml
    0600-06FF  Arabic          → ur   (Sindhi 'sd', Kashmiri 'ks' share it)
    ABC0-ABFF  Meitei Mayek    → mni  (Manipuri)
    1C50-1C7F  Ol Chiki        → sat  (Santali)
    ASCII                       → en

THE 22 SCHEDULED LANGUAGE CODES
  hi Hindi   bn Bengali    te Telugu    mr Marathi     ta Tamil
  gu Gujarati  ur Urdu    kn Kannada  or Odia        ml Malayalam
  pa Punjabi   as Assamese  mai Maithili sa Sanskrit  ne Nepali
  kok Konkani  sd Sindhi   mni Manipuri brx Bodo     doi Dogri
  sat Santali  ks Kashmiri

NAME-MATCH FLOW
  1. Detect language → build Indic Wikipedia subdomain (e.g. te.wikipedia.org)
  2. Query REST API:
        https://{lang}.wikipedia.org/api/rest_v1/page/summary/{name}
     Returns title + extract ALREADY in the user's language + thumbnail URL.
  3. On 404: fall back to opensearch on the same wiki, retry top hit.
  4. Still nothing: translate to English via AI4Bharat Bhashini (Indian Gov),
     retry en.wikipedia.org, translate the extract BACK to user's language.
  5. Clean the extract (dedupe, collapse blank lines, trim).
  6. Download the thumbnail to matched_images/.
  7. Show the result with veggie emoji, dividers, and the matched image path.

BARCODE + PHOTO MODES
  --photo       : run 'zbarimg -q' FIRST; barcode found → product path,
                  else plant path.
  Product path  : GS1 India SmartSearch → Open Food Facts (Indian catalogue).
                  (UPCitemdb removed — was American.)
  Plant path    : Pl@ntNet identify API, key from plantid.conf
                  (curl -s --max-time 30 -F "images=@photo.jpg" -F "organs=leaf")
                  Top match parsed with jq: scientific name, common names,
                  score, image URL. Warns if score < 20%.

MULTILINGUAL OUTPUT
  • Result details come from the native Wikipedia in the user's language
    (free on the happy path).
  • UI status messages ("match found", "no match", warnings) are translated
    via AI4Bharat Bhashini (Indian Gov), cached in .cache/ so each language
    is translated only once.  Falls back to English on error.

LOADING SPINNER
  Every network call shows a veggie spinner with elapsed seconds:
      🍅 ⠙ Searching Wikipedia (te) … (3s)
  The spinner is silenced automatically when output is piped (no TTY).

LOGGING — images REQUIRED in the log
  • plantid_log.html : one styled entry per match — timestamp, input in the
                       ORIGINAL script, detected language, matched title,
                       extract, confidence, and THE MATCHED IMAGE embedded as
                       base64 (<img src="data:image/jpeg;base64,...">) — fully
                       self-contained, opens in any browser. Inline CSS.
  • plantid_log.csv : timestamp,input_type,input_value,language,matched_name,
                       confidence,source_api,image_path,status
  • --log           : aligned colour table of the last 10 entries + render the
                       latest matched image inline in the terminal via chafa.
  • --log-html      : xdg-open the HTML log.
  • Append-only — never overwrites.

ENGINEERING
  • set -euo pipefail; trap cleanup EXIT (temp files removed, images kept).
  • Deps: curl, jq, zbarimg (required for barcode-in-photo detection).
    Optional: chafa (terminal images), translate-shell (translation
    fallback) — probed with 'command -v'; degrade gracefully with a clear
    note and install commands.
  • plantid.conf holds the Pl@ntNet key (gitignored):
        PLANTNET_API_KEY=your_key_here
  • Exit codes: 0=match  1=no match  2=API/network  3=bad input

ENVIRONMENT
  PLANTID_CONF=/path/to/conf   override the default conf path

HELP
}

# ──────────────────────── Interactive quick-start (no args) ────────────────
print_quickstart_static() {
  cat <<EOF
plantid.sh — Multilingual Plant & Pesticide Identifier (India Edition v2.0)

No input given. Pick one:

  1. NAME     (any of the 22 Indian scheduled languages)
       ./plantid.sh --name "தக்காளி"            # Tamil (auto-detected)
       ./plantid.sh --name "टमाटर" --lang mr    # Marathi override
       ./plantid.sh --name "tomato"             # English

  2. BARCODE  (6–14 digits from a packaged product)
       ./plantid.sh --barcode 8901234567890

  3. PHOTO    (plant photo, OR a photo that contains a barcode)
       Save the image to disk, then:
       ./plantid.sh --photo leaf.jpg

Other:
       ./plantid.sh --log          # table view + render latest image in terminal
       ./plantid.sh --log-html     # open HTML log (with images) in browser
       ./plantid.sh --help         # full help

(Re-run in a real terminal for an interactive prompt.)
EOF
}

_guide_language() {
  printf '\n%s🌐 Pick an OUTPUT language%s (for status messages + native Wikipedia extract):\n' "${C_BOLD}" "${C_CYAN}"
  printf '   %s0%s) auto-detect from the input script (default)\n' "${C_BOLD}" "${C_RESET}"
  local i=1 code
  for code in hi bn te mr ta gu ur kn or ml pa as mai sa ne kok sd mni brx doi sat ks; do
    printf '  %2d) %s  %-14s %s\n' "$i" "$code" "${LANG_NAME[$code]}" "${LANG_ENGLISH[$code]}"
    i=$((i+1))
  done
  printf '\n'
  local pick=""
  read -rp 'Pick 0-22 or type a code (hi/te/en/…): ' pick || true
  pick="${pick,,}"
  pick="${pick//[[:space:]]/}"
  if [[ -z "$pick" || "$pick" == "0" ]]; then
    printf '   %s→ auto-detect (language inferred from the input script)%s\n' "$C_GREY" "$C_RESET"
    return
  fi
  if [[ -n "${LANG_NAME[$pick]:-}" || "$pick" == "en" ]]; then
    REQUESTED_LANG="$pick"
    if [[ "$pick" == "en" ]]; then
      printf '   %s→ en  English  selected.%s\n' "$C_GREEN" "$C_RESET"
    else
      printf '   %s→ %s  %s  (%s) selected.%s\n' "$C_GREEN" "$REQUESTED_LANG" "${LANG_NAME[$REQUESTED_LANG]}" "${LANG_ENGLISH[$REQUESTED_LANG]}" "$C_RESET"
    fi
    return
  fi
  if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= 22 )); then
    local -a lcodes=(hi bn te mr ta gu ur kn or ml pa as mai sa ne kok sd mni brx doi sat ks)
    REQUESTED_LANG="${lcodes[$((pick-1))]}"
    printf '   %s→ %s  %s  (%s) selected.%s\n' "$C_GREEN" "$REQUESTED_LANG" "${LANG_NAME[$REQUESTED_LANG]}" "${LANG_ENGLISH[$REQUESTED_LANG]}" "$C_RESET"
    return
  fi
  warn "invalid pick '$pick' — using auto-detect (tip: type a code like te/hi/mr, or a number 1-22)"
}

_guide_name() {
  local ol="${REQUESTED_LANG:-en}"
  printf '\n📝 %s\n' "$(t "$ol" name_hdr)"
  if [[ -n "$REQUESTED_LANG" && "$REQUESTED_LANG" != "en" ]]; then
    printf 'Language: %s (%s)\n\n' "${LANG_NAME[$REQUESTED_LANG]}" "${LANG_ENGLISH[$REQUESTED_LANG]}"
  else
    printf '(language is auto-detected from the script you type)\n\n'
  fi
  local nm=""
  read -rp "$(t "$ol" name_prompt)" nm || true
  nm="${nm#./plantid.sh --name }"
  nm="${nm#\"}"; nm="${nm%\"}"
  if [[ -z "$nm" ]]; then return; fi
  INPUT_NAME="$nm"
}

_guide_barcode() {
  local ol="${REQUESTED_LANG:-en}"
  printf '\n📦 %s\n' "$(t "$ol" bc_hdr)"
  printf '%s\n\n' "$(t "$ol" bc_how)"
  local bc=""
  read -rp "$(t "$ol" bc_prompt)" bc || true
  if [[ -z "$bc" ]]; then return; fi
  if [[ "$bc" == *"plantid"* || "$bc" == *"--barcode"* ]]; then
    local digits="${bc//[!0-9]/}"
    if [[ -n "$digits" ]]; then
      note "extracted digits '$digits' from your input"
      bc="$digits"
    fi
  fi
  INPUT_BARCODE="$bc"
}

_guide_photo() {
  local ol="${REQUESTED_LANG:-en}"
  printf '\n📷 %s\n' "$(t "$ol" ph_hdr)"
  printf '%s\n\n' "$(t "$ol" ph_how)"
  printf 'Image files in this folder:\n'
  local found=0 f
  for f in "$SCRIPT_DIR"/*.jpg "$SCRIPT_DIR"/*.jpeg "$SCRIPT_DIR"/*.png "$SCRIPT_DIR"/*.webp; do
    [[ -f "$f" ]] || continue
    printf '  %s\n' "$(basename "$f")"
    found=1
  done
  if [[ $found -eq 0 ]]; then
    printf '  (none — drop a .jpg/.png here and re-run)\n'
  fi
  printf '\n'
  local ph=""
  read -rp "$(t "$ol" ph_prompt)" ph || true
  if [[ -z "$ph" ]]; then return; fi
  ph="${ph#./plantid.sh --photo }"
  ph="${ph#\"}"; ph="${ph%\"}"
  if [[ ! -f "$ph" && -f "$SCRIPT_DIR/$ph" ]]; then
    ph="$SCRIPT_DIR/$ph"
  fi
  INPUT_PHOTO="$ph"
}

# ──────────────────────── Pesticide-specific guide ────────────────────────
# Dedicated pesticide section — always goes through the brand→active-ingredient
# fallback chain, regardless of whether the input "looks like" a pesticide.
# Examples it accepts:
#   "Tata Rallis Rilon"            → Chlorantraniliprole
#   "Confidor Insecticide"         → Imidacloprid
#   "Bavistin"                     → Carbendazim
#   "Rallis Coragen SC"            → Chlorantraniliprole
PESTICIDE_EMOJIS=("🧪" "🌾" "🐞" "🐛" "🍃" "🌱" "🪲" "🐝" "🦗" "🍅")
_guide_pesticide() {
  print_header "🧪 PESTICIDE / Agrochemical Mode"
  printf 'Type the brand name of the pesticide, fungicide, herbicide, or\n'
  printf 'agrochemical you want to identify.\n\n'
  printf '%sExamples:%s\n' "$C_BOLD" "$C_RESET"
  printf '  • Tata Rallis Rilon         (insecticide)\n'
  printf '  • Confidor Insecticide      (insecticide)\n'
  printf '  • Bavistin Fungicide        (fungicide)\n'
  printf '  • Tilt Propiconazole        (fungicide)\n'
  printf '  • Rallis Coragen            (insecticide)\n'
  printf '  • Pendimethalin             (herbicide — active ingredient)\n\n'
  local nm=""
  read -rp 'Enter brand name: ' nm || true
  if [[ -z "$nm" ]]; then return; fi
  INPUT_NAME="$nm"
  # Tag the input so run_name_match knows to ALWAYS go through the pesticide
  # fallback chain (even if a direct Wikipedia article exists — pesticides
  # usually don't have brand-name articles, but if they do, the user
  # probably wanted the active ingredient anyway).
  INPUT_IS_PESTICIDE=1
}

# ──────────────────────── Loop-until-exit interactive menu ────────────────
# Runs the chosen lookup, prints the result, then asks the user what to do
# next.  Only exits when the user types: q / quit / exit / no / n.
# Any other reply (Enter / y / yes / anything else) → back to the menu.
interactive_loop() {
  while true; do
    # Reset state for each iteration so a previous run doesn't bleed in.
    INPUT_NAME=""
    INPUT_BARCODE=""
    INPUT_PHOTO=""
    INPUT_IS_PESTICIDE=0
    REQUESTED_LANG=""

    printf '\n%s%s🌿 plantid.sh — Multilingual Plant & Pesticide Identifier%s\n' \
      "${C_BOLD}${C_CYAN}" "${C_BG_CYAN}" "${C_RESET}"
    printf '%s%s   🇮🇳 India Edition v3.0 • %s%s\n' \
      "${C_BOLD}${C_CYAN}" "" "$(date '+%Y-%m-%d %H:%M:%S')" "${C_RESET}"
    printf '\nWhat would you like to identify?\n\n'
    printf '  %s1%s) 🌱  A plant / crop by NAME         (any Indian language)\n' "$C_BOLD" "$C_RESET"
    printf '  %s2%s) 🧪  A PESTICIDE / agrochemical    (brand → ingredient)\n' "$C_BOLD" "$C_RESET"
    printf '  %s3%s) 📦  A packaged product by BARCODE\n' "$C_BOLD" "$C_RESET"
    printf '  %s4%s) 📷  A plant PHOTO  (or a photo containing a barcode)\n' "$C_BOLD" "$C_RESET"
    printf '\n'
    printf '%sType "q" / "quit" / "exit" at any prompt to leave.%s\n\n' "$C_GREY" "$C_RESET"

    local choice=""
    read -rp 'Pick 1/2/3/4  (h = help, q = quit): ' choice || true

    # Treat quit/exit anywhere as a hard exit.
    case "${choice,,}" in
      q|quit|exit)
        printf '\n%s👋 Goodbye!%s\n\n' "$C_CYAN" "$C_RESET"
        exit 0
        ;;
      h|help|"")
        show_help
        continue
        ;;
    esac

    case "$choice" in
      1) _guide_language; _guide_name ;;
      2) _guide_pesticide ;;
      3) _guide_language; _guide_barcode ;;
      4) _guide_language; _guide_photo ;;
      *) warn "invalid choice '$choice' — pick 1, 2, 3, or 4"; continue ;;
    esac

    # If the user pressed Enter on the inner prompts (no input collected),
    # ask if they want to do something else.
    if [[ -z "$INPUT_NAME" && -z "$INPUT_BARCODE" && -z "$INPUT_PHOTO" ]]; then
      printf '\n'
      read -rp 'No input given. Try again? (y/n): ' again || again="y"
      case "${again,,}" in
        n|no|q|quit|exit)
          printf '\n%s👋 Goodbye!%s\n\n' "$C_CYAN" "$C_RESET"
          exit 0
          ;;
        *) continue ;;
      esac
    fi

    # ── Dispatch the chosen lookup ───────────────────────────────────────
    if [[ -n "$INPUT_NAME" ]]; then
      run_name_match "$INPUT_NAME" "$REQUESTED_LANG" || true
    elif [[ -n "$INPUT_BARCODE" ]]; then
      run_barcode_match "$INPUT_BARCODE" || true
    elif [[ -n "$INPUT_PHOTO" ]]; then
      run_photo_match "$INPUT_PHOTO" || true
    fi

    # ── After the result, ask if the user wants another lookup ──────────
    printf '\n%s%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' \
      "$C_CYAN" "" "${C_RESET}"
    local again=""
    read -rp 'Identify something else? (Enter = yes, q/quit/exit = no): ' again || again="y"
    case "${again,,}" in
      n|no|q|quit|exit)
        printf '\n%s👋 Goodbye!%s\n\n' "$C_CYAN" "$C_RESET"
        exit 0
        ;;
      *)
        # Anything else (including empty Enter) → loop back to the menu.
        ;;
    esac
  done
}

# Old single-shot quickstart (used when stdin is NOT a TTY, e.g. piped).
show_quickstart() {
  if [[ ! -t 0 ]]; then
    print_quickstart_static
    exit 0
  fi
  interactive_loop
}

# ──────────────────────── Arg parsing ─────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)     INPUT_NAME="${2:-}"; shift 2 ;;
      --barcode)  INPUT_BARCODE="${2:-}"; shift 2 ;;
      --photo)    INPUT_PHOTO="${2:-}"; shift 2 ;;
      --lang)     REQUESTED_LANG="${2:-}"; shift 2 ;;
      --log)      DO_LOG=1; shift ;;
      --log-html) DO_LOG_HTML=1; shift ;;
      --help|-h)  DO_HELP=1; shift ;;
      --) shift; break ;;
      *) err "unknown option: $1"; DO_HELP=1; shift ;;
    esac
  done
}

# ──────────────────────── main() ──────────────────────────────────────────
main() {
  TMP_DIR=$(mktemp -d -t plantid.XXXXXX)
  probe_deps
  parse_args "$@"

  if (( DO_HELP )); then
    show_help
    exit 0
  fi
  if (( DO_LOG_HTML )); then
    open_html_log
    exit 0
  fi
  if (( DO_LOG )); then
    show_log_term
    exit 0
  fi

  local n=0
  [[ -n "$INPUT_NAME"    ]] && n=$((n+1))
  [[ -n "$INPUT_BARCODE" ]] && n=$((n+1))
  [[ -n "$INPUT_PHOTO"   ]] && n=$((n+1))
  if [[ $n -eq 0 ]]; then
    show_quickstart
    [[ -n "$INPUT_NAME"    ]] && n=$((n+1))
    [[ -n "$INPUT_BARCODE" ]] && n=$((n+1))
    [[ -n "$INPUT_PHOTO"   ]] && n=$((n+1))
    if [[ $n -eq 0 ]]; then
      exit 0
    fi
  fi
  if [[ $n -gt 1 ]]; then
    err "use only ONE of --name / --barcode / --photo"
    exit "$EC_BAD_INPUT"
  fi

  if [[ -n "$INPUT_NAME" ]]; then
    [[ -z "$INPUT_NAME" ]] && die "--name requires a value" "$EC_BAD_INPUT"
    run_name_match "$INPUT_NAME" "$REQUESTED_LANG"
    exit $?
  fi
  if [[ -n "$INPUT_BARCODE" ]]; then
    run_barcode_match "$INPUT_BARCODE"
    exit $?
  fi
  if [[ -n "$INPUT_PHOTO" ]]; then
    run_photo_match "$INPUT_PHOTO"
    exit $?
  fi
}

main "$@"
