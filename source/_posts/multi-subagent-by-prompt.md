---
title: 从superpower看多Agent编排：用Prompt协议实现可控协作
date: 2026-05-16 18:37:37
tags: [AI辅助]
---

最近在读 Superpowers 里的一个 skill：[subagent-driven-development](https://github.com/obra/superpowers/tree/main/skills/subagent-driven-development)。

这个 skill 很有意思。它并不是教 agent 如何写某一种代码，而是在设计一种开发流程（开发+review）：当我们已经有一个实现计划，并且计划里的任务相对独立时，主 agent 不再亲自完成所有工作，而是把每个任务派发给新的 subAgent，再通过两阶段 review 来控制质量。

它的核心思想可以用一句话概括：

> **每个任务派一个新的 subAgent + 两阶段审查 = 可控、高质量、低上下文污染的开发流程。**

也就是说，它真正关注的不是「让更多 agent 干活」，而是「如何让多个 agent 在明确边界内协作」。

<!-- more -->

## 一、 它解决的不是编码问题，而是协作控制问题

在 [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/subagent-driven-development/SKILL.md) 里，开头就定义了这个 skill 的执行方式：

```text
Execute plan by dispatching fresh subagent per task,
with two-stage review after each:
spec compliance review first, then code quality review.
```

这里有三个关键词：

- `fresh subagent per task`  —— 每个任务用全新的子 Agent
- `spec compliance review`  —— 检查是否做对了需求
- `code quality review`  —— 检查代码写得好不好

它解决的是 agent 开发里的几个典型问题：

第一，长上下文污染。一个 agent 在同一个会话里持续做很多任务，很容易把前一个任务的判断、假设、实现细节带到后一个任务里。

第二，自己实现、自己检查容易产生确认偏误。implementer 往往会相信自己的实现，报告“已完成”，但实际可能漏需求、多做功能，或者误解了规格。

第三，大任务执行中容易失控。如果没有明确的阶段和状态，主 agent 很难判断什么时候该继续、什么时候该回滚、什么时候该问人。

所以这个 skill 的设计目标不是提升单个 agent 的能力，而是通过流程设计降低 agent 的不可靠性。

## 二、 整体架构：Controller + 三个角色

整个系统由四个角色组成：

```text
Controller（主控）
  -> Implementer（实现者）
  -> Spec Reviewer（规格审查员）
  -> Code Quality Reviewer（代码质量审查员）
```

**Controller 不直接写代码**。它的职责是：

- 读取计划 → 拆出任务 → 准备上下文 → 派发 Implementer
- 处理返回状态 → 派发 Reviewer → 根据结果决定返工 → 标记完成 → 进入下一任务

流程可以简化为一条串行流水线：

```
Controller 拆任务
  → Implementer 实现
  → Spec Reviewer 检查需求
    → 不通过 → 返工
    → 通过 → Code Quality Reviewer 检查质量
      → 不通过 → 返工
      → 通过 → 任务完成 → 进入下一项
```

这就像一条轻量级的 CI 流水线。区别在于：每个阶段的「执行者」不是脚本，而是一个有明确职责的 subAgent

## 三、5 个关键设计

### 设计 1: 每个任务用全新的 subAgent

整个设计里最核心的一条。子 Agent **不继承** 主会话的上下文历史，Controller 精确构造它需要的输入。[SKILL.md](https://github.com/obra/superpowers/blob/main/skills/subagent-driven-development/SKILL.md) 明确强调：

```text
They should never inherit your session's context or history —
you construct exactly what they need.
```

好处很明显：

- 子 agent 不会被之前任务污染
- 每个任务边界更清楚
- reviewer 不会被 implementer 的叙述带偏
- Controller 保留全局视角，不被实现细节淹没

这其实是一种「上下文最小充分原则」—— 不是给越多越好，而是给刚好完成任务所需的信息

Controller 的 prompt 模板也体现了这一点（ [implementer-prompt.md](https://github.com/obra/superpowers/blob/main/skills/subagent-driven-development/implementer-prompt.md)）：

```text
## Task Description
[完整任务文本 —— 粘贴进来，不要让 subAgent 自己读文件]

## Context
[场景说明：这个任务的位置、依赖、架构背景]
```

注意这里特别说：不要让 subAgent 自己读计划文件，而是把任务全文粘进去

这说明 Controller 要承担「上下文整理者｜的职责，subAgent 拿到的是已经被裁剪和组织过的任务包

### 设计 2：角色职责非常窄

**Implementer：只负责实现一个任务**

在 [implementer-prompt.md](https://github.com/obra/superpowers/blob/main/skills/subagent-driven-development/implementer-prompt.md) 中，implementer 的职责是：

```text
1. 实现任务指定的内容
2. 写测试
3. 验证实现可工作
4. 提交代码
5. 自我审查
6. 汇报状态
```

职责边界非常明确：实现、测试、验证、提交、自查、汇报。遇到不清楚的地方就问，任务超出能力就停。**不是尽量完成一切，而是有明确的退出条件。**

**Spec Reviewer：只检查是否符合需求**

[spec-reviewer-prompt.md](https://github.com/obra/superpowers/blob/main/skills/subagent-driven-development/spec-reviewer-prompt.md) 定义了它的目的：

```text
Verify implementer built what was requested
(nothing more, nothing less)
```

它不主要关心代码优雅不优雅，而是检查三类问题：

- 是否漏做需求
- 是否多做了没要求的东西
- 是否误解了需求

不做代码质量判断。**先确认方向对了。**

这一步非常重要。因为在真实开发里，「做错方向但代码写得不错」是很常见的失败模式。

**Code Quality Reviewer：只检查实现质量**

[code-quality-reviewer-prompt.md](https://github.com/obra/superpowers/blob/main/skills/subagent-driven-development/code-quality-reviewer-prompt.md) 定义了它的目的：

```text
Verify implementation is well-built
(clean, tested, maintainable)
```

并且它有一个前置条件：**只有 Spec Reviewer 通过了，才会进入质量审查。**

```text
Only dispatch after spec compliance review passes.
```

也就是说，只有确认「做对了」，才进入「做得好不好」的判断。

### 设计 3：状态协议让协作可控

Implementer 不是随便返回一段自然语言，而是必须返回结构化状态。状态定义在 [SKILL.md](https://github.com/obra/superpowers/blob/main/skills/subagent-driven-development/SKILL.md)：

| 状态                   | 含义                                                         |
| ---------------------- | ------------------------------------------------------------ |
| **DONE**               | 任务完成，进入 Spec Review                                   |
| **DONE_WITH_CONCERNS** | 完成但有疑虑，Controller 需要先读 concerns                   |
| **NEEDS_CONTEXT**      | 缺上下文，Controller 补充后重新派发                          |
| **BLOCKED**            | 无法完成，Controller 判断 → 拆任务、换模型、补上下文、或找人 |

这四个状态就是 Controller 和 Implementer 之间的控制接口。

### 设计 4：Reviewer 不信任 Implementer

Spec Reviewer 的 prompt 里有一段我觉得最有价值的话：

```text
Do Not Trust the Report
```

并继续要求：

- 不要相信 implementer 对完整性的声明
- 不要接受 implementer 对需求的解释
- 必须读实际代码
- 必须逐条对照需求
- 必须找 missing、extra 和 misunderstanding

这背后的原则非常适合迁移到其他多 Agent 系统：

> 前一个 agent 的输出不是事实，而是 claim。Reviewer 的职责不是复述 claim，而是验证 artifact。

如果 reviewer 只是看 implementer 的报告，那么多 Agent 协作只是「多个 agent 相互背书」。但这里 reviewer 必须独立读代码，所以它承担的是验证者角色。这是降低幻觉或过于乐观的关键。

### 设计 5：两阶段 Review Gate

这个 skill 的 review 不是建议，而是强约束。在流程中：

```text
Implementer 完成
  → Spec Reviewer 检查
    → 不通过 → 返回 Implementer 修
  → Code Quality Reviewer 检查
    → 不通过 → 返回 Implementer 修
  → 两者都通过 → 任务完成
```

顺序不能反。Spec Review 先于 Code Quality Review。**需求没满足，代码质量再好也没用。**。

Red Flags（红线规则）也明确禁止：

- 跳过 review loops
- 在 Spec 还没通过时就开始 Code Quality Review

**说明 review loop 是强约束，不是可选优化。**



## 四、 为什么不并行派多个 Implementer？

这个 skill 虽然叫 subagent-driven-development，但**不鼓励并行写代码**。Red Flags 明确禁止派发多个 Implementer 同时开工。

原因很现实：

- 多个 implementer 同时改代码容易冲突
- Commit 边界会变乱
- Review 很难判断问题来自哪个任务
- 后一个任务可能依赖前一个任务的结果

**它追求的不是最大并发，而是最大可控性。**

这是一个很重要的启发：**多 Agent 不等于并行。多 Agent 的价值在于角色隔离和独立验证，而不是同时开工。**



## 五、实现方式：轻量级 Prompt 编排

整个 skill 的源码只有几个文件：

```text
SKILL.md
implementer-prompt.md
spec-reviewer-prompt.md
code-quality-reviewer-prompt.md
```

没有复杂的 multi-agent 框架。核心就是：

**Prompt Template + Controller Discipline + Review Gate = Lightweight Multi-Agent Orchestration**

这也是它很值得学习的地方—— 它的协作规则写在 skill 本身，而不是依赖基础设施。



## 六、给我们的启发

如果要设计类似的多 Agent skill，7 条原则可以直接复用：

1. **先设计 Controller，再设计 Worker** —— 先定义主控流程，再想子 Agent 做什么
2. **角色要窄** —— 职责越窄，prompt 越稳定
3. **上下文由 Controller 裁剪** —— 不让子 Agent 自己探索
4. **返回格式要结构化** —— 状态协议让决策稳定
5. **Review 要验证真实产物** —— 不信报告，看代码
6. **失败路径要明确设计** —— 不止定义成功路径
7. **不要为了多 Agent 而并行** —— 可控性比并发重要



## 写在最后

subagent-driven-development 展示的是一种非常务实的多 Agent 编排方式。

没有复杂框架，没有让一群 Agent 自由讨论。而是把开发过程拆成明确角色：Controller 调度，Implementer 实现，Spec Reviewer 验收需求，Code Quality Reviewer 检查质量。

多 Agent 系统的关键不是让更多 Agent 参与，而是 **让每个 Agent 在正确的边界内，只做自己该做的事，并让后续 Agent 能独立验证它的产物。**

SubAgent 编排的核心不是「智能叠加」，而是 **责任隔离、状态协议和质量门控。**

---

**参考资料**

本文拆解的项目：Superpowers / subagent-driven-development
完整源码：https://github.com/obra/superpowers/tree/main/skills/subagent-driven-development

