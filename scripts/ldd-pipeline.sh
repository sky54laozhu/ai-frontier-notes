#!/usr/bin/env bash
# LDD 五阶段自动编排脚本
# 每个阶段独立 session + 独立模型，天然实现上下文隔离和成本分层
#
# 用法:
#   ./scripts/ldd-pipeline.sh "你的需求描述"
#   ./scripts/ldd-pipeline.sh "构建一个 URL 短链接服务，支持自定义短码"
#
# 可选参数:
#   --skip-spec    跳过 Spec 阶段（已有 docs/spec.md）
#   --skip-plan    跳过 Plan 阶段（已有 docs/plan.md）
#   --dry-run      只打印命令不执行

set -euo pipefail

# ─── 配置 ───────────────────────────────────────────────
MODEL_SPEC="opus"       # Spec: 深度推理，需要 Opus
MODEL_PLAN="opus"       # Plan: 深度推理，需要 Opus
MODEL_BUILD="sonnet"    # Build: 编码主力，Sonnet 性价比最高
MODEL_REVIEW="sonnet"   # Review: 代码审查，Sonnet 够用
MODEL_ACCEPT="haiku"    # Accept: 验收检查，Haiku 便宜够用

DOCS_DIR="docs"
SPEC_FILE="$DOCS_DIR/spec.md"
PLAN_FILE="$DOCS_DIR/plan.md"
REVIEW_FILE="$DOCS_DIR/review.md"

# ─── 参数解析 ────────────────────────────────────────────
SKIP_SPEC=false
SKIP_PLAN=false
DRY_RUN=false
REQUIREMENT=""

for arg in "$@"; do
  case "$arg" in
    --skip-spec) SKIP_SPEC=true ;;
    --skip-plan) SKIP_PLAN=true ;;
    --dry-run)   DRY_RUN=true ;;
    *)           REQUIREMENT="$arg" ;;
  esac
done

if [[ -z "$REQUIREMENT" && "$SKIP_SPEC" == false ]]; then
  echo "用法: $0 \"需求描述\" [--skip-spec] [--skip-plan] [--dry-run]"
  exit 1
fi

# ─── 工具函数 ────────────────────────────────────────────
phase() {
  local name="$1" model="$2"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Phase: $name | Model: $model | $(date '+%H:%M:%S')"
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

check_file() {
  local file="$1" name="$2"
  if [[ ! -f "$file" ]]; then
    echo "ERROR: $name 未生成 ($file)"
    exit 1
  fi
  echo "OK: $name 已生成 ($(wc -l < "$file") 行)"
}

# ─── 准备 ────────────────────────────────────────────────
mkdir -p "$DOCS_DIR"
START_TIME=$(date +%s)

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║       LDD Pipeline - 五阶段自动编排              ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  Spec/Plan: $MODEL_SPEC (深度推理)                  ║"
echo "║  Build:     $MODEL_BUILD (编码主力)               ║"
echo "║  Review:    $MODEL_REVIEW (代码审查)               ║"
echo "║  Accept:    $MODEL_ACCEPT (验收检查)                ║"
echo "╚══════════════════════════════════════════════════╝"

# ─── Phase 1: Spec ───────────────────────────────────────
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
5. 验收测试清单（可自动化验证的条件）

要求：每个功能的验收条件必须是可测试的，不能模糊。
先读取 CLAUDE.md 了解项目约定。将结果写入 $SPEC_FILE。
"
  check_file "$SPEC_FILE" "Spec"
else
  echo "跳过 Spec 阶段（使用已有 $SPEC_FILE）"
  check_file "$SPEC_FILE" "Spec"
fi

# ─── Phase 2: Plan ───────────────────────────────────────
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
  check_file "$PLAN_FILE" "Plan"
else
  echo "跳过 Plan 阶段（使用已有 $PLAN_FILE）"
  check_file "$PLAN_FILE" "Plan"
fi

# ─── Phase 3: Build ─────────────────────────────────────
phase "Build" "$MODEL_BUILD"

# 读取 plan 中的任务数量，逐个执行
TASK_COUNT=$(grep -c '^\s*##\s*Task\|^\s*###\s*Task\|^\s*- \[ \]' "$PLAN_FILE" 2>/dev/null || echo "1")
echo "检测到约 $TASK_COUNT 个任务"

run_claude "$MODEL_BUILD" "
你是高级开发者。读取 $PLAN_FILE，按顺序实现所有任务。

规则：
- 先读取 CLAUDE.md 了解项目约定
- 按 Plan 中的顺序逐个实现
- 每完成一个任务，运行相关测试确保不破坏已有功能
- 如果测试失败，先修复再继续下一个任务
- 写完代码后运行完整测试套件
- 不要跳过任何任务
"

# ─── Phase 4: Review ─────────────────────────────────────
phase "Review" "$MODEL_REVIEW"
run_claude "$MODEL_REVIEW" "
你是代码审查专家。执行以下审查并将报告写入 $REVIEW_FILE：

1. 运行 git diff 查看所有改动
2. 检查每个改动文件：
   - 逻辑正确性
   - 边界条件处理
   - 安全漏洞（注入、XSS、认证绕过）
   - 性能问题
   - 是否符合 CLAUDE.md 中的项目规范
3. 运行测试套件，报告结果
4. 运行类型检查（如适用）

输出格式：
- 严重问题（必须修复）
- 建议改进（可选）
- 测试覆盖率评估
- 总体评价（PASS / NEEDS_FIX）

如果评价是 NEEDS_FIX，直接修复严重问题。
将审查报告写入 $REVIEW_FILE。
"

# ─── Phase 5: Accept ─────────────────────────────────────
phase "Accept" "$MODEL_ACCEPT"
run_claude "$MODEL_ACCEPT" "
你是 QA 工程师。读取 $SPEC_FILE 中的验收测试清单，逐条验证。

步骤：
1. 读取 $SPEC_FILE 中的验收条件
2. 对每个条件：启动服务（如需要）、执行验证、记录结果
3. 汇总：通过 / 失败 / 跳过

输出格式（直接打印到终端）：
  [PASS] 条件描述
  [FAIL] 条件描述 — 失败原因
  [SKIP] 条件描述 — 跳过原因

  总计: X/Y 通过
"

# ─── 完成 ────────────────────────────────────────────────
END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))
MINUTES=$(( DURATION / 60 ))
SECONDS=$(( DURATION % 60 ))

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Pipeline 完成！总耗时: ${MINUTES}m ${SECONDS}s"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  产出文件:"
echo "    Spec:   $SPEC_FILE"
echo "    Plan:   $PLAN_FILE"
echo "    Review: $REVIEW_FILE"
echo ""
