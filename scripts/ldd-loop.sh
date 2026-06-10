#!/usr/bin/env bash
# LDD Loop Engineering 编排脚本
#
# 与 ldd-pipeline.sh（线性单次执行）不同，本脚本实现了 Loop Engineering 的核心模式：
#
#   ┌─────────────────────────────────────────────────────────────┐
#   │                                                             │
#   │   Spec ──→ Plan ──→ Build ──→ Review ──┬──→ Accept ──┬──→ Done
#   │     ↑                  ↑       │       │             │
#   │     │                  │   NEEDS_FIX   │    FAIL     │
#   │     │                  └───────┘       │             │
#   │     │                                  │             │
#   │     └──── SPEC_MISMATCH ───────────────┘             │
#   │                                                      │
#   │     外层 Loop: Accept 失败 → 回到 Build 重试          │
#   │     内层 Loop: Review 发现问题 → Build 修复           │
#   │     逃逸阀: 超过 MAX_RETRIES 次 → 人工介入            │
#   └─────────────────────────────────────────────────────────────┘
#
# 用法:
#   ./scripts/ldd-loop.sh "你的需求描述"
#   ./scripts/ldd-loop.sh "构建一个 URL 短链接服务" --max-retries 5
#   ./scripts/ldd-loop.sh "任意" --skip-spec --skip-plan
#   ./scripts/ldd-loop.sh "任意" --dry-run

set -euo pipefail

# ─── 配置 ───────────────────────────────────────────────
MODEL_SPEC="opus"
MODEL_PLAN="opus"
MODEL_BUILD="sonnet"
MODEL_REVIEW="sonnet"
MODEL_ACCEPT="haiku"

MAX_RETRIES=3           # 最大重试次数（逃逸阀）
MAX_REVIEW_FIXES=2      # Review → Build 内层循环上限

DOCS_DIR="docs"
SPEC_FILE="$DOCS_DIR/spec.md"
PLAN_FILE="$DOCS_DIR/plan.md"
REVIEW_FILE="$DOCS_DIR/review.md"
ACCEPT_FILE="$DOCS_DIR/accept.md"
LOOP_LOG="$DOCS_DIR/loop-log.md"

# ─── 参数解析 ────────────────────────────────────────────
SKIP_SPEC=false
SKIP_PLAN=false
DRY_RUN=false
REQUIREMENT=""

for arg in "$@"; do
  case "$arg" in
    --skip-spec)     SKIP_SPEC=true ;;
    --skip-plan)     SKIP_PLAN=true ;;
    --dry-run)       DRY_RUN=true ;;
    --max-retries=*) MAX_RETRIES="${arg#*=}" ;;
    --max-retries)   : ;; # 下一个 arg 处理
    *)
      if [[ "${PREV_ARG:-}" == "--max-retries" ]]; then
        MAX_RETRIES="$arg"
      else
        REQUIREMENT="$arg"
      fi
      ;;
  esac
  PREV_ARG="$arg"
done

if [[ -z "$REQUIREMENT" && "$SKIP_SPEC" == false ]]; then
  echo "用法: $0 \"需求描述\" [--skip-spec] [--skip-plan] [--max-retries N] [--dry-run]"
  exit 1
fi

# ─── 工具函数 ────────────────────────────────────────────
phase() {
  local name="$1" model="$2" iter="${3:-}"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if [[ -n "$iter" ]]; then
    echo "  Phase: $name (iter $iter) | Model: $model | $(date '+%H:%M:%S')"
  else
    echo "  Phase: $name | Model: $model | $(date '+%H:%M:%S')"
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

run_claude() {
  local model="$1"
  shift
  local prompt="$*"

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] claude -p --model $model \"${prompt:0:80}...\""
    return 0
  fi

  claude -p "$prompt" --model "$model"
}

