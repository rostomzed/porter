#!/bin/zsh
# Porter test suite.
#
#   ./test.sh            full run: native engines + Office/iWork engines
#   ./test.sh --native   native engines only (what CI runs — GitHub's macOS
#                        runners have no Microsoft Office or iWork)
#
# Office tests are skipped automatically for engines that aren't installed.
set -u
cd "$(dirname "$0")/.."

NATIVE_ONLY=false
[[ "${1:-}" == "--native" ]] && NATIVE_ONLY=true

BIN="build/Porter.app/Contents/MacOS/Porter"
[[ -x "$BIN" ]] || ./scripts/build.sh

TMP=$(mktemp -d "${TMPDIR:-/tmp}/porter-tests.XXXXXX")
OUT="$TMP/out"
mkdir -p "$OUT"
trap 'rm -rf "$TMP"' EXIT

PASS=0 FAIL=0 SKIP=0

check() { # <label> <expected-pdf>
    if [[ -f "$2" ]] && (( $(stat -f%z "$2") > 500 )); then
        echo "  PASS  $1"; (( PASS += 1 ))
    else
        echo "  FAIL  $1"; (( FAIL += 1 ))
    fi
}

skip() { echo "  SKIP  $1 ($2 not installed)"; (( SKIP += 1 )); }

echo "==> CLI basics"
"$BIN" --version >/dev/null && echo "  PASS  --version" && (( PASS += 1 )) || { echo "  FAIL  --version"; (( FAIL += 1 )); }
"$BIN" --help | grep -q "Usage: porter" && echo "  PASS  --help" && (( PASS += 1 )) || { echo "  FAIL  --help"; (( FAIL += 1 )); }

echo "==> Native engines"
printf 'Hello Porter.\nSecond line with unicode: éàü — ok\n' > "$TMP/text.txt"
printf '# Title\n\nSome **bold** and a\n\n- list item\n' > "$TMP/markdown.md"
printf '<html><body><h1>Heading</h1><p>Paragraph with <b>bold</b>.</p></body></html>' > "$TMP/web.html"
cp docs/icon.png "$TMP/image.png"

"$BIN" -q -o "$OUT" "$TMP/text.txt" "$TMP/markdown.md" "$TMP/web.html" "$TMP/image.png" 2>/dev/null
check "txt      → pdf" "$OUT/text.pdf"
check "md       → pdf" "$OUT/markdown.pdf"
check "html     → pdf" "$OUT/web.pdf"
check "png      → pdf" "$OUT/image.pdf"

echo "==> Behavior"
# name collision: converting the same file again must produce "text 2.pdf"
"$BIN" -q -o "$OUT" "$TMP/text.txt" 2>/dev/null
check "collision → 'name 2.pdf'" "$OUT/text 2.pdf"

# Google pointer files must fail with a helpful message, not crash
echo '{"url":"https://docs.google.com/document/d/x/edit"}' > "$TMP/link.gdoc"
if "$BIN" -q -o "$OUT" "$TMP/link.gdoc" 2>"$TMP/gdoc.err"; then
    echo "  FAIL  .gdoc rejected (conversion unexpectedly succeeded)"; (( FAIL += 1 ))
elif grep -q "Google" "$TMP/gdoc.err"; then
    echo "  PASS  .gdoc rejected with helpful message"; (( PASS += 1 ))
else
    echo "  FAIL  .gdoc rejected but message unhelpful"; (( FAIL += 1 ))
fi

if ! $NATIVE_ONLY; then
    echo "==> Office / iWork engines"
    if [[ -d "/Applications/Microsoft Word.app" ]]; then
        textutil -convert doc  "$TMP/text.txt" -output "$TMP/word97.doc"   2>/dev/null
        textutil -convert docx "$TMP/text.txt" -output "$TMP/modern.docx"  2>/dev/null
        textutil -convert odt  "$TMP/text.txt" -output "$TMP/open.odt"     2>/dev/null
        "$BIN" -q -o "$OUT" "$TMP/word97.doc" "$TMP/modern.docx" "$TMP/open.odt" 2>/dev/null
        check "doc  (legacy, via Word) → pdf" "$OUT/word97.pdf"
        check "docx (via Word)         → pdf" "$OUT/modern.pdf"
        check "odt  (via Word)         → pdf" "$OUT/open.pdf"

        # Quarantined (downloaded) files trigger Word's Protected View, which
        # hangs scripted conversions unless Porter stages a clean copy.
        textutil -convert docx "$TMP/text.txt" -output "$TMP/downloaded.docx" 2>/dev/null
        xattr -w com.apple.quarantine "0081;00000000;Safari;" "$TMP/downloaded.docx"
        "$BIN" -q -o "$OUT" "$TMP/downloaded.docx" 2>/dev/null
        check "docx (quarantined)      → pdf" "$OUT/downloaded.pdf"

        # Sandboxed engines can't write to /tmp directly — Porter must stage
        # the output and move it itself.
        "$BIN" -q -o "$TMP/sandbox-out" "$TMP/modern.docx" 2>/dev/null
        check "output lands in /tmp dir     " "$TMP/sandbox-out/modern.pdf"
    else
        skip "doc/docx/odt" "Microsoft Word"
    fi

    if [[ -d "/Applications/Microsoft Excel.app" ]]; then
        printf 'name,qty\nwidget,2\ngadget,7\n' > "$TMP/table.csv"
        "$BIN" -q -o "$OUT" "$TMP/table.csv" tests/fixtures/legacy.xls 2>/dev/null
        check "csv  (via Excel)        → pdf" "$OUT/table.pdf"
        check "xls  (legacy, via Excel)→ pdf" "$OUT/legacy.pdf"
    else
        skip "csv/xls" "Microsoft Excel"
    fi

    if [[ -d "/Applications/Microsoft PowerPoint.app" ]]; then
        "$BIN" -q -o "$OUT" tests/fixtures/deck.pptx 2>/dev/null
        check "pptx (via PowerPoint)   → pdf" "$OUT/deck.pdf"
    else
        skip "pptx" "Microsoft PowerPoint"
    fi
fi

echo ""
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
(( FAIL == 0 ))
