---
title: Git Worktree 实战：从多分支并行，到 AI Agent 隔离
date: 2025-10-08 10:08:26
tags: [git, AI辅助]
---

下午三点，你正在 `feature/new-module` 分支上开发新功能，代码改到一半，还没到能 commit 的程度

这时候 QA 在群里 @你：上周提测的 `feature/payment` 有 bug，订单回调没处理异常情况，需要修一下

你下意识想切到 `feature/payment` 分支，手悬在键盘上停住了——当前 `feature/new-module` 上散了一地的代码怎么办？`git stash`？stash pop 的时候冲突了怎么办？而且你心里清楚，修完 QA 提的 bug 之后还得继续回来开发 `feature/new-module`。两边来回切分支，万一哪次忘了 stash 或者切错了分支，代码就可能搞混

这个场景，只要你在同一个代码仓库里同时跟过「开发中」和「测试中」两个需求，就一定经历过。`git stash` 和 `git switch` 能解决一部分问题，但当「并行开发」变成常态，你会发现一直在 stash → switch → pop → 解决冲突之间来回折腾——而且真的很容易搞错

Git 从 2.5 版本（2015 年）开始就内置了一个更彻底的解决方案——**`git worktree`**

<!-- more -->

## Worktree 解决了什么

先理清问题本质。传统 Git 工作流有一个隐含假设：**一个仓库同时只能有一个工作目录**。你的 `~/project` 目录里，`.git` 存着整个仓库的历史，外面的文件就是当前 checkout 分支的快照

当你想同时处理两个分支时，这个模型就碎了。你必须在同一个目录里反复切换分支——这意味着：

- 切换之前要么 commit，要么 stash
- 切回来之后，IDE 要重新索引文件
- 未跟踪的构建产物、依赖、临时文件在不同分支之间可能互相污染

`git worktree` 的解决思路很简单：**一个 `.git` 仓库，多个工作目录**。每个 worktree 独立 checkout 一个分支，互不干扰。

```
~/project/                  # 主仓库
├── .git/                   # 唯一的 Git 数据库（所有 worktree 共享）
├── src/                    # feature/payment 分支的源码
├── pom.xml
└── ...

~/project-hotfix/           # 另一个 worktree
├── .git → ~/project/.git   # 不是目录，是指向主仓库的指针文件
├── src/                    # main 分支的源码
├── pom.xml
└── ...
```

关键细节：**主仓库里的 `.git` 是一个目录，而 worktree 里的 `.git` 是一个文件**——里面只有一行 `gitdir: /path/to/main/.git/worktrees/<name>`。理解了这一点，后面很多「为什么」就好解释了

## 场景一：开发中接到测试反馈

回到开头的场景。你正在 `feature/new-module` 上开发，QA 反馈提测的 `feature/payment` 有 bug 需要修

### 传统做法

```bash
# 当前在 feature/new-module 上，代码改了一半
git stash                    # 暂存当前修改
git switch feature/payment   # 切到测试分支
# ... 定位问题、修 bug、提交、推送 ...
git switch feature/new-module # 切回来
git stash pop                # 恢复之前的修改——祈祷没有冲突
```

这个流程的问题不只是 stash pop 可能冲突。更大的隐患是来回切容易搞错——你可能修完 bug 之后忘了切回 `feature/new-module`，直接在 `feature/payment` 上继续写新功能的代码；或者修 bug 修到一半思路被打断，再切回去时忘了刚才改到哪了

### 用 Worktree

```bash
# 在 feature/new-module 目录里，不需要 stash，直接为测试分支创建工作区
git worktree add ../project-payment feature/payment

# 进入 payment 目录修 bug
cd ../project-payment
mvn compile -DskipTests
# ... 定位问题、修 bug ...
git commit -am "fix: 支付回调异常处理"
git push origin feature/payment

# 修完就删
cd ~/project
git worktree remove ../project-payment
```