# 捕获输出到变量，同时写文件
run_claude_capture() {
  local model="$1" output_file="$2"
  shift 2
  local prompt="$*"

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] claude -p --model $model → $output_file"
    echo "PASS" > "$output_file"
    return 0
  fi

  claude -p "$prompt" --model "$model" --output-format text | tee "$output_file"
}

check_file() {
  local file="$1" name="$2"
  if [[ ! -f "$file" ]]; then
    echo "ERROR: $name 未生成 ($file)"
    return 1
  fi
  echo "OK: $name 已生成 ($(wc -l < "$file") 行)"
}

log_loop() {
  local msg="$1"
  echo "[$(date '+%H:%M:%S')] $msg" | tee -a "$LOOP_LOG"
}

# 从 Review 报告中提取评价结果
extract_verdict() {
  local file="$1"
  if grep -qi "NEEDS_FIX\|needs.fix\|严重问题" "$file" 2>/dev/null; then
    echo "NEEDS_FIX"
  else
    echo "PASS"
  fi
}

# 从 Accept 报告中提取通过率
extract_accept_result() {
  local file="$1"
  if grep -qi "FAIL\|失败\|未通过" "$file" 2>/dev/null; then
    # 检查是否是 spec 层面的问题
    if grep -qi "SPEC_MISMATCH\|spec.*错误\|需求.*不符" "$file" 2>/dev/null; then
      echo "SPEC_MISMATCH"
    else
      echo "FAIL"
    fi
  else
    echo "PASS"
  fi
}

# ─── 准备 ────────────────────────────────────────────────
mkdir -p "$DOCS_DIR"
: > "$LOOP_LOG"
START_TIME=$(date +%s)

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║       LDD Loop Engineering - 闭环编排                ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  Spec/Plan : $MODEL_SPEC (深度推理)                     ║"
echo "║  Build     : $MODEL_BUILD (编码主力)                  ║"
echo "║  Review    : $MODEL_REVIEW (代码审查)                  ║"
echo "║  Accept    : $MODEL_ACCEPT (验收检查)                   ║"
echo "║  Max Retry : $MAX_RETRIES 次 (逃逸阀)                      ║"
echo "╚══════════════════════════════════════════════════════╝"

log_loop "Pipeline 启动"

# ─── Phase 1: Spec（只执行一次）──────────────────────────
if [[ "$SKIP_SPEC" == false ]]; then
  phase "Spec" "$MODEL_SPEC"
  run_claude "$MODEL_SPEC" "
你是产品架构师。根据以下需求，生成详细的产品规格文档并写入 $SPEC_FILE。

需求：$REQUIREMENT

文档结构：
1. 项目概述（一句话描述）
2. 核心功能列表（每个功能包含：描述、输入、输出、验收条件）
3. 技术约束（技术栈、性能要求、安全要求）
4. 非功能需求
5. 验收测试清单（每条必须是可自动化验证的断言，格式为：
   - [AC-01] 描述 | 验证命令或 HTTP 请求 | 期望结果
   ）

要求：每个验收条件必须机器可判定（返回码、响应体、文件存在性）。
先读取 CLAUDE.md 了解项目约定。将结果写入 $SPEC_FILE。
"
  check_file "$SPEC_FILE" "Spec" || exit 1
  log_loop "Spec 完成"
else
  echo "跳过 Spec（使用已有 $SPEC_FILE）"
  check_file "$SPEC_FILE" "Spec" || exit 1
fi

# ─── Phase 2: Plan（只执行一次）──────────────────────────
if [[ "$SKIP_PLAN" == false ]]; then
  phase "Plan" "$MODEL_PLAN"
  run_claude "$MODEL_PLAN" "
你是技术 Lead。读取 $SPEC_FILE，生成实现计划并写入 $PLAN_FILE。

计划结构：
1. 架构概览（组件图、数据流）
2. 任务拆分（每个任务包含：描述、涉及文件、依赖关系、预估复杂度）
3. 实现顺序（考虑依赖关系的拓扑排序）
4. 风险点和备选方案

