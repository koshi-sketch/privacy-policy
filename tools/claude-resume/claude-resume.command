#!/bin/bash
# Claude 復帰ボタン
# 最近の Claude Code セッションをまとめて再開する。ダブルクリックで実行。
# 各セッションは新しい Terminal ウィンドウで `claude --resume <id> --remote-control` として開き、
# スマホの Claude アプリの元のセッションにつなぎ直す。
#   DAYS=30  … 何日以内に更新されたセッションを対象にするか
#   MAX=10   … 候補の最大数
#   ALL=1    … 選択画面を出さずに全部再開する（リモートから実行する時用）
#   DRY_RUN=1 … 実行せずに開くコマンドを表示するだけ

DAYS=${DAYS:-30}
MAX=${MAX:-10}
PROJECTS="$HOME/.claude/projects"
LOG="$HOME/Library/Logs/claude-resume.log"
mkdir -p "$(dirname "$LOG")"
exec 2>>"$LOG"
echo "=== $(date) ===" >&2

# 結果を必ず画面に出す（ウィンドウがすぐ閉じても分かるように）
say() {
  echo "$1"
  echo "$1" >&2
  [ -n "$DRY_RUN" ] && return
  osascript - "$1" >/dev/null <<'OSA'
on run argv
  activate
  display dialog (item 1 of argv) with title "Claude 復帰" buttons {"OK"} default button 1
end run
OSA
}

if [ ! -d "$PROJECTS" ]; then
  say "セッションが見つかりません: $PROJECTS"
  exit 1
fi

# 実行中のセッションは開き直さない
running=$(ps -axo command 2>/dev/null | grep -- '--resume' | grep -v grep)

ids=(); dirs=(); labels=()
n=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  # ほぼ空のセッションは除外
  [ "$(wc -c < "$f")" -lt 5000 ] && continue
  id=$(basename "$f" .jsonl)
  printf '%s\n' "$running" | grep -qF -- "$id" && continue
  dir=$(grep -m1 -o '"cwd":"[^"]*"' "$f" | cut -d'"' -f4)
  [ -d "$dir" ] || continue
  title=""
  for key in customTitle aiTitle summary; do
    title=$(grep -o "\"$key\":\"[^\"]*\"" "$f" | tail -1 | cut -d'"' -f4)
    [ -n "$title" ] && break
  done
  [ -z "$title" ] && title=$(basename "$dir")
  title=$(printf '%s' "$title" | tr -d '\\"' | cut -c1-60)
  n=$((n + 1))
  ids+=("$id"); dirs+=("$dir")
  labels+=("$(printf '%02d' "$n")  $title  [$(basename "$dir")]")
  [ "$n" -ge "$MAX" ] && break
done < <(find "$PROJECTS" -mindepth 2 -maxdepth 2 -name '*.jsonl' -mtime -"$DAYS" \
           -exec stat -f '%m %N' {} + 2>/dev/null | sort -rn | cut -d' ' -f2-)

if [ "$n" -eq 0 ]; then
  say "再開できるセッションがありません（${DAYS}日以内・実行中を除く）。
DAYS=60 などで期間を広げられます。"
  exit 0
fi

if [ -n "$DRY_RUN" ] || [ -n "$ALL" ]; then
  chosen=$(printf '%s\n' "${labels[@]}")
else
  chosen=$(osascript - "${labels[@]}" <<'OSA'
on run argv
  activate
  set r to choose from list argv with title "Claude 復帰" with prompt "再開するセッションを選んでください（全部選択済み）" default items argv OK button name "再開" with multiple selections allowed
  if r is false then return ""
  set AppleScript's text item delimiters to linefeed
  return r as text
end run
OSA
)
  st=$?
  if [ $st -ne 0 ]; then
    say "選択画面を出せませんでした（エラー $st）。
ログ: $LOG"
    exit 1
  fi
fi

[ -z "$chosen" ] && exit 0

while IFS= read -r line; do
  i=$((10#${line%%  *} - 1))
  dir=${dirs[$i]}
  cmd="cd '${dir//\'/\'\\\'\'}' && claude --resume ${ids[$i]} --remote-control"
  if [ -n "$DRY_RUN" ]; then
    echo "$cmd"
    continue
  fi
  echo "open: $cmd" >&2
  osascript - "$cmd" >/dev/null <<'OSA'
on run argv
  tell application "Terminal"
    activate
    do script (item 1 of argv)
  end tell
end run
OSA
  sleep 1
done <<< "$chosen"

# スリープで再び切れないように 12 時間スリープを抑止
if [ -z "$DRY_RUN" ] && ! pgrep -x caffeinate >/dev/null; then
  nohup caffeinate -i -t 43200 >/dev/null 2>&1 &
fi

say "$(printf '%s\n' "$chosen" | grep -c .) 件のセッションを再開しました。"
