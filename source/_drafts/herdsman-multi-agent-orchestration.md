---
title: 用 Pi Herdsman 编排 Agent 编队：从「派得出任务」到「接得住结果」
date: 2026-10-14 16:30:00
tags: [AI辅助, 工程实践, 工具]
---

两个月前我写了[《用 Herdr 让 AI Agent 互相派活》](/2026/08/09/herdr-multi-agent-workflow/)。那篇的结论是：Herdr 真正稀缺的能力是**递得出任务**。

用了两个月，我发现那只是前半句——**任务递出去了，结果不一定回得来**：

- **结果可能读不回来。** 工人 agent 如果用了全屏 TUI 渲染，回答滚出屏幕之后，`herdr agent read --lines` 调到多大都捞不回来。Herdr 官方的兜底是「让 agent 把回答写成文件、只回一个路径」——本质上就是让 agent 手工模拟一次结构化投递。
- **`--wait` 等的不是「你发的那条 prompt」。** 官方原话：*This wait tracks lifecycle state, not an individual turn*。工人已经在干活时，你这次的等待可能被**上一轮**的完成满足，你以为读到的是这次的结果，其实是上一次的。
- **完成后主 agent 根本感知不到。** 最要命的一条。你得自己记得回去说一句「看看结果」，它才会去读。

最后一条的原因很朴素：**LLM 会话「感知」某件事的唯一方式，是在某一轮里读到那些文字。没有新一轮，就没有感知。** 而 Herdr 跑在 Pi 进程**外面**，它没有任何通道能回调进去。

