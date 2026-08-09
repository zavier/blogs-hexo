---
title: 用 Herdr 让 AI Agent 互相派活：打破多 Agent 协作的上下文孤岛
date: 2026-08-09 08:54:31
tags: [AI辅助, 工程实践, 工具]
---

我是后端开发。最近一年，AI 编程 agent 已经成了日常开发的主力——Claude Code、Pi、Codex，经常同时开好几个，让它们各干各的。

单个 agent 用得都挺顺手，但 agent 一多，它们之间的配合就开始让人头疼了。

## 任务分派断裂

一个需求经常要动好几个仓库。我在某个项目目录（或者几个仓库的共同父目录）里跟 agent 讨论了半小时，方案终于敲定了——然后呢？

- 我得自己记住「order-service 要做 A、user-service 要做 B」；
- 手动打开新终端、`cd` 到对应仓库、再起一个 agent；
- 把刚才讨论的结论**复制粘贴**过去，还要祈祷上下文没丢；
- 然后对第二个仓库重复一遍……

沟通的现场和执行的现场是分离的，中间靠人肉搬运上下文。每个终端里的 agent 都是孤岛，不知道其他 agent 的存在，更谈不上协作。

![人肉搬运上下文：沟通的现场和执行的现场是分离的](/images/herdr/context-broken.png)

<!-- more -->

