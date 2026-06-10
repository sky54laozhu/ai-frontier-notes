<p align="center">
  <strong>AI Frontier Notes / AI 前沿笔记</strong>
</p>

<p align="center">
  <a href="./docs/blog/reading-map.md"><b>阅读地图 / Reading map</b></a>
</p>

# AI Frontier Notes

> Deep research + engineering teardowns on emerging AI technologies. Every claim fact-checked, every conclusion grounded in real code.
>
> AI 新技术深度调研与工程拆解。每一处事实经过多源交叉验证，每一个结论有真实工程支撑。

## Status

🚧 **In progress** · 5 articles published, more coming.

## At a glance

- **01: Loop Engineering** — 从"我来 prompt"到"系统替我 prompt"的范式跳跃
- **02: Loop Engineering 实战** — 从零用 Loop 造一个自动 Bug 修复系统
- **03: Hello World 星标监控** — 30 行脚本 + 一条命令，10 分钟造你的第一个 Loop
- **04: Loop-Driven Development** — 用 5 个 Loop 跑完从 Spec 到验收的全过程
- **05: Token 经济学** — Claude Code 全流程开发的成本优化手册
- **调研方法**：多 Agent 并行搜索 → 源去重 → 声明提取 → 三票制对抗验证 → 综合报告
- **写作风格**：问题陈述 → 朴素方案为什么不行 → 核心方案 → 实现要点 → 反直觉结论

## Series

| # | 主题 | 日期 | 状态 |
|---|------|------|------|
| 01 | [Loop Engineering](docs/blog/zh/01-loop-engineering.md) | 2026-06-10 | ✅ Published |
| 02 | [Loop Engineering 实战](docs/blog/zh/02-loop-engineering-in-practice.md) | 2026-06-10 | ✅ Published |
| 03 | [Hello World: 星标监控](docs/blog/zh/03-loop-hello-world-star-tracker.md) | 2026-06-10 | ✅ Published |
| 04 | [Loop-Driven Development](docs/blog/zh/04-loop-driven-development.md) | 2026-06-10 | ✅ Published |
| 05 | [Token 经济学](docs/blog/zh/05-token-optimization.md) | 2026-06-10 | ✅ Published |

## Repo layout

| Path | Purpose |
|------|---------|
| [`docs/blog/reading-map.md`](./docs/blog/reading-map.md) | **Entry point** — bilingual reading map |
| [`docs/blog/zh/`](./docs/blog/zh/) | 中文版 |
| [`docs/blog/en/`](./docs/blog/en/) | English version |
| [`docs/blog/assets/img/`](./docs/blog/assets/img/) | Diagrams |

## Research methodology

每篇文章的事实性声明均经过以下流程验证：

1. **Scope** — 将问题分解为 5-6 个搜索角度
2. **Search** — 每个角度并行 web search，去重 URL
3. **Fetch** — 抓取 top 15-22 源，提取可证伪声明
4. **Verify** — 每条声明 3 个独立 Agent 投票（2/3 驳回才杀掉）
5. **Synthesize** — 合并语义重复、按置信度排序、标注来源

被驳回的声明在文末明确列出，不会藏起来。

## Writing style

继承自 [building-an-agent-harness](https://github.com/sky54laozhu/building-an-agent-harness) 18 篇工程拆解系列的写作风格：

- **第一人称工程视角**：不是旁观者综述，是造过系统的人的判断
- **问题 → 朴素方案 → 核心方案 → 反直觉结论**：每篇同一结构
- **反直觉结论三层递进**：每篇结尾给出与直觉相反的工程洞察
- **源可查**：每一处事实引用标注来源 URL

## Related

- [building-an-agent-harness](https://github.com/sky54laozhu/building-an-agent-harness) — 18 篇 Agent Harness 工程拆解系列（前序系列）

## License

Dual-licensed:

- **Content** (`docs/`, README): [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
- **Tooling** (`scripts/`): [MIT](https://opensource.org/licenses/MIT)

---

Contact: sky54laozhu@163.com / sky54laozhu@gmail.com
