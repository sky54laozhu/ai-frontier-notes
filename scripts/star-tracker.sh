#!/usr/bin/env bash
#
# star-tracker.sh — 记录 ai-frontier-notes 仓库的星标数据
# 用法: ./scripts/star-tracker.sh
# 数据写入: scripts/star-history.csv
#

set -euo pipefail

REPO="sky54laozhu/ai-frontier-notes"
CSV="$(dirname "$0")/star-history.csv"

# 首次运行创建 CSV 头
if [ ! -f "$CSV" ]; then
  echo "timestamp,stars,forks,watchers,open_issues" > "$CSV"
fi

# 用 gh api 拿数据
DATA=$(gh api "repos/$REPO" --jq '[.stargazers_count, .forks_count, .subscribers_count, .open_issues_count] | @csv')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "${TIMESTAMP},${DATA}" >> "$CSV"

# 输出当前状态（供 Loop 读取）
STARS=$(echo "$DATA" | cut -d',' -f1)
PREV_LINE=$(tail -2 "$CSV" | head -1)

if [ "$(wc -l < "$CSV")" -gt 2 ]; then
  PREV_STARS=$(echo "$PREV_LINE" | cut -d',' -f2)
  DIFF=$((STARS - PREV_STARS))
  echo "⭐ Stars: $STARS (${DIFF:+$DIFF} since last check)"
else
  echo "⭐ Stars: $STARS (first record)"
fi
