---
title: 'Loop Engineering 的 Hello World —— 30 行脚本 + 一条命令造一个 GitHub 星标监控'
slug: 03-loop-hello-world-star-tracker
date: 2026-06-10
series: ai-frontier-notes
series_index: 3
keywords: [Loop Engineering, Hello World, GitHub Stars, 监控, Claude Code, /loop, cron, 最小可行 Loop]
prev: 02-loop-engineering-in-practice
canonical: https://github.com/sky54laozhu/ai-frontier-notes/blob/main/docs/blog/zh/03-loop-hello-world-star-tracker.md
---

# Loop Engineering 的 Hello World —— 30 行脚本 + 一条命令造一个 GitHub 星标监控

> 第 02 篇的 Auto-Fix Loop 有 6 步、5 个构件、需要 5 天上手。这篇只用 **1 个构件（Scheduling）+ 30 行 bash + 1 条 Claude Code 命令**，10 分钟造出一个能跑的 Loop。如果你从没写过 Loop，从这里开始。

**章节跳转：**[为什么从这个开始](#为什么从这个开始) · [10 分钟搭完](#10-分钟搭完) · [升级路线](#逐步加构件) · [真实运行](#真实运行记录) · [反直觉结论](#反直觉结论)

## 为什么从这个开始

第 02 篇给了一个"5 天入门计划"，从最简单的 Loop 开始逐步加构件。但很多人读完 02 篇的反应是——"太复杂了，Auto-Fix 那个 Loop 我还没信心跑。"

问题出在例子太重了。修 bug 涉及代码理解、测试验证、PR 流程——每一步都可能出错。初学者需要的不是这种，而是一个 **不可能失败的 Loop**：

- 不改代码（只读数据）
- 不需要 MCP（一个 `gh api` 调用搞定）
- 不需要 Worktree（没有并行，没有文件冲突）
- 不需要 Sub-agent（不需要 Maker/Checker）
- 甚至不需要 Memory（CSV 文件就是记忆）

这就是"监控 GitHub 星标增长"——**Loop Engineering 的 Hello World**。

## 目标

造一个 Loop，它做的事极其简单：

```
每 30 分钟:
  1. 查 GitHub API，拿到仓库当前的 stars / forks / watchers 数
  2. 追加一行到 CSV 文件
  3. 跟上一次的数据比较
  4. 如果有变化，输出一句人话总结（"过去 30 分钟涨了 3 个 star"）
  5. 如果没变化，安静等下一轮
```

这个 Loop 只用了五大构件中的 **1 个：Scheduling**。但它是完整的 Loop——有节奏、有状态（CSV）、有终止条件（你按 Ctrl-C）。

## 10 分钟搭完

### Step 1：写数据采集脚本（3 分钟）

```bash
#!/usr/bin/env bash
# scripts/star-tracker.sh

set -euo pipefail

REPO="sky54laozhu/ai-frontier-notes"   # 换成你的仓库
CSV="$(dirname "$0")/star-history.csv"

# 首次运行创建 CSV 头
if [ ! -f "$CSV" ]; then
  echo "timestamp,stars,forks,watchers,open_issues" > "$CSV"
fi

# 拿数据
DATA=$(gh api "repos/$REPO" --jq \
  '[.stargazers_count, .forks_count, .subscribers_count, .open_issues_count] | @csv')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 追加到 CSV
echo "${TIMESTAMP},${DATA}" >> "$CSV"

# 跟上一次比较
STARS=$(echo "$DATA" | cut -d',' -f1)

if [ "$(wc -l < "$CSV")" -gt 2 ]; then
  PREV_STARS=$(tail -2 "$CSV" | head -1 | cut -d',' -f2)
  DIFF=$((STARS - PREV_STARS))
  echo "⭐ Stars: $STARS (${DIFF:+$DIFF} since last check)"
else
  echo "⭐ Stars: $STARS (first record)"
fi
```

```bash
chmod +x scripts/star-tracker.sh
```

就这么多。30 行。唯一的外部依赖是 `gh`（GitHub CLI），你大概率已经装了。

### Step 2：手动跑一次验证（1 分钟）

```bash
$ ./scripts/star-tracker.sh
⭐ Stars: 0 (first record)

$ cat scripts/star-history.csv
timestamp,stars,forks,watchers,open_issues
2026-06-10T07:02:33Z,0,0,0,0
```

能跑通。CSV 里有数据了。

### Step 3：用 Claude Code `/loop` 让它自己跑（1 分钟）

现在把它交给 Loop：

```
/loop 30m 运行 ./scripts/star-tracker.sh 采集 GitHub 星标数据。
读取 scripts/star-history.csv 的最近 5 条记录。
如果 stars 有增长，总结增长趋势（比如"过去 2 小时从 3 涨到 7，增速加快"）。
如果连续 3 次无变化，说"暂无变化，继续监控"。
```

**搭完了。** 从现在开始，每 30 分钟 Claude Code 会自动跑脚本、读 CSV、给你一句人话总结。你可以去做别的事了。

### 这就是一个 Loop

回顾一下，它满足 Loop 的所有定义：

| Loop 特征 | Auto-Fix Loop（02 篇） | Star Tracker（本篇） |
|-----------|------------------------|---------------------|
| 有节奏 | 每 15 分钟 | 每 30 分钟 |
| 有状态 | Memory 文件 | CSV 文件 |
| 有终止条件 | 修完所有 bug / 预算花完 | 你按 Ctrl-C |
| 自主运行 | ✅ | ✅ |
| 构件数量 | 5+1（全部） | 1（Scheduling） |

**最小的 Loop 只需要一个构件：调度。** 剩下的四个构件是"让 Loop 做更复杂的事"用的，不是"让 Loop 跑起来"用的。

## 逐步加构件

现在你有了一个能跑的 Hello World Loop。如果你想让它更强，可以逐步加构件——**每次只加一个，观察效果，再决定要不要加下一个**。

### +Memory：让 Loop 记住趋势

当前的 Loop 只看"上一次 vs 这一次"。加了 Memory 后它能看到更长期的模式：

```
/loop 30m 运行 ./scripts/star-tracker.sh 采集数据。
读取 scripts/star-history.csv 全部记录。
分析趋势:
- 如果过去 24 小时有增长，计算日增速
- 如果某个时段增速突然加快，尝试关联原因
  （比如"下午 3 点到 5 点涨了 12 个 star，可能跟你发的推有关"）
- 把分析结果写到 .claude/memory/star-trend.md
下次运行时先读 .claude/memory/star-trend.md，跟新数据对比。
```

Memory 文件长这样：

```markdown
# .claude/memory/star-trend.md
---
name: star-trend
description: ai-frontier-notes 仓库星标增长趋势分析
metadata:
  type: project
---

## 最新状态（2026-06-10 15:00 UTC）
- 当前 stars: 23
- 24h 增长: +23（从 0 开始）
- 峰值时段: 12:00-14:00 UTC (+15)

## 模式
- 增长主要来自发布后前 6 小时
- 中文技术社区分享带来的增长集中在 UTC 4:00-8:00（北京时间 12:00-16:00）

## 待观察
- 第二天是否有长尾增长
- 英文版是否带来额外增长
```

### +MCP：让 Loop 看到谁 star 了

接上 GitHub MCP 后，Loop 不仅能看到数量，还能看到具体是谁：

```json
// .claude/settings.json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"]
    }
  }
}
```

```
/loop 30m 采集星标数据后，额外用 GitHub API 获取最近的 stargazers 列表。
如果有新的 stargazer，看看他们的 profile：
- 如果是有影响力的开发者（followers > 100），记到 Memory 里
- 如果是某个公司的人（bio 里有公司名），记到 Memory 里
这些信息帮助判断内容传播到了哪些圈子。
```

### +Sub-agent：让 Loop 自动写周报

```
/loop 24h 读取 scripts/star-history.csv 和 .claude/memory/star-trend.md。
启动一个 sub-agent 写一份周报：
- 本周 star 增长曲线（用 ASCII art 画）
- 增长最快的 3 个时段及可能原因
- 与上周对比
- 下周预测
把周报写到 docs/weekly/ 目录下。
```

### 构件升级路线图

```
Hello World（本篇）
  │  只有 Scheduling
  │
  ├─ +Memory → 趋势分析，跨周期学习
  │
  ├─ +MCP → 看到具体 stargazers，分析传播路径
  │
  ├─ +Sub-agent → 自动写增长周报
  │
  └─ +Skills → 教 Loop 你的运营策略
      （"star 破 100 时自动发推庆祝"）
```

注意这个路线里**没有 Worktree**——因为这个 Loop 不改代码。不是每个 Loop 都需要全部五个构件。**按需加构件，不要为了"完整"而加。**

## 真实运行记录

这个 Star Tracker Loop 是我在写本篇博客时真实搭建并运行的。第一次采集的数据：

```csv
timestamp,stars,forks,watchers,open_issues
2026-06-10T07:02:33Z,0,0,0,0
```

仓库刚建好，0 star。这条数据会成为整条增长曲线的起点。

如果你正在读这篇文章，说明这个仓库已经有了一些 star——而这些增长的每一步都被 Loop 记录在了 `scripts/star-history.csv` 里。你可以打开这个文件，看到增长的真实时间线。

## 反直觉结论

> **最好的第一个 Loop 是一个"只读"的 Loop。**

第 02 篇的 Auto-Fix Loop 是"读写"的——它读 issue、写代码、改文件、提 PR。任何一步出错都有后果。初学者面对这种 Loop 会犹豫："万一它乱改代码怎么办？"

Star Tracker 是"只读"的——它只查 API、写 CSV。**最坏的情况是多了一行错误数据，删掉就行。** 不可能搞坏任何东西。这种零风险让你可以放心地把它跑起来，观察 Loop 的行为模式，建立对 Loop 的直觉——然后再去挑战读写型的 Loop。

**学骑自行车应该先在平地上练，不是先上坡。** Star Tracker 就是那块平地。

更反直觉的：**这个 30 行的 Hello World 已经比你手动操作强了。** 你不会每 30 分钟打开一次 GitHub 看 star 数——但 Loop 会。你不会在凌晨 3 点记录 star 变化——但 Loop 会。你不会坚持一周每天 48 次手动记录——但 Loop 会。**Loop 的价值不在于它比你聪明，在于它比你持久。**

最反直觉的：**这篇博客本身就是被 Loop 监控的对象。** 我写完这篇文章、push 到 GitHub 的那一刻，Star Tracker Loop 就开始记录它带来的增长。如果你现在给这个仓库点了一个 star，下一个 30 分钟周期里，Loop 会记录到你。

这就是 Loop Engineering 最简单也最本质的形态——**你设计系统，系统替你持续观察**。

---

## 完整文件清单

```
ai-frontier-notes/
├── scripts/
│   ├── star-tracker.sh          # 30 行采集脚本
│   └── star-history.csv         # 增长数据（Loop 自动追加）
└── .claude/memory/
    └── star-trend.md            # 趋势分析（加了 Memory 构件后）
```

## 现在就试

1. Fork [sky54laozhu/ai-frontier-notes](https://github.com/sky54laozhu/ai-frontier-notes)（或用你自己的任何仓库）
2. 把 `scripts/star-tracker.sh` 里的 `REPO=` 改成你的仓库
3. 跑 `./scripts/star-tracker.sh` 验证
4. 在 Claude Code 里输入：
   ```
   /loop 30m 运行 ./scripts/star-tracker.sh，读最近 5 条 CSV 记录，总结变化。
   ```
5. 去做别的事。30 分钟后回来看 Loop 的汇报。

**你的第一个 Loop，10 分钟，从现在开始。**

---

## 配图

1. ![只读 Loop vs 读写 Loop 对比](../assets/img/03-read-only-vs-readwrite.svg)
2. ![Star Tracker 构件升级路线图](../assets/img/03-upgrade-path.svg)

---

📌 系列阅读地图：[reading-map.md](../reading-map.md)
🔗 English version: [en/03-loop-hello-world-star-tracker.md](../en/03-loop-hello-world-star-tracker.md)
🔗 上一篇: [02 Loop Engineering 实战](./02-loop-engineering-in-practice.md)