这篇写的是 [Pi Herdsman](https://github.com/boadij/pi-herdsman)——它在 Herdr 之上补的正是这一层。

<!-- more -->

## 三步跑起来

```bash
pi install npm:pi-herdsman
herdr integration install pi
```

然后在 Herdr 的 pane 里启动 Pi：

```bash
herdr
# 在 pane 里
pi
```

**必须在 Herdr 的 pane 里**——Herdr 外面启动的 Pi 会话管不了 Agent，`/herdsman` 会退化成「安装诊断」模式。

就这三步。之后不用记任何命令，直接说人话：

> 让 scout 摸一下 order-service 的订单状态机，重点看现有状态迁移路径、有没有和退款态冲突的地方。

它会自己调用 `delegate_agent`，起一个**只读**的 agent 去干，你继续忙别的。

> **名字不用记。** `scout` / `implementer` / `reviewer` / `researcher` / `generalist` 这五个名字是给模型看的，挑选依据是定义里的 `description`。不点名它也会猜。但**如果你在意权限边界就点名**——「让 scout 看」等于钉死它只能读，改不了你的文件。
>
> 想知道有哪些 agent 在跑、整棵会话树花了多少钱，打开 `/herdsman` 面板。

## 走一个完整需求

还是上一篇那个「支付退款」需求，还是那两个仓库：

```text
~/demo/herdr-demo/
 ├── order-service/    # 订单服务，负责退款单创建
 └── user-service/     # 用户服务，负责账户余额退回
```

但这次重点在 `order-service` 一个仓库里——因为**退款状态机**才是真正的硬骨头：状态怎么定义、幂等怎么做、和已有订单状态怎么兼容。这就是 Herdsman 和 Herdr 的分工差异：

> **Herdr 擅长「水平」拆——多仓库、任务浅、彼此独立；Herdsman 擅长「垂直」拆——一个目标拆成多层，每层有明确的所有权和交付物。**

下面走一遍垂直拆。

### 第一步：先派个 agent 去摸代码

方案聊到一半，你会发现自己需要弄清几件事，但不该自己一个个去翻：现有状态机里哪些状态能迁到退款态？幂等键该用什么？项目里有没有相似实现可以参考？

这些活范围明确、只读、结果可检查，正是该委派的：

> 让 scout 摸一下 order-service 的订单状态机，重点看现有状态迁移路径、有没有和退款态冲突的地方、有没有相似实现可以参考。

说完这句就可以**不管它了**。

> **坑点：委派完先结束这一轮。** 这是 Herdsman 契约里最反直觉的一条——别守着等结果，去做你自己还拥有的、不相干的事；没有就直接停下。原因在[后面](#它凭什么能自动叫醒你)讲。

### 第二步：方案定了，再让它动手

scout 回来了，确认状态机里有两条迁移路径和退款态冲突，而且历史订单归档模块有现成的幂等约定可以参考。

这时候换 `implementer`——**它是可写的**，前面那个 scout 改不了代码：

> 让 implementer 按这个方案把退款状态机实现出来，参考历史订单归档那套幂等约定，重点处理那两条冲突的迁移路径。

一次把要求说完，比来回挤牙膏效率高得多。

> **这也是和「派活」最大的区别。** Herdsman 的委派不是一句话，而是带 `task`（有界目标）和 `files`（证据）的契约。`files` 可以放文件和**已完成任务的结果引用**，形如 `result:scout#1`——转手给下一个 agent 时引用原样保留，身份不变。
>
> 对比上一篇的做法：主 agent 是「把结论组织成一段 prompt」，那是**字符串投递**，内容糊进文本里，和源文件脱钩。

### 第三步：换一个 agent 复查

写完了别让写的人自己检查。再派一个 `reviewer`：

> 让 reviewer 复查这次退款状态机的改动，重点看并发安全和状态迁移的边界情况。

`reviewer` 定义是**只读**的——它物理上改不了你的代码。所以它交上来的只有意见，不会顺手「帮你改一下」。

reviewer 提了两个问题，回到 Lead；Lead 把意见转给 implementer 改，再让 reviewer 确认。整个来回我要做的只有：**在它问我决策的时候回答**。

> **这一轮的结果，会自动送到你面前。** 不需要你回去问「做完了吗」——这正是 Herdsman 解决的核心问题。

### 第四步：联调——这部分还是 Herdr 的活

起服务、跑测试、tail 日志是**普通终端进程**，Herdsman 故意不管——它只管 agent 会话。所以这部分还是上一篇那套：

```bash
herdr pane run <pane-id> "mvn -q test -Dtest=RefundStateMachineTest"
herdr pane wait-output <pane-id> --match "BUILD SUCCESS" --timeout 300000
```

`wait-output` 直接等某行输出出现，比反复读屏幕好得多。

> **分工原则：按「谁拥有这个工作单元」分，不按工具偏好分。** 一个工作单元只能登记给一套——交给 Herdsman 的就等它唤醒你，自己用 Herdr 管的就自己去看。两边都登记，就回到「感知不到」的老问题上了。

## 它凭什么能自动叫醒你

这是 Herdsman 唯一值得讲的原理，因为它就是全部的价值所在。

Herdsman 在启动子 agent 时，会通过环境变量把它的「信箱」目录传给子进程（`PI_HERDSMAN_MAILBOX`）。目录里就是几个普通文件：

```text
state.json                  # 任务状态：活跃请求、已完成请求、待回答的问题
request-<requestId>.json    # 投进来的请求
ask-<askId>.json            # agent 反过来问 owner 的问题
result-<requestId>.json     # 终态结果
```

子 agent 干完活，结果写进 `result-<requestId>.json`。**而 Lead 那边——同一个 Pi 进程里——的扩展会把它取出来，用 Pi 的扩展 API 注入：**

```js
pi.sendMessage(
  { customType: "pi-herdsman-agent-result", content, display: true, details },
  { triggerTurn: true, deliverAs: "steer" }
);
```

**`triggerTurn: true` 就是那三个坑的解药**：它给 Lead 的会话**强制开一轮**，即使 Lead 正闲着。

所以「委派完就结束回合」不但安全，而且是对的做法——**你停下，扩展会把你叫醒**。而在纯 Herdr CLI 的方案里，结束回合是致命的：没有人会叫你。

投递进来的内容长这样：

```text
Agent result · agent=scout · definition=scout · session=<id> · status=completed

Result ref: result:scout#1

（agent 写的完整正文）
```

每个完成的任务还会在磁盘上留一个带溯源头的产物，我翻了一下数据目录：

```text
~/.pi/agent/pi-herdsman/results/d56c1081-692b-4329-9abb-b20bccba6a6d

Agent result source: {"agent":"repo-scout","definition":"scout",
  "cwd":"/Users/zheng/code/open-code-review",
  "piSessionId":"01a1393f-4c2c-7769-8b1d-53818cbde425"}

# Repository Orientation: open-code-review
（以下是 agent 自己写的完整 markdown）
```

**记着是谁产的、用的哪个定义、在哪个目录、哪个会话**——这些信息在上一篇的「读屏幕」方案里根本拿不到。

## 几个反直觉的地方

用起来会撞到几条看着莫名其妙的规定，理解上面那个「扩展叫醒你」之后，它们其实都是推论：

| 规定 | 为什么 |
| --- | --- |
| 委派完就结束回合 | 唤醒责任已经从模型转移到扩展进程，不需要你醒着 |
| 不许轮询进度 | 轮询不仅多余，还会烧掉上下文——而且它本来就会主动叫你 |
| 别给两个 agent 派重叠的活 | **每个未决工作单元只有一个执行者**，责任没有歧义才有明确的回收对象 |
| 别用 `read_agent_transcript` 看进度 | 那是给「最后持久化的工作真的影响恢复决策」用的，不是进度条 |

还有两条细节，用久了会 appreciate：

**「说完了」和「被打断了」分得开。** 文档里有句话我印象很深：*An aborted Pi execution is not successful assignment completion, **even when the conversation contains assistant text***。被中断的执行**不是**成功完成，哪怕对话里已经有一段看起来完整的回答。这一点「读屏幕」方案根本做不到——屏幕上都是文字，你怎么知道它是说完了还是被打断了？

**agent 可以反过来问你。** 卡在只有你能拍板的决定上时，它会用 `ask_owner` 提问，问题**结构化地回到它的直属 owner**，你回答之后它自动继续。上一篇里对应的是 Herdr 的 `blocked` 状态——你能看到它红了，但得自己点进去看它在问什么。

## 什么时候别用它

照例，诚实地说三条最重要的限制。

**① 它只编排 Pi。** Managed Agent 全都是 Pi 会话——因为「结果自动回收」依赖子进程里装着 Herdsman 扩展、会往信箱里报终态结果。Claude Code、Codex 里没有这个扩展。

有意思的是，**「只能 Pi」和「结构化结果回收」是同一件事的两面**：上一篇那套跨工具混编之所以必须读屏幕，正是因为那些工具没有这条信箱。想要跨工具，就得接受读屏幕；想要接得住结果，就得接受单工具。

**② 调度单位是一个仓库，不是多个。** 这不是配置问题，是结构问题：`delegate_agent` 没有「目标目录」参数，子 agent 的工作目录固定等于调用方的工作目录；`delegate_project` 也只有 `task / branch / base / files`，没有仓库参数。所以「一个 Manager 编排多个仓库」做不到。

**③ 别在同一个会话里混两套编排。** 如果你一边用 Herdsman 委派、一边又用 herdr CLI 手工起 agent，那个手工起的 agent **不在 Herdsman 的所有权登记里**——收不到自动结果、不进成本统计、出事了也没有恢复路径。要混就分层混（agent 归 Herdsman、普通进程归 Herdr），不要在同一层混。

## 跨仓库怎么办

回到 `user-service` 那半。每个仓库一个会话，用 **peer 通道**对齐就行。

`list_peers` / `message_peer` 是给同角色会话通信用的，而且明确是 **user-global、不按项目过滤**的——就是设计来跨项目的。我写这篇时实际跑了一次：

```json
{"self":"01a13950-a34d-75e3-a69f-b4d15e93464f",
 "peers":[{"session":"01a13971-e54e-75f4-a6b8-6048a34c66d2",
           "name":"lead-01a13971",
           "cwd":"/Users/zheng/code/open-code-review",
           "repo":"","branch":"","workspace_label":"english"}]}
```

另一个目录里的 Pi 会话就在那儿，`cwd` 可见。**而且它的投递方式和结果投递一样是 `triggerTurn: true`**——`message_peer` 发过去会**自动唤醒对方会话**。这正是上一篇缺的那条跨仓库回调。

```text
你：在 repo-A 的会话里讨论方案
   ↓
repo-A Lead：拆出「repo-A 做 X、repo-B 做 Y」
   ↓ list_peers 找到 repo-B 的 Lead
   ↓ message_peer（附接口契约文件）
repo-B Lead：被自动唤醒 → 委派本地 Agent → 完成
   ↓ message_peer 回传（附 result: 引用）
repo-A Lead：被自动唤醒 → 汇总 → 你验收
```

**两个诚实的缺口**：peer 消息**不是任务**（文档原话：*Peer messages are coordination data, not assignments*），所以对方不会「自动回报结果」，得它主动发回；另外 peer 双方必须已经存在，起第二个会话目前还是人的活。

我的实际做法是：**跨仓库的需求，我自己当那个协调器。** 这不丢人——人本来就是合格的跨仓库协调器，只是不该同时当上下文搬运工。

> 顺便修正上一篇的一个数字：我写的时候 Herdr 能识别 19 种 agent，现在是 **24 种**。

## 总结

上一篇的结论是：Herdr 的稀缺能力是**递得出任务**。这篇补上后半句：**递得出任务之后，还得接得住结果。**

Herdr 管物理位置——pane 在哪、进程活没活。Herdsman 管任务状态——谁派给谁、做完没有、结果是什么、谁负责。**这两层是叠加的，不是替代关系。**

回头看，这个演进挺像软件工程里的老故事：**先把任务发下去（异步），再解决怎么知道它完成了（回调）**。没有回调的异步，只能靠轮询——而人肉轮询，恰恰是我一开始想摆脱的那个活。

所以如果你已经走到上一篇那一步——在并行跑多个 agent，但总觉得自己在当「终端调度员 + 上下文搬运工」——那么下一个瓶颈大概率不是「派得更多」，而是「收得更稳」。

反过来，如果你的甜区是**跨仓库、跨工具**，那 Herdsman 现在还替代不了你手上那套 Herdr CLI 方案。我的建议是两个都留着，分层用。

## 参考

- [Pi Herdsman 官方仓库](https://github.com/boadij/pi-herdsman)
- [Getting started](https://github.com/boadij/pi-herdsman/blob/main/docs/getting-started.md)
- [Coordination：角色与权威模型](https://github.com/boadij/pi-herdsman/blob/main/docs/concepts/coordination.md)
- [Delegation：委派与并行](https://github.com/boadij/pi-herdsman/blob/main/docs/concepts/delegation.md)
- [上一篇：用 Herdr 让 AI Agent 互相派活](/2026/08/09/herdr-multi-agent-workflow/)