要求：
- 每个任务粒度控制在 30 分钟以内可完成
- 标注哪些任务可以并行
- 先读取 CLAUDE.md 了解项目约定
将结果写入 $PLAN_FILE。
"
  check_file "$PLAN_FILE" "Plan" || exit 1
  log_loop "Plan 完成"
else
  echo "跳过 Plan（使用已有 $PLAN_FILE）"
  check_file "$PLAN_FILE" "Plan" || exit 1
fi

# ─── 外层 Loop: Build → Review → Accept ─────────────────
OUTER_ITER=0
PIPELINE_RESULT="FAIL"

while [[ "$PIPELINE_RESULT" != "PASS" && $OUTER_ITER -lt $MAX_RETRIES ]]; do
  OUTER_ITER=$((OUTER_ITER + 1))
  log_loop "=== 外层 Loop 第 $OUTER_ITER/$MAX_RETRIES 轮 ==="

  # ─── Phase 3: Build ───────────────────────────────────
  phase "Build" "$MODEL_BUILD" "$OUTER_ITER"

  if [[ $OUTER_ITER -eq 1 ]]; then
    # 第一轮：全量实现
    BUILD_PROMPT="
你是高级开发者。读取 $PLAN_FILE，按顺序实现所有任务。

规则：
- 先读取 CLAUDE.md 了解项目约定
- 按 Plan 中的顺序逐个实现
- 每完成一个任务，运行相关测试确保不破坏已有功能
- 如果测试失败，先修复再继续下一个任务
- 写完代码后运行完整测试套件
- 不要跳过任何任务
"
  else
    # 后续轮：只修复 Accept/Review 发现的问题
    BUILD_PROMPT="
你是高级开发者。上一轮验收/审查发现了问题，需要修复。

问题清单：$(cat "$ACCEPT_FILE" "$REVIEW_FILE" 2>/dev/null | grep -i 'FAIL\|NEEDS_FIX\|严重\|错误' | head -20)

规则：
- 先读取 CLAUDE.md 了解项目约定
- 读取 $REVIEW_FILE 和 $ACCEPT_FILE 了解具体问题
- 只修复上述问题，不做无关改动
- 修复后运行完整测试套件确认
"
  fi

  run_claude "$MODEL_BUILD" "$BUILD_PROMPT"
  log_loop "Build 完成 (iter $OUTER_ITER)"

  # ─── 内层 Loop: Review → Fix ──────────────────────────
  REVIEW_ITER=0
  REVIEW_VERDICT="NEEDS_FIX"

  while [[ "$REVIEW_VERDICT" == "NEEDS_FIX" && $REVIEW_ITER -lt $MAX_REVIEW_FIXES ]]; do
    REVIEW_ITER=$((REVIEW_ITER + 1))

    # ─── Phase 4: Review ────────────────────────────────
    phase "Review" "$MODEL_REVIEW" "$OUTER_ITER.$REVIEW_ITER"
    run_claude_capture "$MODEL_REVIEW" "$REVIEW_FILE" "
你是代码审查专家。执行以下审查并将报告写入 $REVIEW_FILE：

1. 运行 git diff 查看所有改动
2. 检查每个改动文件：
   - 逻辑正确性、边界条件
   - 安全漏洞（注入、XSS、认证绕过）
   - 性能问题
   - 是否符合 CLAUDE.md 中的项目规范
3. 运行测试套件，报告结果
4. 运行类型检查（如适用）

最后一行必须是以下之一（机器可解析）：
  VERDICT: PASS
  VERDICT: NEEDS_FIX