**你的 `~/project` 目录始终停在 `feature/new-module` 上，纹丝不动。** 没有 stash，没有分支切换，不存在「切错分支」的可能。修完 QA 的 bug，关掉 payment 的 IDE 窗口，继续写新功能——两个需求在物理上隔离，脑子里也不会搞混

## 场景二：多个 AI Agent 并行开发

现在越来越多的开发者用 Claude Code 或 Codex 来写代码。一个常见的场景是：**同一个仓库里同时有多个需求在推进，你想让多个 AI agent 分别处理，互不干扰。**

如果让两个 agent 在同一个目录里干活，它们会互相踩文件——agent A 改到一半的代码被 agent B 覆盖，或者两个 agent 各自生成的修改混在一起拆不开。

worktree 天然解决这个问题——每个 agent 一个独立工作目录，各干各的。

```bash
# 为 agent A 创建 worktree，做 feature/export
git worktree add ../project-export main
cd ../project-export
git switch -c feature/export
# 在这个目录里启动 Claude Code 或 Codex
# Claude Code：claude 直接在这个目录启动
# Codex：codex exec "实现导出功能..."

# 回到主仓库，为 agent B 再创建一个 worktree，做 feature/refund
cd ~/project
git worktree add ../project-refund main
cd ../project-refund
git switch -c feature/refund
# 同样在这个目录里启动 Claude Code 或 Codex

# 两个 agent 并行跑，你等它们出结果就行
```

两个 agent、两个 worktree、同一个仓库——互不干扰。 各自改完各自提交，你只需要 review 两个目录的 diff，分别合并。本质上就是把场景一里「人同时处理多个分支」的逻辑，换成了「多个 agent 同时处理多个分支」

> 这也正是 Claude Code 和 Codex 底层在做的事。 它们内部就是用 worktree 给每个 agent 任务创建隔离环境——Claude Code 的 `--worktree` 参数、Codex 的 `--sandbox workspace-write` 模式，本质上都是自动化了上面这个流程。理解了手动版本，你就理解了 AI 编程工具「agent 隔离」的底层原理。

## 注意事项

日常使用 worktree 有几个点值得留意：

- 同一分支不能同时出现在两个 worktree 里。Git 会直接拒绝——这是故意的，防止两个目录同时修改同一个分支导致冲突。
- 多个 worktree 共享 stash。 `git stash list` 是全局的，注意别在错误的目录里 pop 了不对的 stash。
- `git worktree remove` 不会自动删目录。如果目录里还有未跟踪文件，需要加 `--force`：`git worktree remove --force <path>`。
- `prune` 要定期跑。 手动 `rm -rf` 删了目录但没走 `git worktree remove` 的话，元数据会残留。跑一下 `git worktree prune` 清理。
- Submodule 兼容性差。 如果你的项目重度依赖 Git submodule，worktree 的行为可能不稳定。建议先小范围试用，或继续多 clone。

## 总结

`git worktree` 解决的是多分支并行的上下文切换成本——不用 stash、不用重新索引、不用在脑子里重建「我改到哪了」，更不会因为来回切分支把代码搞混。而且你会发现，当执行者从你换成了 AI agent，问题完全一样，解法也完全一样——这就是为什么 Claude Code 和 Codex 不约而同地用 worktree 做 agent 隔离。它们只是自动化了你在场景一和场景二里手动做的事

下次 QA 在群里 @你、或者想让 AI agent 帮你并行干活的时候，别在 `git stash` 和「再 clone 一份」之间纠结了。试一下：

```bash
git worktree add ../project-payment feature/payment
```

## 参考

- [Git 官方文档：git-worktree](https://git-scm.com/docs/git-worktree)
- [Pro Git（中文版）](https://git-scm.com/book/zh/v2)
- [Atlassian Tutorial: Git Worktree](https://www.atlassian.com/git/tutorials/git-worktree)
- [Claude Code Docs：使用 worktrees 运行并行会话](https://code.claude.com/docs/zh-CN/worktrees)
