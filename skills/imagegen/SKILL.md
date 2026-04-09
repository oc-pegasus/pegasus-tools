---
name: imagegen
description: "Generate images via OpenRouter API (Gemini, FLUX, etc.). Use when user asks to create, generate, draw, or make an image, picture, avatar, illustration, diagram, or visual content. Supports text-to-image with configurable model, size, and output path."
---

# imagegen

Generate images using OpenRouter API.

## Usage

```bash
SKILL_DIR/scripts/imagegen.sh [OPTIONS] "prompt"
```

## Parameters

| Param | Required | Description |
|-------|----------|-------------|
| prompt | ✅ | Text description of the image |
| `-o PATH` | | Output file path (default: `~/.openclaw/workspace/imagegen-{timestamp}.png`) |
| `-m MODEL` | | Model override (default: from config) |
| `-s SIZE` | | `small` (512px, default), `medium` (1024px), `large` (original) |

## Config

`~/.config/openrouter/config.json` — needs `api_key`, optional `base_url` and `default_model`.

## Output

Script prints the saved file path on success. Default output goes to workspace for easy sending.

## Sending to User

Include `MEDIA:<filepath>` in your reply to send the generated image. File must be under workspace.

Example:
```
Here's your image!
MEDIA:/home/jianjun/.openclaw/workspace/imagegen-20260408-084900.png
```

## Defaults

- Size: `small` (512px wide, good for chat)
- Model: from config or `google/gemini-2.5-flash-image`