如果是 NEEDS_FIX，列出每个问题的文件名和行号。
将审查报告写入 $REVIEW_FILE。
"
    REVIEW_VERDICT=$(extract_verdict "$REVIEW_FILE")
    log_loop "Review 结果: $REVIEW_VERDICT (iter $OUTER_ITER.$REVIEW_ITER)"

    if [[ "$REVIEW_VERDICT" == "NEEDS_FIX" && $REVIEW_ITER -lt $MAX_REVIEW_FIXES ]]; then
      # 内层循环：回到 Build 修复
      phase "Build-Fix" "$MODEL_BUILD" "$OUTER_ITER.$REVIEW_ITER"
      run_claude "$MODEL_BUILD" "
你是高级开发者。Review 发现了以下问题，请修复：

$(cat "$REVIEW_FILE" | grep -A2 -i '严重\|NEEDS_FIX\|问题' | head -30)

规则：
- 只修复 Review 指出的问题
- 修复后运行测试确认
- 不做无关改动
"
      log_loop "Build-Fix 完成 (iter $OUTER_ITER.$REVIEW_ITER)"
    fi
  done

  if [[ "$REVIEW_VERDICT" == "NEEDS_FIX" ]]; then
    log_loop "WARNING: Review 内层循环用尽 ($MAX_REVIEW_FIXES 次)，继续 Accept"
  fi

  # ─── Phase 5: Accept ──────────────────────────────────
  phase "Accept" "$MODEL_ACCEPT" "$OUTER_ITER"
  run_claude_capture "$MODEL_ACCEPT" "$ACCEPT_FILE" "
你是 QA 工程师。读取 $SPEC_FILE 中的验收测试清单，逐条验证。

步骤：
1. 读取 $SPEC_FILE 中的验收条件
2. 对每个条件：启动服务（如需要）、执行验证、记录结果
3. 汇总

输出格式：
  [PASS] AC-xx: 条件描述
  [FAIL] AC-xx: 条件描述 — 失败原因
  [SKIP] AC-xx: 条件描述 — 跳过原因

最后一行必须是以下之一（机器可解析）：
  RESULT: PASS (X/Y)
  RESULT: FAIL (X/Y)
  RESULT: SPEC_MISMATCH — 描述

将结果写入 $ACCEPT_FILE。
"

  ACCEPT_RESULT=$(extract_accept_result "$ACCEPT_FILE")
  log_loop "Accept 结果: $ACCEPT_RESULT (iter $OUTER_ITER)"

  case "$ACCEPT_RESULT" in
    PASS)
      PIPELINE_RESULT="PASS"
      ;;
    SPEC_MISMATCH)
      log_loop "ERROR: Spec 层面的问题，需要人工介入修改 $SPEC_FILE"
      echo ""
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      echo "  SPEC_MISMATCH: 验收发现需求层面的问题"
      echo "  请人工修改 $SPEC_FILE 后重新运行："
      echo "  $0 \"$REQUIREMENT\" --skip-spec --skip-plan"
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      exit 2
      ;;
    FAIL)
      if [[ $OUTER_ITER -ge $MAX_RETRIES ]]; then
        log_loop "ERROR: 达到最大重试次数 ($MAX_RETRIES)，人工介入"
      else
        log_loop "Accept 失败，进入下一轮 Build → Review → Accept"
      fi
      ;;
  esac
done

# ─── 结果 ────────────────────────────────────────────────
END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))
MINUTES=$(( DURATION / 60 ))
SECONDS=$(( DURATION % 60 ))

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$PIPELINE_RESULT" == "PASS" ]]; then
  echo "  PASS — 验收通过！总耗时: ${MINUTES}m ${SECONDS}s | 循环: $OUTER_ITER 轮"
else
  echo "  FAIL — 达到重试上限。总耗时: ${MINUTES}m ${SECONDS}s | 循环: $OUTER_ITER 轮"
  echo "  请查看日志: $LOOP_LOG"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  产出文件:"
echo "    Spec:   $SPEC_FILE"
echo "    Plan:   $PLAN_FILE"
echo "    Review: $REVIEW_FILE"
echo "    Accept: $ACCEPT_FILE"
echo "    Log:    $LOOP_LOG"
echo ""
