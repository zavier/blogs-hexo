---
title: 让 Agent 连数据库：多项目、只读、选对库
date: 2026-10-27 01:10:00
tags: [AI辅助, 工程实践, 工具]
---

[上一篇](/2026/10/25/agent-browser-guide/)讲的是让 AI 替你点网页：点登录、点下单、点保存，最后把截图和接口记录交回来。文末那个例子里，它记了一笔 50.5 元的交通费，账本页上那一行清清楚楚。

可截图只证明页面画出了这一行。它证明不了库里存的是 `5050` 还是 `50.5`，证明不了这笔钱落在哪张表、状态对不对、有没有重复记两次。要确认这些，只能去查数据库。

于是会点网页之后，很自然的下一个想法是：让它也会查库。

对研发来说，这件事的用处比“查询”两个字大得多。日常这三件事都要连库，而且都离不开代码：

| 场景 | 具体在问什么 |
| --- | --- |
| 数据探查 | 我改的这个字段，线上到底有哪些取值？哪个占大头？有没有历史脏数据 |
| 操作后的结果验证 | 页面点了保存、提示成功，库里真的改了吗？改对表了吗 |
| 测试数据构造 | 造之前得知道有哪些唯一约束、哪些枚举、哪些字段非空 |

以前这三件事的办法是：切到数据库客户端，找到连接、写 SQL、把结果复制回对话里。一次两次还行，一天二十次就很难受。

这篇讲怎么把这一步接上，以及接上之后怎么不出事。核心一句话：**难的不是连上，是连上之后还看得懂、改不坏。**

<!-- more -->

## 一、给 agent 加数据库能力，路子基本只有一条

第一反应通常是“给它写个脚本”或者“封装几个接口”——查表、查索引、跑 SQL。能用，但很快会撞上同一个问题：**你在用的不止一个客户端。**

Claude Code 一套插件机制，Cursor 一套，VS Code 一套，Codex CLI 又是另一套。同一件事写四遍，连接串和权限维护四份，改个字段名要同步四处。

