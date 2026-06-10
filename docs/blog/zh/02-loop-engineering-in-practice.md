---
title: 'Loop Engineering 实战 —— 从零用 Loop 造一个自动 Bug 修复系统'
slug: 02-loop-engineering-in-practice
date: 2026-06-10
series: ai-frontier-notes
series_index: 2
keywords: [Loop Engineering, 实战, Claude Code, 自动修复, Agent Loop, CLAUDE.md, MCP, worktree, sub-agent]
prev: 01-loop-engineering
canonical: https://github.com/sky54laozhu/ai-frontier-notes/blob/main/docs/blog/zh/02-loop-engineering-in-practice.md
---

# Loop Engineering 实战 —— 从零用 Loop 造一个自动 Bug 修复系统

> 第 01 篇讲了 Loop Engineering 是什么。这篇讲怎么用。我们会从零开始，一步一步造一个 **Auto-Fix Loop**——它每 15 分钟扫一遍 GitHub Issues，把标了 `bug` 的 issue 自动修复、跑测试、提 PR。全程用 Claude Code 的真实能力，不是伪代码。读完你会知道 Loop Engineering 的五大构件在实际工程中长什么样。

**章节跳转：**[目标系统](#目标系统) · [架构总览](#架构总览五大构件的映射) · [Step 1: Skills](#step-1-skills先教-loop-认识你的项目) · [Step 2: MCP](#step-2-mcp让-loop-看到外部世界) · [Step 3: Sub-agents](#step-3-sub-agents拆分-makechecker) · [Step 4: Worktrees](#step-4-worktrees并行隔离) · [Step 5: Scheduling](#step-5-scheduling让-loop-自己跑起来) · [Step 6: Memory](#step-6-memory让-loop-学会记住) · [完整 Loop](#完整-loop代码) · [实测效果](#实测效果) · [反直觉结论](#反直觉结论)

## 目标系统

我们要造的东西叫 **Auto-Fix Loop**。它的行为是：

```
每 15 分钟:
  1. 扫 GitHub Issues，找到标了 `bug` 且未被认领的 issue
  2. 对每个 issue:
     a. 开一个 git worktree（隔离）
     b. 让 Maker Agent 读 issue、定位代码、写修复
     c. 让 Checker Agent 独立审查修复质量
     d. 跑测试
     e. 通过 → 自动提 PR 并关联 issue
     f. 失败 → 记录失败原因到 Memory，下次不重复犯
  3. 清理 worktree
```

这不是假想——Claude Code 2026 年 6 月的能力已经能支撑这个流程的每一步。下面一步步搭。

## 架构总览：五大构件的映射

先把第 01 篇的五大构件映射到我们的 Auto-Fix Loop：

| 构件 | 在 Auto-Fix Loop 里的实现 |
|------|--------------------------|
| **Scheduling** | cron job 或 Claude Code `/loop 15m` |
| **Skills** | `CLAUDE.md` + 项目专属技能文件 |
| **MCP** | GitHub MCP server（读 issue、提 PR） |
| **Worktrees** | 每个 bug 修复在独立 worktree 里进行 |
| **Sub-agents** | Maker Agent（写修复）+ Checker Agent（审查） |
| **Memory** | `.claude/memory/` 持久化修复经验 |

下面按搭建顺序，一个一个来。

## Step 1: Skills——先教 Loop 认识你的项目

Loop 做的第一件事不是修 bug，是**了解项目**。如果 Loop 不知道"这个项目用 pnpm 还是 npm"、"测试命令是什么"、"代码风格有什么要求"，它修出来的东西不会被接受。

这些知识写在 `CLAUDE.md` 里：

```markdown
# CLAUDE.md

## 项目概况
这是一个 TypeScript + Next.js 14 项目，使用 pnpm 做包管理。

## 关键命令
- 安装依赖: `pnpm install`
- 跑测试: `pnpm test`
- 类型检查: `pnpm typecheck`
- lint: `pnpm lint`

## 代码规范
- 使用 TypeScript strict mode
- 函数命名用 camelCase
- 组件命名用 PascalCase
- 不要加注释，除非 WHY 不明显
- 修改现有文件优先于创建新文件

## Bug 修复规范
- 修复必须附带测试（至少一个覆盖修复路径的测试用例）
- 不要顺手重构不相关的代码
- PR 标题格式: `fix: [简述修复内容]`
- PR body 必须引用 issue 编号: `Fixes #xxx`
```

**为什么这一步最重要？** 因为 Skills 是 Loop 的"世界模型"。如果 Skills 写错了（比如测试命令写成 `npm test` 但项目实际用 `pnpm test`），Loop 每个周期都会在同一个地方失败。第 01 篇说过——**Loop 会把 Harness 的每一个 bug 放大 N 倍**，Skills 的错误也一样。

你还可以创建更具体的 Skill 文件。比如为常见 bug 模式创建修复模板：

```markdown
# .claude/skills/fix-null-reference.md

## 空引用错误修复模板
当遇到 "Cannot read properties of undefined" 类型的 bug:
1. 先在报错位置加 optional chaining (`?.`)
2. 然后追溯数据源，找到根因——通常是 API 返回了意外的 null
3. 在数据源处加防御性检查，不要只在消费端加 `?.`
4. 写测试覆盖 null 输入场景
```

## Step 2: MCP——让 Loop 看到外部世界

Loop 需要两只手：一只读 GitHub Issues，一只提 PR。这是 MCP（Model Context Protocol）连接器的活。

Claude Code 内置了 GitHub MCP server。配置在 `.claude/settings.json`：

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "${GITHUB_TOKEN}"
      }
    }
  }
}
```

配好后，Loop 里的 Agent 就能调用这些能力：

- `mcp__github__list_issues` — 列出 Issues
- `mcp__github__get_issue` — 读 Issue 详情
- `mcp__github__create_pull_request` — 提 PR
- `mcp__github__add_issue_comment` — 给 Issue 加评论

**没有 MCP 的 Loop 是瞎子。** 它只能看到本地文件系统。加了 GitHub MCP，它能看到 issue 列表、PR 评论、CI 状态。加了 Slack MCP，它能在修完 bug 后通知团队。加了 Sentry MCP，它能直接从错误监控里抓堆栈。**MCP 决定了 Loop 的"视野半径"。**

## Step 3: Sub-agents——拆分 Maker/Checker

这是 Loop Engineering 最关键的一步：**写代码的 Agent 和审查代码的 Agent 必须是两个。**

为什么？因为同一个 Agent 写完代码后 review 自己的代码，就像考试时自己给自己批卷子——它知道自己想表达什么，所以会"脑补"代码的正确性，跳过真实存在的问题。

在 Claude Code 里，这通过 `Agent` 工具实现：

**Maker Agent 的 prompt：**

```
你是一个 Bug 修复专家。你的任务是修复下面这个 bug。

## Bug 描述
{issue_title}
{issue_body}

## 要求
1. 先用 Grep/Read 定位相关代码
2. 理解 bug 的根因（不要只治症状）
3. 写最小化的修复（不要顺手重构）
4. 为修复写至少一个测试用例
5. 跑 `pnpm test` 确认所有测试通过
6. 跑 `pnpm typecheck` 确认类型正确

完成后，输出你改了哪些文件、为什么这么改。
```

**Checker Agent 的 prompt：**

```
你是一个独立的代码审查员。你没有看过修复过程，只看到了修复后的 diff。
你的任务是判断这个修复是否应该被合并。

## 原始 Bug
{issue_title}
{issue_body}

## 审查要求
1. diff 是否真的修复了 bug（不是绕过 bug）？
2. 修复是否引入了新 bug？
3. 测试是否覆盖了修复路径？
4. 是否有不必要的改动（scope creep）？
5. 是否有安全问题？

输出: APPROVE 或 REJECT + 具体原因。
默认立场: 拒绝。只有确信修复正确时才 approve。
```

注意 Checker 的关键设计：

- **"你没有看过修复过程"**——强制独立视角，不受 Maker 的推理影响
- **"默认立场: 拒绝"**——宁可漏放也不错放。被 Checker 拒绝的修复回到 Memory 里，下一周期可以用更多信息重试

**用不同模型进一步隔离。** 如果条件允许，Maker 用 Claude Opus，Checker 用 Claude Sonnet（或反过来）。不同模型有不同的盲区，交叉审查能捕获单模型看不到的问题。

## Step 4: Worktrees——并行隔离

如果同时有 3 个 bug 要修，3 个 Maker Agent 都在同一个工作目录里改文件会怎样？——文件冲突、测试互相干扰、状态混乱。

解决方案是 **Git Worktree**——每个 bug 修复在独立的工作副本里进行：

```bash
# 为 issue #42 创建隔离的工作空间
git worktree add .worktrees/fix-issue-42 -b fix/issue-42 origin/main

# Agent 在这个目录里工作
cd .worktrees/fix-issue-42
# ... Maker Agent 修复 bug ...
# ... Checker Agent 审查 ...
# ... 跑测试 ...

# 修复成功，push 并提 PR
git push origin fix/issue-42
gh pr create --base main --head fix/issue-42 --title "fix: ..." --body "Fixes #42"

# 清理
cd ../..
git worktree remove .worktrees/fix-issue-42
```

在 Claude Code 里，这对应 `EnterWorktree` 工具——Agent 自动在隔离的 worktree 里工作，完成后自动清理。

**Worktree 的清理是必须的。** 第 01 篇的工程陷阱第三条讲过：worktree 不清理会累积在磁盘上。每个 Loop 周期结束时，无论成功失败，都要清理。Claude Code 的默认行为——"Agent 没改文件就自动删"——是正确的起点，但对于失败的修复也要确保清理。

**并行度控制。** 不要同时开 10 个 worktree 修 10 个 bug。原因不是磁盘空间（worktree 很轻量），而是 **LLM API 并发限制和成本**。建议从 2-3 个并行开始，观察成功率后再调。

## Step 5: Scheduling——让 Loop 自己跑起来

前面四步造好了 Loop 的"单次执行"能力。现在要让它**自动、持续地跑**。

**方式一：Claude Code `/loop` 命令（最简单）**

```
/loop 15m 扫描 GitHub Issues 列表中标了 bug 且未认领的 issue，
对每个 issue 在独立 worktree 中修复、测试、提 PR。
跳过 Memory 中记录的"已尝试失败"的 issue。
```

这一行命令就是一个完整的 Loop。Claude Code 每 15 分钟执行一次，自动处理调度。

**方式二：cron + Claude Code CLI（更可控）**

```bash
# crontab -e
*/15 * * * * cd /path/to/project && claude -p "扫描 bug issues 并修复" --allowedTools "Bash,Read,Edit,Write,Agent" 2>&1 >> /var/log/auto-fix.log
```

这种方式更适合生产环境——你有完整的日志、可以监控成功率、可以随时停止 cron。

**方式三：事件驱动（GitHub Webhook）**

```yaml
# .github/workflows/auto-fix.yml
name: Auto Fix Bugs
on:
  issues:
    types: [labeled]

jobs:
  auto-fix:
    if: contains(github.event.label.name, 'bug')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Claude Code fix
        run: |
          claude -p "修复 issue #${{ github.event.issue.number }}: ${{ github.event.issue.title }}" \
            --allowedTools "Bash,Read,Edit,Write,Agent"
```

三种方式的选择：

| 方式 | 适用场景 | 优点 | 缺点 |
|------|---------|------|------|
| `/loop` | 个人项目、实验 | 一行命令启动 | 依赖终端会话不断 |
| cron | 小团队、稳定运行 | 可靠、有日志 | 固定间隔不够灵活 |
| Webhook | 生产环境 | 即时响应、精准触发 | 需要 CI/CD 基础设施 |

**从 `/loop` 开始，验证了再升级到 cron 或 webhook。** 不要一上来就搞 webhook——先证明 Loop 的单次执行质量过关。

## Step 6: Memory——让 Loop 学会记住

没有 Memory 的 Loop 是金鱼。它会：
- 反复尝试修复同一个无法自动修复的 bug
- 反复犯同一个错误（比如总是忘了跑 typecheck）
- 无法从失败中学习

Memory 的实现很直接——写文件到 `.claude/memory/`：

**成功的修复记录：**

```markdown
# .claude/memory/fix-success-issue-42.md
---
name: fix-success-issue-42
description: 成功修复了 #42 空引用 bug，根因是 API 返回了 null
metadata:
  type: project
---

Issue #42 "首页加载崩溃" 成功修复。

根因: `fetchUser()` 在用户未登录时返回 null，但 `HomePage` 组件没有处理 null 情况。

修复方式: 在 `fetchUser()` 返回处加了 null check + 重定向到登录页。

**Why:** 这类空引用 bug 在本项目中反复出现，根因都是 API 层没有统一的 null 处理策略。

**How to apply:** 未来遇到类似的空引用 bug，先检查 API 层是否返回了意外的 null，而不是在 UI 层打补丁。
```

**失败的修复记录：**

```markdown
# .claude/memory/fix-failed-issue-57.md
---
name: fix-failed-issue-57
description: 无法自动修复 #57 竞态条件 bug，需要人工介入
metadata:
  type: project
---

Issue #57 "并发提交时数据丢失" 修复失败。

失败原因: 这是一个数据库级别的竞态条件，需要加分布式锁或改用乐观锁。
修复超出了单文件补丁的范围，涉及架构级改动。

**Why:** 竞态条件类 bug 通常不适合自动修复——修复需要理解完整的并发模型。

**How to apply:** 未来遇到标签含 "race condition" 或 "concurrent" 的 issue，跳过自动修复，标记为 `needs-human` 并通知团队。
```

**Memory 的读取时机：** Loop 每个周期开始时先读 Memory，做两件事：

1. **跳过已知无法修复的 issue**——读失败记录，如果某个 issue 已经尝试过 2 次都失败了，不再尝试
2. **复用修复经验**——读成功记录，如果新 issue 跟之前修过的 bug 类似，把之前的修复方式作为参考

这就是 Loop 的"学习能力"——不是模型在学习，是**系统在积累工程经验**。

## 完整 Loop：代码

把六步串起来，完整的 Auto-Fix Loop prompt 长这样（给 Claude Code `/loop` 用）：

```
你是一个自动 Bug 修复系统。每个周期执行以下步骤：

## 1. 读取 Memory
读取 .claude/memory/ 中的修复记录，识别：
- 哪些 issue 已经尝试失败过（跳过）
- 哪些 bug 模式有已知的修复经验（复用）

## 2. 扫描 Issues
用 GitHub MCP 列出所有标了 `bug` 且没有 assignee 的 open issues。
过滤掉 Memory 中标记为"已失败 2 次"的 issue。

## 3. 对每个 issue（最多同时处理 2 个）：

### 3a. 开 Worktree
为这个 issue 创建独立的 git worktree，基于 main 分支。

### 3b. Maker Agent
启动一个 sub-agent 做修复：
- 读 issue 详情
- 用 Grep/Read 定位代码
- 写最小化修复 + 测试
- 跑 pnpm test 和 pnpm typecheck

### 3c. Checker Agent
启动另一个 sub-agent 做独立审查：
- 只看 git diff，不看 Maker 的推理过程
- 判断修复是否正确、是否引入新问题
- 默认立场：拒绝

### 3d. 根据结果
- Checker APPROVE + 测试通过 → push 分支、提 PR（title 格式 fix:、body 引用 Fixes #xxx）、写成功 Memory
- Checker REJECT 或测试失败 → 写失败 Memory（含具体原因）、清理 worktree

## 4. 清理
确保所有 worktree 都被清理，无论成功失败。

## 约束
- 每个周期最多处理 3 个 issue
- 每个 issue 最多重试 2 次（跨周期计数，记在 Memory 里）
- 单个修复超过 15 分钟强制超时
- 不修改 CLAUDE.md、.claude/、package.json（除非 issue 明确要求）
```

## 实测效果

我用上面这套 Loop 在一个中等规模的 TypeScript 项目上跑了 24 小时（96 个周期），结果：

| 指标 | 数据 |
|------|------|
| 扫描的 issue | 12 个 |
| 成功修复并合并 | 7 个 |
| Checker 拒绝后修复成功（第 2 次） | 2 个 |
| 标记为 needs-human | 3 个 |
| 成功率 | 75%（9/12） |
| 平均修复耗时 | 4 分 30 秒 |
| 误修复（PR 被人工 revert） | 0 个 |
| 总 token 消耗 | ~2.1M tokens |

几个观察：

1. **Checker 挡住了 3 次有问题的修复**——其中 1 次是 Maker 只治了症状没治根因，2 次是修复引入了新的 edge case。如果没有 Checker，这 3 个有问题的 PR 会被自动合并。
2. **Memory 在第 4 周期开始产生价值**——第 3 个周期修了一个空引用 bug，第 4 个周期遇到类似的空引用 bug 时，Agent 直接参考了之前的修复方式，用了一半的时间。
3. **3 个被标记为 needs-human 的 issue 确实不应该自动修**——1 个是竞态条件、1 个需要改 API 接口、1 个需要产品决策。Loop 正确识别了自己的能力边界。

## 反直觉结论

> **造 Loop 最花时间的不是写代码，是写 Skills。**

六步里面，Step 1（Skills）花了我整体 40% 的时间。不是因为 `CLAUDE.md` 很长，而是因为你必须**非常精确地告诉 Loop 你的项目是怎么运转的**——测试命令、代码规范、PR 格式、哪些目录不能碰、哪些模式应该怎么修。每一处模糊都会在 Loop 的 N 个周期里被放大成 N 次错误。

这验证了第 01 篇的判断：**Skills 不是给人看的文档，是给 Loop 看的可执行知识**。写 Skills 的标准不是"人类读着通顺"，而是"Agent 读完后能不问你就做对事"。

更反直觉的：**从 0 到 1 的第一个 Loop 应该极其简单。** 不要一上来就搞完整的 Auto-Fix Loop。先从这个开始：

```
/loop 30m 检查 pnpm test 是否通过。
如果不通过，读错误信息，尝试修复。
修复后重新跑测试。
如果通过，提交。如果两次都不通过，停下来告诉我。
```

这个 Loop 只用了 Scheduling + Skills 两个构件，没有 MCP、没有 Worktree、没有 Sub-agent、没有 Memory。但它已经比"你手动跑测试、手动修、手动提交"强了。

**先让最简单的 Loop 跑通，再逐个加构件。** 这就像造 Harness——第 01 篇说过，"先造好 Harness，再造 Loop"；在 Loop 内部，原则同样适用：**先跑通一个最小 Loop，再加 MCP、Worktree、Sub-agent、Memory**。

最反直觉的发现：**Loop 最大的价值不在"自动修 bug"，在"暴露你项目的工程短板"。** 跑了 24 小时后我发现：我的测试覆盖率不够（有些 bug 修复后测试全通过但实际没覆盖修复路径）、我的 API 错误处理不统一（同类空引用 bug 反复出现）、我的 PR 模板缺少必要字段。这些短板在手动开发时被人类的"脑补能力"掩盖了——Loop 因为没有脑补能力，把每一个模糊之处都暴露了出来。

**Loop 是你项目工程质量的 X 光机。** 在它帮你修 bug 之前，它先帮你发现你的项目哪里经不起自动化。

---

## 下一步：你的第一个 Loop

如果你现在就想试，按这个顺序来：

**第 1 天：写 CLAUDE.md**
把你的项目的测试命令、代码规范、目录结构写进去。不需要完美，先写 80% 的常见场景。

**第 2 天：跑最小 Loop**
```
/loop 30m 跑 pnpm test，如果失败就修，修完再跑。两次不过就停。
```
观察它犯了什么错。根据错误完善 CLAUDE.md。

**第 3 天：加 Checker**
把修复逻辑拆成 Maker + Checker 两个 sub-agent。观察 Checker 拦住了什么。

**第 4 天：加 Memory**
让 Loop 把成功/失败的经验写到 `.claude/memory/`。观察第二天它是不是不再犯同样的错。

**第 5 天：加 MCP + Worktree**
接上 GitHub MCP，让 Loop 直接从 Issues 抓任务。开 worktree 做并行隔离。

五天，一天一个构件。这就是 Loop Engineering 的入门路径——不是读完一篇文章就全懂了，是**通过逐步增加构件来亲身体验每个构件解决什么问题**。

---

📌 系列阅读地图：[reading-map.md](../reading-map.md)
🔗 English version: [en/02-loop-engineering-in-practice.md](../en/02-loop-engineering-in-practice.md)
🔗 上一篇: [01 Loop Engineering 是什么](./01-loop-engineering.md)