最近我试了一个叫 [Herdr](https://herdr.dev/) 的工具。它是一个终端工作区管理工具，和同类工具最大的区别是：**它提供了一套 CLI 和本地 socket API，让 agent 之间可以互相操作**——需求讨论完，主 agent 直接在自己的终端里创建 pane、启动其他仓库的 agent、把任务连同上下文投递过去，等结果、收结果，全程不经过我的手。而且工人 agent 不限于同一种工具，Claude Code、Pi、Codex 可以混编。

至于同时监控多个 agent 的状态（谁在干活、谁卡住了），现在不少终端工具都能做了，Herdr 当然也有，而且做得不错——但这不是本文的重点。本文想记录的是它的**任务分派能力**，用一个 demo 项目走一遍完整流程。

![Herdr整体界面全景](/images/herdr/dashboard.png)

## 一分钟概念速览

实战前只需要知道四个词：

```text
Workspace（工作区）   ← 一个 repo / 一项任务
 └── Tab（标签页）     ← 视图划分：agents / server / logs
      └── Pane（面板）  ← 一个真实的终端
           └── Agent    ← pane 里被识别出来的 AI 进程
```

- **Workspace** 是顶层容器，官方建议每个仓库一个 workspace；
- **Pane** 是真实终端，agent 和各种进程就在里面跑；
- **Agent** 是 Herdr 在 pane 里自动识别出来的 AI 进程，有五种状态：`working`（干活中）、`blocked`（等你审批）、`done`（完成未查看）、`idle`（已查看的空闲）、`unknown`（无法判断）。

侧边栏默认用**彩色状态图标**展示每个 agent 的状态，逐级向上汇总：一个 agent blocked，它所在的 tab 和 workspace 都会变红。如果更喜欢文字，也可以在配置里把 `state_text` 加到 `[ui.sidebar.agents]` 的 rows 里。

交互上 Herdr 是鼠标优先：点击切换、拖拽分栏、右键菜单，基本不用记快捷键。

## 准备工作

### 安装 Herdr 和 integration

建议先看一眼安装脚本再执行：

```bash
curl -fsSL https://herdr.dev/install.sh | less
```

确认无误后：

```bash
curl -fsSL https://herdr.dev/install.sh | sh
herdr
```

首次运行会进入 onboarding 引导，走完后会自动打开设置界面的 integrations 页签——在这里给常用的 agent 装上对应的 integration 即可（我装了 Claude Code 和 Pi 的），也可以在命令行用 `herdr integration install <agent>` 安装。

integration 不装也能用，但建议装：Herdr 默认靠「识屏」判断 agent 在干什么，装上官方 integration 后改用 agent 自己上报的 lifecycle hooks，状态识别会准确很多。

![Herdr-integrations](/images/herdr/herdr-integration.png)

### 给 agent 装上 Herdr 的「操作手册」：skill

这是最关键的一步，也是很多人容易忽略的一步。

Herdr 官方维护了一份 [SKILL.md](https://github.com/herdrdev/herdr/blob/master/skills/herdr/SKILL.md)，可以理解为「给 AI agent 的 Herdr 驾照」——里面教 agent 怎么拆 pane、怎么启动其他 agent、怎么投递任务、怎么等待结果、读输出，以及一系列安全规则（不抢用户焦点、不关别人创建的东西等）。

安装有统一的命令，一条搞定（底层用的是 [`skills`](https://github.com/vercel-labs/skills)——一个通用的 agent skill 管理器，类似 npm 对 JavaScript 包的角色，会自动装到你机器上所有支持 skill 的 agent 里）：

```bash
npx skills add herdrdev/herdr --skill herdr -g
```

`-g` 是全局安装；去掉则只装到当前项目。如果你的 agent 不在支持列表里，也可以手动兜底：本地已装 Herdr 的话运行 `herdr --skill` 会打印出与当前版本匹配的 SKILL.md，把它拷到 agent 的 skill 目录或粘贴进全局指令文件即可。

装好之后，**只有在 Herdr 托管的 pane 里运行的 agent 才会激活它**（skill 的第一条规则就是检查环境变量 `HERDR_ENV=1`，不在 Herdr 里就直接停下），不会污染你在 Herdr 之外的日常使用。

有了这份手册，主 agent 就从「只会聊天」变成了「会操作终端工作区的工头」——后面整个分派流程都是靠它完成的。

![Herdr-skill](/images/herdr/herdr-skill.png)

## 实战背景

Demo 场景：模拟一个「支付退款」需求，涉及两个仓库：

```text
~/demo/herdr-demo/
 ├── order-service/    # 订单服务，负责退款单创建
 └── user-service/     # 用户服务，负责账户余额退回
```

环境：macOS + Herdr + Claude Code + Pi。这里故意用了两种不同的 agent 工具——Claude Code 擅长大型代码库的理解和重构，Pi 的扩展生态在做特定任务时更顺手。本身只要是支持的工具都可以。

## 阶段一：需求沟通

从项目目录启动 Herdr：

```bash
cd ~/demo/herdr-demo/order-service
herdr
```

创建一个 workspace 叫 `req-pay-refund`，在 pane 里启动主 agent（`claude`），开始讨论方案：退款状态机怎么设计、两个服务各自改什么、接口怎么对齐。几轮讨论下来，方案逐渐收敛——退款用状态机驱动，order-service 负责创建和管理状态，user-service 只负责余额操作和并发控制。agent 自己把讨论结果整理成了明确的任务拆分：

- **order-service**：新增退款单创建接口，状态机 + 幂等处理；
- **user-service**：新增余额退回接口，处理并发安全。

我过了一遍，确认无误，进入下一步。

![Herdr-requirement](/images/herdr/requirement.png)


到这里为止，和传统方式没区别。区别在于下一步。

## 阶段二：任务分派——主 Agent 当工头

这是全文的核心。

传统方式下，现在该我人肉搬运上下文了：整理结论、开新终端、cd、起 agent、粘贴……

而在 Herdr 里，我直接对主 agent 说：

> 方案确定了。把退款单接口的任务派给 order-service，用 Pi 执行；把余额退回接口的任务派给 user-service，用 Claude Code 执行。两个仓库并行开始。

因为主 agent 运行在 Herdr 托管的 pane 里、又装了 skill，它接下来会**自己调用 herdr CLI** 完成整个分派。从它的视角看，动作序列是这样的：

1. **为每个仓库创建独立的 workspace**（指定对应仓库的路径，不抢占我的焦点）；
2. **在新 workspace 的 pane 里启动指定类型的工人 agent**——order-service 起一个 Pi，user-service 起一个 Claude Code——并等它就绪，Herdr 会确认 agent 真正启动完成才返回；
3. **把任务连同需求上下文组织成一段 prompt 投递过去**，然后挂起等待——等工人 agent 到达「完成 / 空闲 / 需要你」的某个落定状态；
4. 工人 agent 完成后，**读取它 pane 里的输出**，把结果汇总回来。

![Herdr-split-task](/images/herdr/split-task.png)


这里有两个值得注意的点。

**一是上下文不落地、不过我的手。** 主 agent 刚刚讨论完方案，需求细节还在它的对话里，它直接把结论组织成任务投给工人 agent——这正是开头那个痛点的解法。如果沟通发生在几个仓库的共同父目录，也一样可行，分派时指定目标仓库路径即可。

**二是分派可以跨 agent 工具。** 工人 agent 不需要和主 agent 是同一种——主 agent 是 Claude Code，它照样可以启动一个 Pi 或 Codex 来干活（Herdr 目前能识别 19 种主流 agent）。这带来一个实际的好处：**可以按任务选工具**。比如某个仓库的改造你用惯了 Pi 的扩展生态，另一个仓库想试试 Claude Code 的表现，甚至可以刻意让两个工具各做一半再互相 review。在没有 Herdr 之前，这种混编几乎只能靠人肉中转。

这些 herdr 命令我不需要记、也不需要敲——它们是给 skill 用的，是 agent 的操作语言。我要做的只是说一句「分派下去」。


### 为什么一个 repo 一个 workspace？

一开始我想过把所有仓库塞进一个 workspace 的多个 pane 里。后来放弃了：侧边栏的状态汇总是**按 workspace 维度**滚动的，两个 repo 各一个 workspace，哪个出事了按项目一目了然；混在一起就只剩一锅粥。

## 阶段三：并行开发的监控与验收

任务分派完，两个工人 agent 开始并行干活。这时候我的工作方式变成了：

1. 扫一眼侧边栏；
2. 红色（blocked）→ 点过去处理审批或回答问题；
3. 绿色（done）→ 点过去验收结果；
4. 黄色（working）→ 不用管，去喝口水。

演示一次完整的 blocked 交互：user-service 的 Claude Code 在执行一个写文件操作时需要审批——

![Herdr-sub-task](/images/herdr/sub-task.png)

在侧边栏看到 user-svc 变红，点进去确认放行，状态转回 working，全程不到十秒。

想深入看某个 agent 的完整界面，可以直接「附着」到它身上，看完即走，agent 不受影响。同样，这个操作在右键菜单里就有，不用记命令。

## 阶段四：联调与收尾

两个接口都完成后进入联调。这里用 tab 做视图划分：`agents` tab 放干活的 agent，`server` tab 起本地服务，`logs` tab 看日志和跑测试。

起服务、跑测试、tail 日志这些是**普通终端进程**，不需要 agent 状态机——直接在对应 tab 的 pane 里跑就行，或者让工人 agent 自己起服务自测、自己等测试结果。Herdr 对这种普通进程也提供了「等某行输出出现」的能力（比如等 `BUILD SUCCESS` 或端口 ready），这些同样由 agent 通过 skill 调用。

联调通过后，让主 agent 汇总两个仓库的变更，做最终检查——它会对比两边接口的参数定义、确认状态流转一致。这次 demo 场景简单，联调没遇到意外。需求彻底结束，把对应的 workspace 关掉即可。

## 实际使用中的取舍

写到这里，有必要诚实地说几个限制——免得你装上之后发现跟预期不完全一样。

**Demo 场景简单，不代表所有项目都顺。** 这次的退款需求只有两个仓库、两个接口，依赖关系清晰。真实项目里仓库更多、接口更复杂、agent 生成的代码质量参差不齐——Herdr 解决的是「递任务」和「看状态」，不解决「代码对不对」。工人 agent 交上来的东西还是得人验收，只是省掉了你来回切终端、复制粘贴上下文的体力活。

**单 repo 简单任务，用 Herdr 反而增加负担。** 如果你平时只在一个仓库里干活、一次只跟一个 agent 聊，Herdr 的 workspace / tab / pane 三层模型对你来说是多余的认知成本。它的甜区是：你同时开着至少两个 agent、或者需要在多个仓库间频繁切换上下文。


## 总结

用了一段时间后，我对 Herdr 的理解是：它的价值不是「分屏」，也不只是「看状态」——状态展示现在很多工具都在做。

它真正稀缺的能力是**递得出任务**：CLI 和 socket API 让 agent 之间可以互相编排，而且不挑工具——Claude Code 可以给 Pi 派活，Pi 也可以给 Codex 派活。加上官方 skill 把这套操作变成了 agent 的标准技能，需求沟通和执行之间的上下文断裂就这样被接上了。人在这个流程里的角色，从「终端调度员 + 上下文搬运工」变回了「决策者」——讨论方案、处理审批、验收结果。

如果你平时只开一个 agent，这套东西意义不大；但如果你已经开始并行跑多个 agent、尤其是跨仓库协作，它值得一试。

## 参考

- [Herdr 官方文档](https://herdr.dev/docs/)
- [核心概念](https://herdr.dev/docs/concepts/)
- [Agent 自动化](https://herdr.dev/docs/agent-automation/)
- [Agent Skill 安装](https://herdr.dev/docs/agent-skill/)
- [配置参考](https://herdr.dev/docs/configuration/)