MCP（[Model Context Protocol](https://modelcontextprotocol.io/)）解决的就是这个。它的分工是：**把“能做什么”定义在 server 侧，客户端只负责调用。** 写一次 server，所有支持 MCP 的客户端都能接上，配置也就是一段 JSON。

所以 2026 年这件事的现实答案很朴素：**找一个成熟的 database MCP server，配进去。** 不用自己写。

## 二、选型：先立标准，再看工具

工具是最容易过期的部分，所以先说标准。

四个判断轴：

1. **常驻 context 成本。** 工具描述常年躺在 prompt 里。一个库挂一个 server，五个项目就是五份开销。
2. **要不要把查询固定成“结构化工具”。** 只想让 agent 自由探索，一条万能 `execute_sql` 就够；要防它乱写、或者要给非技术同事用，就得预定义 SQL。
3. **库在谁手里。** 自建 MySQL 和托管平台（Supabase、Neon、MongoDB Atlas）差别很大，后者官方 server 知道分支、迁移这些平台语义。
4. **网络。** 内网库、跳板机，决定了你要不要 SSH 隧道。

按这四条对下来，2026 年 10 月大致是：

| 工具 | 适合什么情况 | 代价 |
| --- | --- | --- |
| DBHub（`@bytebase/dbhub`） | 多库混合、要最省的 context、要 SSH 隧道 | 只有通用工具，没有平台语义 |
| MCP Toolbox for Databases（Google） | 要把查询固化成结构化工具、要连接池和审计 | 工具多，默认常驻成本高 |
| Postgres MCP Pro（crystaldba） | 重点是慢查询、索引调优、EXPLAIN | 只支持 PostgreSQL |
| 各平台官方 server | 库托管在 Supabase / Neon / MongoDB / ClickHouse / Redis | 绑定平台 |

我最后用 DBHub，理由是第一根轴：它默认只暴露两个工具（`execute_sql` 和 `search_objects`），而 `search_objects` 正好是“先看 schema 再写 SQL”这个动作需要的。按它 README 里自己给的对照（厂商自测，不是第三方评测），默认加载约 1.4k tokens，而 MCP Toolbox 默认 28 个工具约 19k——差了十三四倍。多项目场景下这个差值是乘出来的。

最小跑通就一条命令（`--dsn` 就是连接串）：

```bash
npx -y @bytebase/dbhub@latest --transport stdio \
  --dsn "mysql://user:pass@127.0.0.1:3306/mydb"
```

需要 Node 22.5 以上（它用了内置的 `node:sqlite`）。跑通这句，agent 已经能查库了——**如果这个账号有写权限，它现在也能删表。**

## 三、单项目：一个仓库对一个库

研发日常基本都是这个形态：一个项目、一套库、一套账号密码。所以配置要回答的问题只有一个——**这个仓库用哪套连接串。**

我不会把连接串写进仓库。分成两份：

```text
~/.config/dbhub/acme-shop.toml       ← 连接串 + 护栏，chmod 600，不进 git
        ▲ --config 引用
acme-shop/.pi/mcp.json               ← 可以提交，没有密码
```

第一份记得 `chmod 600`——里面有密码；第二份要进仓库，所以只放路径。

一次查询经过的东西就这三段：

```mermaid
flowchart LR
    Repo["仓库<br/>acme-shop/.pi/mcp.json"] -->|"决定加载哪份配置"| Toml["~/.config/dbhub/acme-shop.toml<br/>dsn / readonly / max_rows"]
    Toml -->|"用哪个账号连"| DB[(MySQL<br/>acme_shop)]
```

图里这条链就三环：仓库 → 配置 → 账号。

仓库里那份只有一句话：

```json
{
  "mcpServers": {
    "db": {
      "command": "npx",
      "args": ["-y", "@bytebase/dbhub@latest", "--transport", "stdio",
               "--config", "~/.config/dbhub/acme-shop.toml"]
    }
  }
}
```

关于账号只提一句：**别把你平时那个主账号直接给它。** 单独开一个只读账号（一行 `GRANT SELECT` 的事），名字叫 `ro_xxx` 就行。理由下一节会讲——不是怕它造反，是怕配置漏了一行。

## 四、配置与工具：哪些必配，哪些按需

一份能用的 toml 大概长这样，注释标了哪几个是必配的：

```toml
# ~/.config/dbhub/acme-shop.toml
[[sources]]
id            = "shop"                                  # 必配：给这个源起名
description   = "acme-shop 仓库的商城库：users/orders"    # 必配：模型靠这句话判断该不该用
dsn           = "mysql://ro_shop:<密码>@127.0.0.1:3306/acme_shop"  # 必配
charset       = "utf8mb4"                               # 必配：中文库不加这项，取出来是乱码
query_timeout = 30                                      # 建议：防慢查询拖住库
ssh_host      = "bastion.internal"                      # 可选：内网库走隧道，配 ssh_user/ssh_key
```

`sources` 那段解决的是“连哪个库”。工具侧什么都不写也能用——DBHub 默认就给你两个工具：`execute_sql` 和 `search_objects`。

**但它默认不管你要不要只读，也不管一次拉多少行。** 想要这两样，才需要写 `[[tools]]`：

```toml
[[tools]]
name     = "execute_sql"
source   = "shop"
readonly = true        # 只读：见下
max_rows = 200         # 行数上限：防一次拉回五十万行

[[tools]]
name   = "search_objects"
source = "shop"
```

这里有个没提示的坑：**一旦写了 `[[tools]]`，默认那两个工具就会被你列出的这一整套替换，不是追加。** 我第一次只写了 `execute_sql`，结果工具列表里只剩一个：

```text
tools: ['execute_sql']
```

`search_objects` 没了——而它恰恰是让 agent“先看清表结构再写 SQL”的关键，没有它模型只能猜字段名，猜错了再执行，白烧几轮。

但同一条规则，换个角度看就是好事：你要是需要它，丢了叫配错；你不需要它，那叫特性。想让哪个工具在，就把哪个写进去——只写一个，另一个就真的消失。

比如某个库只想让 agent 看结构、不许它查数据：

```toml
[[tools]]
name   = "search_objects"
source = "shop"
```

这时候 `execute_sql` 这个工具压根不存在，模型去调会被直接拒绝：

```text
Tool execute_sql not found
```

这比下面要讲的 `readonly` 更硬一层：`readonly` 是“能执行 SQL，但只准读”，选择性暴露是“根本没有执行 SQL 的能力”。生产库、或者只想让它摸 schema 的场合，用这个。

### `readonly`：不写这一行，只读是假的

这是全文最想让你注意的地方，因为它反直觉。

我拿一个**可写的** MySQL 账号做对照：配置文件里只写 `[[sources]]`、不写 `[[tools]]`，让 agent 执行一句 `UPDATE`（下面两段返回都只摘了关键字段）。

```json
{ "success": true, "data": { "statements": [ { "count": 1 } ] } }
```

**成功了。** 也就是说，很多人配完跑通的那个状态，DBHub 根本不知道你要只读——默认什么都放行。

加上 `readonly = true`，同一句变成：

```json
{ "success": false, "error": "Read-only mode is enabled...", "code": "READONLY_VIOLATION" }
```

所以：**如果你要的是只读，这一行就没有“按需”的余地。** 不写它，你拿到的是一个能删表的数据库客户端，只是没人去删。

`readonly` 不是拦一切，是白名单：只放行 `select / with / explain / show / describe / desc`。所以 `WITH ... SELECT` 不会误伤。配上之后工具描述里还会自动带 `[READ-ONLY MODE]`，模型第一眼就知道不能写，少撞一次墙。顺带一提，`BEGIN`/`COMMIT` 也不在白名单里——只读模式下跑不了事务，不会出现“一半成功”的中间状态。

### `max_rows`：让它知道“这只是前 200 行”

agent 不知道你的表多大，`SELECT *` 一下拉回几十万行，冲爆的不只是钱。配上上限之后，超出时会给一个明确标记：

```json
{ "count": 200, "truncated": true }
```

模型看得见 `truncated`，就知道“我只要到了前 200 行”，而不是默认这就是全部——否则它会拿一部分数据给你下一个错误的结论。这个标记比上限本身更值钱。

### 再进一步：把常用查询固化成工具

到这里，agent 拿到的还是“一条能随便写的 `execute_sql`”。如果有些查询是固定的、团队天天要跑，可以在同一份 toml 里把它定义成自己的工具（暂时没这需求的话，这节可以跳过）：

```toml
[[tools]]
name        = "orders_by_status"
description = "按状态统计订单数"
source      = "shop"
statement   = "SELECT status, COUNT(*) AS n FROM orders WHERE status = ? GROUP BY status"

[[tools.parameters]]
name           = "status"
type           = "string"
description    = "订单状态"
allowed_values = ["paid", "pending", "refunded"]
```

注册出来就是个普通 MCP 工具。模型看到的不是空白 SQL 输入框，而是“一个状态参数，可选三个值”；传别的值会在执行前被拦掉：

```text
Input validation error: status: Invalid option: expected one of "paid"|"pending"|"refunded"
```

这正好落在第二节那根判断轴上。固定下来有三个好处：**参数有类型和枚举约束**、**SQL 不给模型看**（它改不了 `WHERE`）、**团队共用一份定义**。代价是灵活性——新问题得加新工具，探索性查询还是靠 `execute_sql`。所以两个都留着，看场景切。它和 `readonly` 也不冲突——自定义工具本身就是写死的 SQL，护栏照样开着。

（占位符各库不同：MySQL 是 `?`，PostgreSQL 是 `$1`，SQL Server 是 `@p1`，Oracle 是 `:1`。换库只改这一处。）

### 调配置的时候，怎么快速看对不对

不用每次都开客户端。让 DBHub 走 HTTP 在本机起一个，自带网页调试台：

```bash
npx @bytebase/dbhub@latest --transport http --host 127.0.0.1 --port 8080 \
  --config ~/.config/dbhub/acme-shop.toml
```

浏览器打开 `http://localhost:8080` 就是 Workbench：能直接跑工具、看最近几次请求的 trace。手边没有库也能先看看长什么样，单独跑一条 `--demo` 就行。

`--host` 一定要带。它默认是 `0.0.0.0`，也就是绑到所有网卡，而 Workbench 没有鉴权——同一个网段里谁都能连云查数据。本机自己用，没有理由不带 `127.0.0.1`。

## 五、多项目：三种方案

手上四五个项目、各有各的库，这时问题变成“进哪个仓库，连哪个库”。

先说清目标：**不是拦住它查别的库**——有些项目本来就要跨库，拦了反而碍事。目标是少一次判断，让它默认站在正确的库前面。

三种做法，我都实测过。

### 方案 A：每个仓库一份项目级配置（推荐做默认）

就是第三节那个形态。仓库里只写“用哪份 toml”，连接串留在仓库外。

好处是**这个仓库默认只有一个库的连接**：不是靠模型判断该用哪个，而是根本不用判断。顺带还解决“项目配置要提交、密码不能进去”的问题。

### 方案 B：一个项目挂多个 server（要跨库时叠加）

项目确实要查两三个库时，就在同一个 `.pi/mcp.json` 里挂多个：

```json
{
  "mcpServers": {
    "db-shop": {
      "command": "npx",
      "args": ["-y", "@bytebase/dbhub@latest", "--transport", "stdio",
               "--config", "~/.config/dbhub/acme-shop.toml"],
      "description": "acme_shop 商城库(只读)：users / products / orders"
    },
    "db-blog": {
      "command": "npx",
      "args": ["-y", "@bytebase/dbhub@latest", "--transport", "stdio",
               "--config", "~/.config/dbhub/acme-blog.toml"],
      "description": "acme_blog 内容库(只读)：posts / comments"
    }
  }
}
```

工具名会带 server 前缀（`mcp__db_shop__execute_sql` 这种），等于库名写在最前面。每份 toml 各管自己的 `readonly` 和 `max_rows`，某个库以后要开写权限，只改它那份，不牵连别的。

实测一次会话里同时查两边是通的：本地 demo 库里 `orders` 五单、合计 328400 分，`posts` 里 views 最高那篇 1503。

### 方案 C：一份 toml 挂多个 source

省进程，但工具名会变成 `execute_sql_shop` / `execute_sql_blog`：

```text
tools: ['execute_sql_shop', 'search_objects_shop', 'execute_sql_blog', 'search_objects_blog']
```

麻烦在**选错不报错**。模型选了 `execute_sql_blog` 去查本该属于 shop 的东西，得到的只是“表不存在”，而不是“你选错库了”。而且每个 source 都得单独写一遍 `[[tools]]` 才有只读，漏一个那个库就裸奔。

库多到五个以上、全是只读、又只想维护一份文件时，这个方案才划算。

按顺序用：**A 做默认，B 做补充，C 做妥协。**

## 六、换客户端要不要重写

不用。这类 server 都是一个本地进程加 stdio，配置内容就三样：启动命令、参数、环境变量。所以所有支持 MCP 的客户端都能用，要改的只是配置放哪、顶层键叫什么。

| 客户端 | 配置文件 | 顶层键 | 格式 |
| --- | --- | --- | --- |
| Claude Code | `.mcp.json`（项目）/ `~/.claude.json`（用户） | `mcpServers` | JSON |
| Cursor | `.cursor/mcp.json` / `~/.cursor/mcp.json` | `mcpServers` | JSON |
| pi | `.pi/mcp.json` / `~/.pi/agent/mcp.json` | `mcpServers` | JSON |
| VS Code (Copilot) | `.vscode/mcp.json` | **`servers`** | JSON |
| OpenAI Codex | `~/.codex/config.toml` | `mcp_servers` | **TOML** |

注意两个例外：VS Code 的顶层键是 `servers` 不是 `mcpServers`，抄过去会静默不生效；Codex 用 TOML 不用 JSON。

Claude Code 直接用命令写进项目最省事：

```bash
claude mcp add --scope project db-shop -- \
  npx -y @bytebase/dbhub@latest --transport stdio \
  --config /Users/you/.config/dbhub/acme-shop.toml
```

只用 Claude Code、又只有一个库的话，还有更省事的一条路——装官方插件：

```text
/plugin marketplace add bytebase/dbhub
/plugin install dbhub@dbhub
```

它自带 `readonly = true` 和 `max_rows = 1000`，连接串存进安全存储（不进配置文件），另附 `/dbhub:setup`（帮拼连接串）和 `/dbhub:explore`（教模型按渐进披露读 schema）两个技能。

代价是只覆盖“单库 + 只读”：多库、要写、要隧道、要自定义工具，还是回上面的 toml 路径。切过去之前记得在 `/plugin` 里关掉插件自带的 server，否则会同时跑两个实例。

Codex 那份 TOML：

```toml
[mcp_servers.db-shop]
command = "npx"
args = ["-y", "@bytebase/dbhub@latest", "--transport", "stdio",
        "--config", "/Users/you/.config/dbhub/acme-shop.toml"]
```

**这里有个跨客户端的小坑：`~` 展开各家不一致。** 有的客户端认 `~/`，有的原样传给子进程，路径变成字面量 `~/.config/...`，报文件不存在。稳妥做法是写绝对路径，或者用 `${HOME}` 这类环境变量插值。同一个路径我在两个客户端里遇到过一个能跑一个报错，就是它。

## 七、实战：三种问法

回到开头那三件事。接上之后，我发现自己反复在问三类问题，共同点是——**不让模型猜，让它先查再说。**

### 1. 数据探查：把代码里的枚举和库里的真实分布对齐

代码里写着：

```ts
export const ORDER_STATUSES = ["paid", "pending", "refunded"];
```

我会让它查：

```sql
SELECT status, COUNT(*) AS n FROM orders GROUP BY status ORDER BY n DESC;
```

再问一句：“有没有代码里没定义的值？有没有定义了但库里从没出现过的？”

这类漂移很常见：历史脏数据留着老状态、灰度功能的值还没上线、删掉的枚举没人清。以前只能人肉翻。

### 2. 结果验证：页面说成功，不等于库里改对了

这是接了 agent-browser 之后最常用的一种。它点完保存、截图显示成功，接下来一句“去库里看下这条记录现在的值”，才算闭环。

尤其是这几种情况：金额单位（分还是元）、状态字段（`paid` 还是 `PAID`）、关联表有没有一起写、软删除的 `deleted_at` 有没有打上。截图全看不出来。

### 3. 测试数据构造：造之前先看约束和现状

直接让模型“造 20 条测试订单”很容易翻车：撞唯一索引、违反非空、日期格式被拒。所以我习惯先问：

“我要给 `orders` 造数据，先看下有哪些唯一约束和非空字段，还有现有数据的取值习惯。”

对应的是 `SHOW CREATE TABLE` 加一次采样。看完再让它写 `INSERT`，通常一次就过。

这三件事本来就要做，区别只在于以前是我切窗口、敲命令、粘结果，现在是它自己查。

不过有件事得说清：如果你只是偶尔查两条数据、自己本来就会写 SQL，直接开 `mysql` 更快。这条链路的成本是给“多轮摸索”准备的——摸 schema、反复改查询、解释结果、对字段。

---

最后给一条判据，用来确认这套配置真的生效了，而不是“看起来能查”：

- 让它执行 `UPDATE`，应该收到 `READONLY_VIOLATION`，而不是 `success: true`
- 让它 `SELECT *` 一张大表，应该看到 `truncated: true`
- 让它执行 `select database()`，返回的应该是这个仓库对应的库名，顺带还能看到用的是哪个账号——**这一步才知道它默认站在哪一边**

三条都对上，才算配完。
