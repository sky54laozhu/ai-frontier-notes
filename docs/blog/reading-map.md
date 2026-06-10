# AI Frontier Notes 系列阅读地图

> **AI 新技术深度调研与工程拆解 — 每篇从"朴素方案为什么不行"讲到真实工程落地**
>
> 调研方法：多 Agent 并行搜索 → 源去重 → 声明提取 → 三票制对抗验证 → 综合报告

## 中文版 · 阅读顺序

| 系列 | 篇 | 标题 | 一句话 |
|------|----|------|--------|
| **Loop Engineering** | 01 | [Loop Engineering](zh/01-loop-engineering.md) | 从"我来 prompt"到"系统替我 prompt"的范式跳跃 |
| | 02 | [Loop Engineering 实战](zh/02-loop-engineering-in-practice.md) | 从零用 Loop 造一个自动 Bug 修复系统 |
| | 03 | [Hello World: 星标监控](zh/03-loop-hello-world-star-tracker.md) | 30 行脚本 + 一条命令，10 分钟造你的第一个 Loop |
| | 04 | [Loop-Driven Development](zh/04-loop-driven-development.md) | 用 5 个 Loop 跑完从 Spec 到验收的全过程 |
| | 05 | [Token 经济学](zh/05-token-optimization.md) | Claude Code 全流程开发的成本优化手册 |
| | 06 | [Claude Code 卡顿排查](zh/06-claude-code-stuck-guide.md) | 六大根因 + 诊断决策树 + 恢复工具箱 |
| | 07 | [模型编排实战](zh/07-model-orchestration.md) | 让正确的模型在正确的阶段自动上场 |

## English · Reading Order

| Series | # | Title | One-liner |
|--------|---|-------|-----------|
| **Loop Engineering** | 01 | [Loop Engineering](en/01-loop-engineering.md) | From "I prompt the agent" to "the system prompts the agent" |
| | 02 | [Loop Engineering in Practice](en/02-loop-engineering-in-practice.md) | Building an auto bug-fix system step by step |
| | 03 | [Hello World: Star Tracker](en/03-loop-hello-world-star-tracker.md) | 30 lines + one command, your first Loop in 10 minutes |
| | 04 | [Loop-Driven Development](zh/04-loop-driven-development.md) | 5 Loops from Spec to acceptance, full lifecycle |
| | 05 | [Token Economics](en/05-token-optimization.md) | Cost optimization playbook for full-lifecycle Claude Code dev |
| | 06 | [Claude Code Stuck Guide](en/06-claude-code-stuck-guide.md) | Six root causes + diagnosis flowchart + recovery toolkit |
| | 07 | [Model Orchestration](en/07-model-orchestration.md) | Putting the right model on the right phase, automatically |

## 按"我想了解 X"反查

- **什么是 Loop Engineering**：01
- **Boris Cherny / Addy Osmani 说了什么**：01 § 问题陈述
- **Loop 的五大构件**：01 § 五大构件
- **Loop 和 Harness 的关系**：01 § 概念栈
- **ReAct 模式**：01 § 学术根基
- **控制论 + Agent**：01 § 学术根基 · McGill
- **Loop 的工程陷阱**：01 § 工程陷阱
- **10 分钟第一个 Loop**：03
- **怎么上手第一个 Loop**：03 → 02 § 下一步
- **CLAUDE.md 怎么写**：02 § Step 1
- **Maker/Checker 怎么拆**：02 § Step 3
- **Loop 的调度方式选择**：02 § Step 5
- **Memory 怎么设计**：02 § Step 6
- **全生命周期 Loop**：04
- **Spec 到验收的五阶段**：04 § 核心思路
- **人类门禁放在哪里**：04 § 五个 Loop 的编排
- **Loop-Driven Development**：04
- **Token 怎么省**：05
- **Claude Code 成本优化**：05
- **模型怎么选（Opus/Sonnet/Haiku）**：05 § 策略一
- **Prompt Cache 怎么用**：05 § 策略四
- **Subagent 什么时候用**：05 § 策略三
- **/compact 和 /clear 的区别**：05 § 策略二
- **Thinking Token 怎么控制**：05 § 策略五
- **CLAUDE.md 多长合适**：05 § 策略二
- **Claude Code 卡住不动怎么办**：06
- **Token 不涨但时间在走**：06 § 症状
- **Stream 超时**：06 § 根因 1
- **UI 假死（Ghost Freeze）**：06 § 根因 6
- **卡顿诊断流程**：06 § 诊断决策树
- **不要让 Claude 修自己的超时配置**：06 § 反模式警告
- **模型怎么自动切换**：07
- **CC Switch 怎么用**：07 § 第二层
- **脚本编排 LDD 流水线**：07 § 第三层
- **OpenRouter / LiteLLM**：07 § 第二层
- **模型编排工具对比**：07 § 第二层

## 系列说明

- **调研方法**：每篇文章基于多 Agent 并行深度调研，事实性声明经三票制对抗验证
- **写作风格**：继承 [building-an-agent-harness](https://github.com/sky54laozhu/building-an-agent-harness) 系列风格
- **前序系列**：[18 篇 Agent Harness 工程拆解](https://github.com/sky54laozhu/building-an-agent-harness/blob/master/docs/blog/reading-map.md)

## 仓库 / 反馈

- 源码仓库：[sky54laozhu/ai-frontier-notes](https://github.com/sky54laozhu/ai-frontier-notes)
- 邮件：sky54laozhu@163.com / sky54laozhu@gmail.com
