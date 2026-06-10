---
title: '模型编排实战 —— 让正确的模型在正确的阶段自动上场'
slug: 07-model-orchestration
date: 2026-06-10
series: ai-frontier-notes
series_index: 7
keywords: [Claude Code, 模型切换, CC Switch, OpenRouter, 脚本编排, Loop Engineering, 多模型]
prev: 06-claude-code-stuck-guide
canonical: https://github.com/sky54laozhu/ai-frontier-notes/blob/main/docs/blog/zh/07-model-orchestration.md
---

# 模型编排实战 —— 让正确的模型在正确的阶段自动上场

> 前六篇讲了 Loop Engineering 的理论（01）、实战（02）、Hello World（03）、全生命周期 LDD（04）、Token 经济学（05）、卡顿排查（06）。这一篇解决第 05 篇留下的一个实操悬念：**"Spec 用 Opus、Build 用 Sonnet、Accept 用 Haiku"——说起来容易，做起来怎么自动化？** 答案是三层方案的组合：内置机制打底、社区工具增强、脚本编排兜底。

**章节跳转：**[问题](#问题手动-model-切不动) · [第一层：内置机制](#第一层claude-code-内置机制) · [第二层：社区工具](#第二层社区工具生态) · [第三层：脚本编排](#第三层脚本编排——唯一真正按阶段自动切的方案) · [组合拳](#组合拳三层配合使用) · [反直觉结论](#反直觉结论)

## 问题：手动 /model 切不动

第 05 篇给出了清晰的模型分层策略：

| Phase | 推荐模型 | 理由 |
|-------|---------|------|
| Spec/Plan | Opus | 深度推理，质量决定后续一切 |
| Build | Sonnet | 编码主力，性价比最高 |
| Review | Sonnet | 代码审查，够用 |
| Accept | Haiku | 验收检查，便宜 5 倍 |

操作方法写的是手动 `/model sonnet`、`/model opus`。在实际开发中有三个痛点：

1. **忘了切**：Build 阶段还挂着 Opus，发现时已经多花了 $3
2. **无法脚本化**：交互式 session 里 `/model` 不能写进 Shell 脚本
3. **想用其他厂商的模型**：DeepSeek 写代码很便宜，Gemini 有 2M 上下文——但 Claude Code 默认只认 Anthropic API

本文逐层解决这三个问题。

![模型控制的三个层次](../assets/img/07-model-control-layers.svg)

## 第一层：Claude Code 内置机制

Claude Code 提供了四种方式控制模型，**优先级从高到低**：

| 方式 | 作用域 | 能自动化？ | 能 session 内切？ |
|------|--------|:---:|:---:|
| `/model` 命令 | 当前 session | 否（手动） | 是 |
| `--model` CLI flag | 单次调用 | **是** | 否（启动时决定） |
| `ANTHROPIC_MODEL` 环境变量 | 当前 Shell | **是** | 否 |
| `settings.json` 中的 `model` | 持久默认 | **是**（改文件） | 否 |

### --model：脚本化的关键

```bash
# 非交互模式，每次调用指定模型
claude -p "生成 spec" --model opus
claude -p "实现代码" --model sonnet
claude -p "验收测试" --model haiku
```

这是唯一能在 Shell 脚本里按阶段切模型的官方方式。`-p`（print mode）让 Claude 执行完就退出，天然做到了上下文隔离——每次调用是独立 session。

### 环境变量：控制别名解析

```bash
ANTHROPIC_MODEL              # 默认模型
ANTHROPIC_DEFAULT_OPUS_MODEL  # /model opus 解析到什么
ANTHROPIC_DEFAULT_SONNET_MODEL # /model sonnet 解析到什么
ANTHROPIC_DEFAULT_HAIKU_MODEL  # /model haiku 解析到什么
CLAUDE_CODE_SUBAGENT_MODEL    # Subagent 用什么模型
```

### opusplan：内置的二级路由

```bash
claude --model opusplan
```

进入 Plan 模式（`/plan`）自动切 Opus，退出后自动切 Sonnet。零配置，覆盖了"Spec/Plan 用 Opus、Build 用 Sonnet"的核心需求。

### 局限

**Hooks 不能改模型，CLAUDE.md 不能指定模型。** 模型选择是配置层的事，不是 prompt 层的事。这意味着在一个交互式 session 里，没有任何方式根据"当前在做什么"自动切模型。

### --fallback-model：过载降级

```bash
claude -p "任务" --model opus --fallback-model sonnet,haiku
```

仅限 `-p` 模式。主模型过载时按顺序尝试 fallback——适合 CI 场景，保证流水线不因模型过载而中断。

## 第二层：社区工具生态

内置机制解决了"能切"，但没解决"方便切"和"跨厂商切"。社区工具填补了这个空白。

![模型编排工具全景对比](../assets/img/07-tool-landscape.svg)

### CC Switch — 桌面一站式管理器

[CC Switch](https://github.com/farion1231/cc-switch) 是目前最成熟的 Claude Code 配置管理工具。Tauri 2 构建，跨平台。

**核心能力**：

- **50+ Provider 预置**：AWS Bedrock、OpenRouter、DeepSeek、Kimi、GLM、Qwen、硅基流动、火山引擎……一键导入 API Key
- **一键切换**：主界面或系统托盘点一下就切，Claude Code 支持热切换无需重启终端
- **角色映射（Role Mapping）**：v3.15+ 支持按角色（sonnet/opus/haiku）映射到不同模型，对应 `ANTHROPIC_DEFAULT_*_MODEL` 环境变量
- **本地代理 + 自动故障转移**：Provider A 挂了自动切 Provider B
- **用量追踪**：按模型/Provider 统计花费、请求数、Token 数

**CC Switch 的模型映射面板**直接对应第 05 篇的策略：

| CC Switch 字段 | 推荐值 | 对应环境变量 |
|---------------|--------|-------------|
| 主模型 | `claude-sonnet-4-6` | `ANTHROPIC_MODEL` |
| 推理模型 (Thinking) | `claude-opus-4.6` | — |
| Haiku 默认模型 | `claude-haiku-4-5` | `ANTHROPIC_DEFAULT_HAIKU_MODEL` |
| Sonnet 默认模型 | `claude-sonnet-4-6` | `ANTHROPIC_DEFAULT_SONNET_MODEL` |
| Opus 默认模型 | `claude-opus-4.6` | `ANTHROPIC_DEFAULT_OPUS_MODEL` |

设完后 `/model haiku`、`/model sonnet`、`/model opus` 才真正切到不同模型。

```bash
# macOS 安装
brew install --cask cc-switch
```

> ⚠️ **安全提醒**：CC Switch 有多个仿冒网站。**唯一官网是 ccswitch.io**，唯一源码在 `farion1231/cc-switch`。

### Claude Code Router — 请求级自动路由

[Claude Code Router](https://github.com/musistudio/claude-code-router)（31.4k stars）是本地代理，绑定 `127.0.0.1:3456`，拦截 Claude Code 的请求，按规则路由到不同模型/厂商。

**与 CC Switch 的区别**：CC Switch 是配置管理器（你手动切），Router 是代理（它根据规则自动切）。

- 按任务类型路由（background task → Haiku，reasoning → Opus）
- 按上下文长度路由（超长上下文 → Gemini 2M 窗口）
- 支持 OpenRouter、DeepSeek、Ollama、Gemini 等后端
- 开发者报告 **50-99% 成本下降**

### ccproxy — 高级 Hook 管线

[ccproxy](https://github.com/starbased-co/ccproxy) 更底层，用 DAG 驱动的 hook 管线拦截请求。`model_router` hook 可以动态改写请求中的 model 字段。能做到：大上下文请求路由到 Gemini，搜索请求路由到 Perplexity——Claude Code 全程以为自己在和 Anthropic API 对话。

### OpenRouter — 500+ 模型云端网关

[OpenRouter](https://openrouter.ai/) 提供单一 API 端点，背后聚合了 500+ 模型、60+ 厂商。

**核心路由能力**：

- **Auto Router**（`openrouter/auto`）：ML 元模型分析你的 prompt，自动选最优模型
- **Fusion**：同一个 prompt 发给多个模型，judge 模型综合最终答案
- **Model Fallbacks**：主模型出错自动切备选

**接入 Claude Code**：设置 `ANTHROPIC_BASE_URL` 指向 OpenRouter 端点即可。

### LiteLLM — 企业级代理

[LiteLLM](https://docs.litellm.ai/) 翻译 API 格式。Claude Code 说 Anthropic 协议，后端可以是 Azure、Bedrock、Vertex AI、Ollama。企业合规场景的标准选择。

设 `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1` 可让 `/model` 菜单显示 LiteLLM 托管的所有模型。

> ⚠️ **注意**：LiteLLM 1.82.7-1.82.8（2026 年 3 月）发生过供应链安全事件，务必用 >= 1.83.0。非 Anthropic 模型在复杂 agentic 任务中的质量会降低——工具调用准确率、文件路径正确性都受影响。

### 9Router — 编码工具专用网关

[9Router](https://github.com/9router/9router) 是专为 AI 编码工具设计的本地网关（`localhost:20128`），支持 Claude Code、Codex、Cursor、Cline 等。内置 Token 压缩（宣称省 20-40% 输入 Token）。

### 工具选择决策

| 你的需求 | 推荐工具 |
|---------|---------|
| 最低门槛，先用起来 | Claude Code 内置 `opusplan` |
| 方便切换，有 GUI | CC Switch |
| 想用 DeepSeek/Gemini 省钱 | Claude Code Router |
| 企业合规，走 Azure/Bedrock | LiteLLM |
| 全自动选最优模型 | OpenRouter Auto Router |
| 按开发阶段完全自动切 | **脚本编排**（见下一节） |

## 第三层：脚本编排——唯一真正按阶段自动切的方案

前两层的工具都有一个共同限制：**它们不知道你当前在哪个开发阶段**。CC Switch 按你手动点击切换，Router 按请求特征路由，OpenRouter 按 prompt 内容选模型——没有一个工具能说"这是 Spec 阶段所以用 Opus，这是 Build 阶段所以用 Sonnet"。

**唯一能做到"按阶段自动切"的方案是 Shell 脚本编排**：每个阶段一个 `claude -p --model` 调用。

![LDD Loop 编排流程图](../assets/img/07-loop-pipeline.svg)

### 线性版：ldd-pipeline.sh

最简单的版本——五个阶段顺序执行，每个阶段用不同模型，跑完即止。

```bash
#!/usr/bin/env bash
set -euo pipefail

# 每个阶段的模型配置
MODEL_SPEC="opus"
MODEL_PLAN="opus"
MODEL_BUILD="sonnet"
MODEL_REVIEW="sonnet"
MODEL_ACCEPT="haiku"

# Phase 1: Spec（Opus 深度推理，生成 docs/spec.md）
claude -p "读取 CLAUDE.md。根据需求生成 docs/spec.md..." --model $MODEL_SPEC

# Phase 2: Plan（Opus 深度推理，生成 docs/plan.md）
claude -p "读取 docs/spec.md，生成 docs/plan.md..." --model $MODEL_PLAN

# Phase 3: Build（Sonnet 编码主力）
claude -p "读取 docs/plan.md，实现所有任务..." --model $MODEL_BUILD

# Phase 4: Review（Sonnet 代码审查）
claude -p "审查代码，git diff main...HEAD..." --model $MODEL_REVIEW

# Phase 5: Accept（Haiku 验收检查）
claude -p "读取 docs/spec.md 中的验收清单，逐条验证..." --model $MODEL_ACCEPT
```

**天然的双重隔离**：

1. **模型隔离**：每个阶段用最合适的模型
2. **上下文隔离**：`claude -p` 每次调用是独立 session，不背历史包袱

这就是第 05 篇"每个 Phase 独立 `/clear`"的自动化版本。

### Loop 版：ldd-loop.sh

线性版的问题：Review 发现 Bug 怎么办？Accept 失败怎么办？——跑完就结束了，没有闭环。

Loop 版加入了 Loop Engineering 的核心模式——**双层闭环 + 逃逸阀**：

```
Spec → Plan → ┌─→ Build → Review ──┐──→ Accept ──┐──→ Done
              │          ↑  │      │        │     │
              │          └──┘      │    FAIL │     │
              │       内层Loop     │        │     │
              │    (NEEDS_FIX      │        │     │
              │     → Build修复)   │        │     │
              │                    │        │     │
              └────────────────────┘────────┘     │
                    外层Loop                      │
                 (Accept失败→重新Build)           PASS
```

**三个关键机制**：

| 机制 | 触发条件 | 行为 |
|------|---------|------|
| **内层 Loop** | Review 返回 `NEEDS_FIX` | Build 只修复 Review 指出的问题，再 Review |
| **外层 Loop** | Accept 返回 `FAIL` | 带着失败信息回到 Build 重新修复 |
| **逃逸阀** | 超过 `MAX_RETRIES` 次 | 停止循环，要求人工介入 |

核心代码片段：

```bash
# 外层 Loop: Build → Review → Accept
while [[ "$PIPELINE_RESULT" != "PASS" && $OUTER_ITER -lt $MAX_RETRIES ]]; do
  OUTER_ITER=$((OUTER_ITER + 1))

  # Build（第一轮全量实现，后续轮只修复问题）
  if [[ $OUTER_ITER -eq 1 ]]; then
    claude -p "读取 plan，实现所有任务" --model sonnet
  else
    claude -p "读取 accept/review 报告，修复失败项" --model sonnet
  fi

  # 内层 Loop: Review → Fix
  REVIEW_ITER=0
  while [[ "$REVIEW_VERDICT" == "NEEDS_FIX" && $REVIEW_ITER -lt $MAX_REVIEW_FIXES ]]; do
    claude -p "审查代码，输出 VERDICT: PASS 或 NEEDS_FIX" --model sonnet
    if [[ "$REVIEW_VERDICT" == "NEEDS_FIX" ]]; then
      claude -p "修复 Review 指出的问题" --model sonnet
    fi
  done

  # Accept
  claude -p "逐条验证 spec 中的验收条件" --model haiku
  # 结果是 PASS → 退出循环；FAIL → 继续外层循环
done
```

**逃逸阀是 Loop Engineering 的安全底线**——没有它，AI 可能在同一个 Bug 上无限循环。默认 3 次外层重试 + 2 次内层修复，超过就强制停下来让人看。

### 用法

```bash
# 完整五阶段 + Loop 闭环
./scripts/ldd-loop.sh "构建一个 URL 短链接服务，支持自定义短码"

# 先看流程（不执行）
./scripts/ldd-loop.sh "任意" --dry-run

# 已有 spec + plan，只跑 Build → Review → Accept 闭环
./scripts/ldd-loop.sh "任意" --skip-spec --skip-plan

# 允许更多重试
./scripts/ldd-loop.sh "任意" --max-retries 5
```

## 组合拳：三层配合使用

三层方案不是互斥的，而是分场景组合：

| 场景 | 推荐组合 | 理由 |
|------|---------|------|
| **日常交互开发** | CC Switch + `opusplan` | 托盘一键切 Provider，opusplan 自动二级路由 |
| **批量任务 / CI** | `ldd-loop.sh` + `--fallback-model` | 脚本按阶段切模型，fallback 防过载 |
| **极致成本优化** | Claude Code Router + DeepSeek 后端 | 简单任务自动路由到便宜模型 |
| **企业合规** | LiteLLM + Azure/Bedrock | API 翻译，走内部审批的云服务 |
| **多模型合议** | OpenRouter Fusion | 重要决策让多个模型投票 |

**最常见的组合**：CC Switch 管日常的 Provider 切换 + 脚本编排管 CI/批量任务。这覆盖了 90% 的场景。

## 反直觉结论

> **最大的浪费不是模型选错，是流水线没闭环。**

用了 CC Switch、配好了角色映射、每个阶段都用了最合适的模型——但如果 Accept 失败没有人管、Review 发现问题没有回到 Build 修复，那省下的模型差价远不够覆盖返工成本。第 05 篇说"返工比模型差价贵 10 倍"，本篇补上后半句：**自动闭环比手动修复快 10 倍**。脚本编排的价值不只是"自动切模型"，更是"自动重试直到过验收"。

更反直觉的：**工具不是越多越好**。CC Switch + 脚本编排已经覆盖了绝大多数场景。加了 Router 加了 LiteLLM 加了 OpenRouter——每多一层代理就多一个故障点、多一个延迟源。除非你真的需要"请求级自动路由到非 Anthropic 模型"，否则不需要三层全上。

最反直觉的：**非 Anthropic 模型看起来便宜，但在 agentic 场景的质量损失可能抵消成本节省**。Claude Code 的工具调用、文件路径解析、多步推理都是针对 Anthropic 模型优化的。换成 DeepSeek 或 Gemini 做 Build，单价便宜了，但工具调用失败率上升 → 重试次数增加 → 总 Token 反而更多。**便宜的模型 × 更多的重试 = 未必比贵模型 × 一次成功 更省钱**。在你实测验证之前，不要假设"换便宜模型一定省钱"。

---

## 配图

1. ![模型控制的三个层次](../assets/img/07-model-control-layers.svg)
2. ![模型编排工具全景对比](../assets/img/07-tool-landscape.svg)
3. ![LDD Loop 编排流程图](../assets/img/07-loop-pipeline.svg)

---

📌 系列阅读地图：[reading-map.md](../reading-map.md)
🔗 上一篇: [06 Claude Code 卡顿排查](./06-claude-code-stuck-guide.md)
