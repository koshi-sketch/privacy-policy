#!/bin/bash
# Claude 復帰ボタンをデスクトップに置く
set -e
URL="https://raw.githubusercontent.com/koshi-sketch/privacy-policy/claude/okiteruka-7iptju/tools/claude-resume/claude-resume.command"
DEST="$HOME/Desktop/Claude復帰.command"
curl -fsSL "$URL" -o "$DEST"
chmod +x "$DEST"
echo "デスクトップに「Claude復帰」を置きました。ダブルクリックで使えます。"
