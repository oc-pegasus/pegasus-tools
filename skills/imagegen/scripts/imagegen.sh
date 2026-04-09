#!/usr/bin/env bash
set -euo pipefail

CONFIG="$HOME/.config/openrouter/config.json"
DEFAULT_OUTPUT_DIR="$HOME/media/images"

usage() {
  cat <<EOF
Usage: imagegen [OPTIONS] "prompt"

Generate images via OpenRouter API and save locally.

Options:
  -o FILE   Output filename (default: ~/media/images/imagegen-{timestamp}.png)
  -m MODEL  Model to use (default: from config)
  -s SIZE   Size: small (512px), medium (1024px), large (original). Default: small
  --help    Show this help

Examples:
  imagegen "a flying horse in the stars"
  imagegen -o horse.png -s medium "a flying horse"
  imagegen -m google/gemini-2.5-flash-image -s large "cute cat"
EOF
  exit 0
}

# Parse args
OUTPUT=""
MODEL=""
SIZE="small"
PROMPT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage ;;
    -o) OUTPUT="$2"; shift 2 ;;
    -m) MODEL="$2"; shift 2 ;;
    -s) SIZE="$2"; shift 2 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) PROMPT="$1"; shift ;;
  esac
done

if [[ -z "${PROMPT:-}" ]]; then
  echo "Error: No prompt provided." >&2
  echo "Run 'imagegen --help' for usage." >&2
  exit 1
fi

# Validate size
case "$SIZE" in
  small|medium|large) ;;
  *) echo "Error: Invalid size '$SIZE'. Use small, medium, or large." >&2; exit 1 ;;
esac

# Read config
if [[ ! -f "$CONFIG" ]]; then
  echo "Error: Config not found at $CONFIG" >&2
  exit 1
fi

API_KEY=$(jq -r '.api_key' "$CONFIG")
BASE_URL=$(jq -r '.base_url // "https://openrouter.ai/api/v1"' "$CONFIG")
[[ -z "$MODEL" ]] && MODEL=$(jq -r '.default_model // "google/gemini-2.5-flash-image"' "$CONFIG")

if [[ -z "$API_KEY" || "$API_KEY" == "null" ]]; then
  echo "Error: No api_key in config." >&2
  exit 1
fi

# Default output to workspace
[[ -z "$OUTPUT" ]] && OUTPUT="${DEFAULT_OUTPUT_DIR}/imagegen-$(date +%Y%m%d-%H%M%S).png"

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT")"

echo "Generating image with model: $MODEL"
echo "Prompt: $PROMPT"
echo "Size: $SIZE"

# API call
RESPONSE=$(curl -sS --fail-with-body "${BASE_URL}/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg model "$MODEL" --arg prompt "$PROMPT" '{
    model: $model,
    messages: [{role: "user", content: $prompt}],
    modalities: ["image", "text"]
  }')" 2>&1) || {
  echo "Error: API request failed:" >&2
  echo "$RESPONSE" >&2
  exit 1
}

# Check for API error
if echo "$RESPONSE" | jq -e '.error' >/dev/null 2>&1; then
  echo "Error: API returned error:" >&2
  echo "$RESPONSE" | jq -r '.error.message // .error' >&2
  exit 1
fi

# Extract base64 image
DATA_URL=$(echo "$RESPONSE" | jq -r '.choices[0].message.images[0].image_url.url // empty' 2>/dev/null)

if [[ -z "$DATA_URL" ]]; then
  DATA_URL=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null | grep -oP 'data:image/[^"]+' | head -1) || true
fi

if [[ -z "$DATA_URL" ]]; then
  echo "Error: No image found in response." >&2
  echo "Response keys: $(echo "$RESPONSE" | jq -r '.choices[0].message | keys[]' 2>/dev/null)" >&2
  exit 1
fi

# Decode base64 data URL -> file
BASE64_DATA="${DATA_URL#*;base64,}"
echo "$BASE64_DATA" | base64 -d > "$OUTPUT" || {
  echo "Error: Failed to decode base64 image." >&2
  exit 1
}

ORIG_SIZE=$(stat -c%s "$OUTPUT" 2>/dev/null || stat -f%z "$OUTPUT")
echo "Original: $ORIG_SIZE bytes"

# Resize if needed
if [[ "$SIZE" != "large" ]]; then
  if command -v magick &>/dev/null; then
    CONVERT_CMD="magick"
  elif command -v convert &>/dev/null; then
    CONVERT_CMD="convert"
  else
    echo "⚠️  ImageMagick not found, skipping resize. Install with: sudo apt install imagemagick"
    echo "✅ Saved: $(realpath "$OUTPUT") ($ORIG_SIZE bytes)"
    exit 0
  fi

  case "$SIZE" in
    small)  MAX_WIDTH=512;  QUALITY=80 ;;
    medium) MAX_WIDTH=1024; QUALITY=85 ;;
  esac

  if $CONVERT_CMD -limit memory 256MB -limit map 512MB "$OUTPUT" -resize "${MAX_WIDTH}x>" -quality "$QUALITY" "$OUTPUT" 2>/dev/null; then
    FINAL_SIZE=$(stat -c%s "$OUTPUT" 2>/dev/null || stat -f%z "$OUTPUT")
    echo "Resized ($SIZE): $FINAL_SIZE bytes (${MAX_WIDTH}px wide, quality ${QUALITY}%)"
  else
    echo "⚠️  Resize failed (OOM or error), keeping original image."
  fi
fi

FINAL_SIZE=$(stat -c%s "$OUTPUT" 2>/dev/null || stat -f%z "$OUTPUT")
echo "✅ Saved: $(realpath "$OUTPUT") ($FINAL_SIZE bytes)"
