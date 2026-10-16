---
title: codemode：让 Agent 学会写代码调工具
date: 2026-10-16 20:30:00
tags: [AI辅助, 工程实践, 工具]
---

MCP（[Model Context Protocol](https://modelcontextprotocol.io/)）解决的是很实际的问题：以前给 agent 加工具，得给每个工具单独写对接代码，改一次要改好几处；有了 MCP，写一次 server，所有支持的 agent 都能接上。

麻烦也出在这里：接起来容易，就容易接多。连几个 server，还没开始打字，上下文里已经堆了两万多 token——全是还没用到的工具说明书。

<!-- more -->


## 一、MCP 带来的三个新问题

### 第一，工具定义本身要占地方

我实测了两个最常见的 server：*折算按 4 字符 ≈ 1 token 估算。*

| | 工具数 | 定义体积 | 折算 token |
|---|---|---|---|
| filesystem | 14 | 13.1 KB | ~3,300 |
| memory | 9 | 11.1 KB | ~2,800 |
| 合计 | 23 | 24.2 KB | ~6,000 |

六千 token 不算大，但它是每次请求都要带上的。128k 的窗口，这两个 server 固定占掉 4.7%。pi 的作者 Mario Zechner [实测过](https://mariozechner.at/posts/2025-11-30-pi-coding-agent)：Playwright MCP 21 个工具 13.7k token、Chrome DevTools MCP 26 个工具 18k——两个 server 就吃掉接近四分之一，而原话里的口径是「还没开始干活，7-9% 的窗口就没了」。

### 第二，工具多了，模型会选错

工具名差不多的时候尤其明显，比如 `notification-send-user` 和 `notification-send-channel`，模型很难判断该用哪个。Anthropic 在[一篇讲工具按需加载的文章](https://www.anthropic.com/engineering/advanced-tool-use)里给过评测：在 58 个工具的系统里，把「全部工具定义都给模型」改成「只给一个搜索工具、按需查出相关的几个」，准确率反而涨了——Opus 4 从 49% 到 74%，Opus 4.5 从 79.5% 到 88.1%，token 同时省了 85%。

也就是说，「把全部工具都告诉模型」付出的不止是 token，还有准确率。

### 第三，中间结果也要经过模型

因为调用方式是这样的：模型说「读文件 1」，结果回到上下文，模型再说「读文件 2」，结果又回到上下文。每读一个文件，模型就要重新看一遍前面的所有内容。极端一点：分析一个 10 MB 的日志，它只要个错误频率，整个文件也得先进来。

**这三个问题里，第一、二个是「工具怎么进模型」，第三个是「工具怎么被调用」。** 前者已经有办法（按需加载、搜索发现），后者才是 code execution 要解决的。


## 二、codemode 的思路：让模型写代码，而不是一步步调工具

第三个问题的直接原因是「模型一步一步走」。换个方式：**让模型写一段程序，程序自己去查数据、自己算，最后只把答案交回来。**

这就是 codemode：它给模型一个 JavaScript 沙箱，脚本里可以调用工具。模型传过去的参数不是 JSON，而是一段代码（工具名先混个脸熟，billing 这个例子下一节会展开）：

```js
const res = await tools.mcp__billing__list_invoices({});        // 查数据（返回 { content: [...] }）
const raw = res.content.map((c) => c.text ?? "").join("\n");
const overdue = raw.split("\n").filter((l) => l.includes("overdue"));
// 聚合、排序都在脚本里做完，下面这行是唯一回到模型的东西
return overdue.length;
```

对比一下：

| | 谁在循环 | 中间结果在哪 | 模型看到什么 |
|---|---|---|---|
| 一步步调工具 | 模型 | 全部回到上下文 | 每一次查询的完整结果 |
| codemode | 脚本 | 留在脚本的变量里 | 只有最后 return 的值 |

## 三、实测：三组对照

前面都是道理，这一节是实跑。整个实验整理成了一个可以直接跑的 demo。

### 场景

一个 billing 服务，只通过 MCP 暴露三个工具：

- `list_invoices` → 返回 200 条发票（约 11.4 KB）
- `get_invoice` → 查单条详情
- `set_invoice_status` → 改状态

任务：

> 找出 overdue 金额合计最高的客户，把它的 overdue 发票改成 signed，报告结果。

数据是固定种子生成的，标准答案唯一。**先复算标准答案**（这一步不经过 pi，直接和 MCP server 对话）：

```bash
cd codemode-billing-demo
node scripts/verify-baseline.mjs
```

```
发票总数: 200
overdue 总数: 66
overdue 金额合计最高的客户: Initech | 金额: 52383.89 | 张数: 9
它的 overdue 发票: INV-0003, INV-0027, INV-0051, INV-0075, INV-0099, INV-0123, INV-0147, INV-0171, INV-0195
```

### 三组只改工具集

同一台机器、同一个模型，唯一变量是给模型的工具：

| | 给模型的工具 | 顶层调用 | 总 token | 结果 | 状态改动落在哪 |
|---|---|---|---|---|---|
| A | bash + read | 38 × bash | 40.9k | 三问全对 | **模型自己另起了一个 server 实例**，pi 看不到 |
| B | 只有 codemode | 6 × codemode | **7.6k** | 三问全对 | pi 的实例，MCP 调用全部可查 |
| C | bash + read + **MCP 工具直接暴露** | 9 × bash | 18.8k | 三问全对 | 又是模型自建的实例，pi 看不到 |

```bash
scripts/run-arm.sh A     # bash + read（MCP 工具不进工具列表）
scripts/run-arm.sh B     # 只有 codemode
scripts/run-arm.sh C     # bash + read，且 MCP 工具直接暴露（exposure=direct）
```

（脚本会临时改 `~/.pi/agent/mcp.json` 来切换工具集，跑完自动恢复。token 数每次跑会有出入——模型走法略有不同——但结构结论稳定。）

### A 组：模型绕了一个大圈

拿不到 MCP 工具，它就**自己写了一个 MCP 客户端脚本，用 bash 跑**。读票、算账、改状态全靠这个脚本，pi 只看到「跑了 38 次 bash」——比 C 组的 9 次多出好几倍（会话记录里能看出它在反复试探，但看不出确切原因）。

关键在最后那步——它连的是自己新建的 server 实例，所以**状态改动发生在 pi 管辖范围之外**，对 pi 来说这次操作等于没发生过。

### B 组：6 段脚本，调用全部留在账本上

这一段值得细看，因为它是 codemode 的正面展示。

先看账：审计脚本能把每一次嵌套调用逐条打出来——

```bash
node scripts/check-session.mjs results/sessions-B/<session>.jsonl
```

```
顶层工具调用: {"codemode":6}
嵌套调用数: 21
  mcp__billing__list_invoices({})                        ← 拉全量数据
  mcp__billing__set_invoice_status({"id":"INV-0003","status":"signed"})
  ...（共 9 张）
  mcp__billing__get_invoice({"id":"INV-0003"})           ← 逐条复核
  ...（共 9 张）
usage: input=430  output=534  totalTokens=7620
```

再看模型实际写的脚本（完整 6 段在仓库 `examples/` 里）。核心那段是这样的：

```js
const res = await tools.mcp__billing__list_invoices({});
const raw = res.content.map((c) => c.text ?? "").join("\n");
const rows = raw.split("\n").map((l) => l.trim()).filter(Boolean).map((l) => {
  const m = l.match(/^id=(\S+) customer=(\S+) amount=([\d.]+) status=(\S+)$/);
  return m ? { id: m[1], customer: m[2], amount: parseFloat(m[3]), status: m[4] } : { bad: l };
});
const agg = {};
for (const r of rows) {
  if (r.status !== "overdue") continue;
  agg[r.customer] = agg[r.customer] || { sum: 0, ids: [] };
  agg[r.customer].sum += r.amount;
  agg[r.customer].ids.push(r.id);
}
const sorted = Object.entries(agg)
  .map(([c, v]) => ({ customer: c, sum: Math.round(v.sum * 100) / 100, count: v.ids.length, ids: v.ids }))
  .sort((a, b) => b.sum - a.sum);
store("top", sorted[0]);          // 结论存进会话，下一段脚本用 load("top") 取
```

3,000 多行发票数据全留在这个脚本里，模型只看到最后那个结论。**注意最后一行**：`store()` 把结论存在会话分支上，不占上下文——下一段脚本直接 `load("top")` 拿到 9 张发票号，`Promise.all` 并发改状态，中间没有任何数据回到模型。

整个任务它写了 6 段脚本，分工很清楚：拉数据 → 解析聚合 → 存结论 → 并发改状态 → 逐条复核金额。**21 次 MCP 调用，每一次的参数和结果都能在会话记录里查到。**

### C 组：工具就在眼前，它还是绕开

这组最反直觉：MCP 工具**直接出现在它的工具列表里**，它还是选了自己写 bash 客户端（还顺手在磁盘上多留了个文件）。

**所以关键不是「有没有把工具暴露出来」，而是模型会更自然地走它熟悉的那条路。** 这条路能到终点，但过程不可见、改动不落地、账目也归不到 pi 头上——A、C 两组跑完，会话记录里只有 bash。

> 这个 demo 可以独立跑，代码在 **https://github.com/zavier/codemode-billing-demo**（public，MIT）。


## 四、在 pi 里 codemode 长什么样

codemode 本身也是一个工具，但它给的是一个运行环境（QuickJS 沙箱）：

- 沙箱里没有文件系统、没有网络、没有定时器，也没有 Node 的 API（完整限制见第五节）。脚本想看外面，只能通过 `tools.xxx()`。能调哪些工具取决于 harness 给了沙箱哪些——这正是第三节能成立的原因。
- **每次 `tools.xxx()` 调用都会记录在会话里、过权限、计费。** 这一点和 bash 不一样：bash 里干了什么，pi 是不知道的（A、C 两组就是这么绕过去的）。
- 工具名里的特殊字符会换成下划线：`mcp__billing__list_invoices` → `tools.mcp__billing__list_invoices`。
- 沙箱内存上限 256 MB，脚本里不能再嵌套调 codemode。
- 除了工具，还能调分类模型和图像模型。

开启方式：

```bash
pi --tools +codemode          # 单次开启
# 或在 ~/.pi/agent/settings.json 里加 "defaultTools": ["+codemode"]
```

和 MCP 的分工：**MCP 管「工具怎么接上」，codemode 管「工具怎么被调用」**。两者不在一个层面，所以 codemode 不是 MCP 专属的；但 MCP 工具多了之后，需要 codemode 这类方案，不然第一节那三个问题压不住。


## 五、什么时候用，什么时候不用

**适合用的**：工具只能通过 MCP 或沙箱拿到，shell 够不到；需要重复调用很多次、中间结果不该进上下文；**需要每一次调用都留下记录**（第三节 B 组那种）；要调分类模型、图像模型——它们不出现在 `/model` 列表里，只能通过 codemode 调用。

**不适合用的**：本地数据、shell 可用（bash 更简单）；小任务（我在自己的博客仓库试过：统计 112 篇文章的 tag 分布，它直接读了 14 个文件，没碰 codemode，11.7k token、7 秒解决——这个判断是对的；这个实验用私有仓库做的，不可复现）；需要一步步调试、人在环的操作；你自己都还不确定要做什么的探索性任务。**codemode 适合「我知道要重复很多次」，不适合「我还不知道要做什么」。**

**代价**：

- 沙箱比想象的小：没有文件系统、没有网络、没有定时器，内存 256 MB 上限。等一个永远不会返回的 Promise 会直接失败，因为没有定时器让它超时。
- 需要运维一个执行环境——沙箱、资源限制、审计。这部分普通工具调用不需要承担。
- 脚本里 `return` 和 `console.log` 出去的东西照样进上下文，`max_output_tokens` 默认只有 10000。


## 六、小结

- MCP 解决了工具怎么接的问题，代价是工具定义变成固定开销，还让模型更容易选错。
- codemode 换了个思路：模型写一段程序，程序自己循环、自己处理中间数据，最后只把答案交回来。
- 第三节那个实测里，MCP 工具直接暴露时模型反而自己写了 bash 客户端绕过去；收进沙箱之后，21 次调用全部留在会话记录里，token 还降到两成。**codemode 在这里的价值不是「更快」，是「留在账本上」。**
- 用得对不对全看场景：本地数据有 shell 就用 bash；工具在沙箱里、需要可审计，才轮到 codemode。

### 附：复现材料

**https://github.com/zavier/codemode-billing-demo**

```
codemode-billing-demo/
├── README.md                 三步复现说明（先算标准答案 → 跑三组 → 审计）
├── mcp/server.mjs            MCP server（200 条发票，固定种子，内存态）
├── scripts/
│   ├── verify-baseline.mjs   独立复算标准答案（不经过 pi）
│   ├── run-arm.sh            跑一组实验（A|B|C）
│   └── check-session.mjs     审计会话：嵌套调用 + token
└── examples/                 B 组实际生成的脚本完整记录
```
