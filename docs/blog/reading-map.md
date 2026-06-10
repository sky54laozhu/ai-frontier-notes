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

## English · Reading Order

| Series | # | Title | One-liner |
|--------|---|-------|-----------|
| **Loop Engineering** | 01 | [Loop Engineering](en/01-loop-engineering.md) | From "I prompt the agent" to "the system prompts the agent" |
| | 02 | [Loop Engineering in Practice](en/02-loop-engineering-in-practice.md) | Building an auto bug-fix system step by step |
| | 03 | [Hello World: Star Tracker](en/03-loop-hello-world-star-tracker.md) | 30 lines + one command, your first Loop in 10 minutes |
| | 04 | [Loop-Driven Development](zh/04-loop-driven-development.md) | 5 Loops from Spec to acceptance, full lifecycle |

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

## 系列说明

- **调研方法**：每篇文章基于多 Agent 并行深度调研，事实性声明经三票制对抗验证
- **写作风格**：继承 [building-an-agent-harness](https://github.com/sky54laozhu/building-an-agent-harness) 系列风格
- **前序系列**：[18 篇 Agent Harness 工程拆解](https://github.com/sky54laozhu/building-an-agent-harness/blob/master/docs/blog/reading-map.md)

## 仓库 / 反馈

- 源码仓库：[sky54laozhu/ai-frontier-notes](https://github.com/sky54laozhu/ai-frontier-notes)
- 邮件：sky54laozhu@163.com / sky54laozhu@gmail.com
