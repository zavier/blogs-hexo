---
title: 把终端变成研发工作台——pi-devops-tools 深度解析
date: 2026-08-02 22:00:00
tags: [AI辅助, 工程实践, 工具, 数据库]
---

一个半月前，我写了[一篇短文](/2026/07/26/pi-devops-tools/)介绍把 AI 编码工具改造成研发工作台的思路，并以数据库查询作为第一个验证场景。当时 `pi-devops-tools` 还只是一个概念验证——能连数据库、能执行查询、能手写 SQL 而不是让 AI 猜。

一个半月后，它已经从「能用」走到了「好用」。这篇文章是对整个扩展的完整技术解析——不只是功能介绍，更是一份设计决策的记录。

<!-- more -->

---

## 一、它现在长什么样

先看一张全景图：

> **[截图位置 1]**：Pi 终端中 `/db` 仪表盘的完整截图，包含状态栏的 `🗄 prod/shop @mysql-prod` 标识、仪表盘的操作列表（🔄 切换环境/数据库、📋 浏览数据表、💬 SQL 查询 等 9 个入口）。

输入 `/db` 回车，出现一个仪表盘。顶部显示当前连接状态——哪个环境、哪个连接、哪个数据库。下面是一排操作入口：切换数据库、浏览表、查表结构、写 SQL、看历史、查收藏、管关联、浏览关联表。

所有这些操作都在同一个终端里完成。没有 DataGrip，没有单独的 SSH 窗口，没有切来切去。

但这只是给**人**用的那一半。给 **AI** 用的那一半——`db_query`、`db_tables`、`db_mutate` 等工具——是静默注册在 Pi 的工具集里的。AI 可以直接调用它们查数据、读表结构、甚至（在人类确认后）修改数据。这意味着一次对话中，AI 可以：查数据库定位问题 → 读代码定位 bug → 写修复 → 验证数据是否正确。

---

## 二、全景架构

整个扩展 ~3000 行 TypeScript，按分层架构组织：

```
commands/          ← UI 层：/db 子命令处理器，只依赖门面接口
state/workspace.ts ← 门面层：DatabaseWorkspaceService，组合所有模块
connection/        ← 连接层：MySQL 连接池管理 + SQL 安全策略
history/           ← 持久层：查询历史 + 收藏夹 (SQLite)
relation/          ← 关系层：表关联持久化 (SQLite)
relation-graph.ts  ← 图引擎：内存双向图 + BFS 遍历
formatting/        ← 展示层：查询结果格式化（纯函数）
tools/             ← LLM 工具层：6 个 db_* 工具 + 动态加载
skills/            ← 技能层：db-explore 数据库探索工作流
types.ts           ← 类型层：共享领域类型
```

**严格的单向依赖：命令层不知道连接池的存在，图引擎不知道 MySQL 的存在。** 每一层只向下依赖，从不反向。

核心是门面 `DatabaseWorkspaceService`。它暴露 23 个公共方法，是所有 `/db` 子命令和 `db_*` 工具的唯一入口。如果要替换底层存储（比如把 SQLite 换成 JSON 文件），只需要改构造函数——命令层代码零改动。

> **[截图位置 2]**：架构图的 Mermaid 渲染版本，展示 commands → workspace → connection/history/relation-graph 的分层关系。

---

## 三、连接管理：环境 → 连接 → 数据库

### 3.1 配置即代码

数据库连接配置放在 `~/.pi/database/connections.yaml`：

```yaml
connections:
  mysql-prod:
    environment: prod
    type: mysql
    host: 10.0.1.50
    port: 3306
    username: readonly
    password: ${DB_PROD_PASSWORD}
    defaultDatabase: shop
    queryLimit: 200
  mysql-staging:
    environment: staging
    type: mysql
    host: 10.0.2.50
    port: 3306
    username: dev
    password: ${DB_STAGING_PASSWORD}
```

密码用 `${ENV_VAR}` 占位符——启动时从环境变量替换，真实密码不落盘。每个连接可以独立配置 `queryLimit`（无 LIMIT 的 SELECT 自动追加的行数上限，默认 100）。

### 3.2 交互式切换

`/db switch` 走一个三级选择器：

> **[截图位置 3]**：`/db switch` 的完整交互流程截图——环境选择（prod/staging）→ 连接选择 → 数据库选择（SHOW DATABASES 结果列表），每一步都展示 SelectList UI。

选择完成后，状态持久化到 `~/.pi/database/workspace.json`，下次启动 Pi 自动恢复。状态栏同步更新为 `🗄 prod/shop @mysql-prod`。

### 3.3 交互式添加连接

`/db add` 不需要手动编辑 YAML。交互式向导引导你完成环境 → 名称 → 主机 → 端口 → 凭据的填写：

> **[截图位置 4]**：`/db add` 的密码输入界面截图，展示星号掩码效果和 `${ENV_VAR}` 占位符提示。

密码输入做了视觉掩码（星号显示），支持 `${ENV_VAR}` 占位符。端口有范围校验（1-65535）。保存后提供可选的连接测试——输入完立即验证是否能连上。

### 3.4 跨库查询

门面的 `resolveTarget()` 是跨库能力的核心：

- 默认使用当前 workspace 选择
- 只传 `database` → 当前连接的另一个库（MySQL 同实例天然支持跨库 JOIN）
- 只传 `connectionId` → 另一个连接的默认数据库
- 都传 → 任意已配置连接上的任意库

LLM 工具（`db_query`、`db_tables` 等）通过可选的 `connection` / `database` 参数暴露这一能力。AI 不需要让用户来回 `/db switch`——它可以直接跨库查询。

---

## 四、双重入口：命令与 Tool 的分工

这是整个扩展最重要的设计原则：**确定性操作走命令，构造性操作走 Tool。**

### 4.1 给人的：`/db query`

有两种模式：

**表优先模式**：选表 → 输入 WHERE 条件 → 选择是否查询关联表。系统自动生成 `SELECT * FROM table WHERE ...`，执行器补 LIMIT。

> **[截图位置 5]**：`/db query` 的完整交互流程——模糊搜索选表（输入关键字实时过滤） → WHERE 条件输入 → "查询关联表？" 确认 → 结果展示。

**裸 SQL 模式**：打开一个多行编辑器，直接写 SQL。

> **[截图位置 6]**：裸 SQL 输入的多行编辑器截图。

为什么不让 AI 代写 SQL？因为对于一个熟悉自己数据库的工程师来说，写 `SELECT * FROM orders WHERE user_id = 123 LIMIT 20` 比跟 AI 描述「帮我查一下这个用户的订单」更快、更准、更省 token。SQL 的表达效率远高于自然语言。

### 4.2 给 AI 的：6 个 db_* 工具

| 工具 | 激活方式 | 用途 |
|------|---------|------|
| `db_query` | 常驻 | 执行只读 SQL |
| `db_tables` | 常驻 | 列出表 / 查看表结构 |
| `db_mutate` | 常驻 | INSERT/UPDATE/DELETE（人工确认门控）|
| `db_tools` | 常驻 | 按需启用懒加载工具 |
| `db_discover` | 懒加载 | 发现连接和数据库 |
| `db_list_relations` | 懒加载 | 列出已注册的表关联 |
| `db_relation` | 懒加载 | 注册/删除表关联 |

**但 `/db query` 的执行结果，AI 是看得到的。** 查询结果通过 `pi.sendMessage({ display: false })` 以静默消息注入 LLM 上下文。这意味着你可以自己写 SQL 把数据查出来，然后直接基于结果和 AI 对话——数据你查，推理 AI 做，各司其职。

这种静默上下文注入也用在会话启动时：Pi 启动后，扩展自动发送一条 `Current database: shop (connection: mysql-prod, environment: prod)` 的消息给 LLM。AI 不需要「猜」当前连的是哪个库，也不需要先失败一次再发现。

### 4.3 查询结果的双受众展示

查询结果需要同时服务两个受众：

- **TUI（给人看）**：自适应终端宽度，装饰线、颜色编码、展开/折叠交互
- **LLM（给 AI 看）**：紧凑 Markdown，无填充，截断标记 `…[+N]` 让 AI 知道被截了多少

两个版本由 `formatting/result-document.ts` 的同一个函数装配——消费方只负责映射颜色和追加交互提示。保证「TUI 展示的」和「AI 读到的」是同一条数据的两种视图，不会出现信息不一致。

> **[截图位置 7]**：同一条查询结果在 TUI（左）和 LLM 上下文（右）的对比截图。

---

## 五、动态工具加载：为什么不全激活

Pi 的工具集会进 system prompt。每多一个工具，就多一份上下文消耗。7 个数据库工具如果全激活，会增加不少 token 开销。

但并不是所有场景都需要全部工具。日常查询只需要 `db_query` + `db_tables`。只有当你需要探索新数据库、发现连接、管理关联关系时，才需要另外三个。

所以设计了**常驻集** + **懒加载**的分层：

```
常驻（4 个）：db_query, db_tables, db_mutate, db_tools
懒加载（3 个）：db_discover, db_list_relations, db_relation
```

`db_tools` 是一个特殊的 loader 工具——它本身不做任何数据库操作，只负责按需启用懒加载工具。AI 调用 `db_tools` 时说一句「我需要查关系」，关键词匹配到 `db_list_relations` 和 `db_relation`，它们从下一轮对话开始可用。

关键词匹配是纯函数，按英文词干匹配——比如 `"relationship"` 匹配到 `db_list_relations`，`"foreign key"` 匹配到 `db_discover`。空查询匹配全部，当 AI 不确定需要什么时做兜底。

每次会话启动时，工具集重置为常驻集——激活工具集不持久化，不跨会话污染。

---

## 六、安全：不可绕过的三道防线

### 6.1 只读白名单

所有查询必须匹配 `/^(SELECT|SHOW|DESCRIBE|EXPLAIN)\b/i`。`\b` 很重要——它拒绝 `SELECTOR` 之类的词。这个检查不在命令层，而在执行引擎 `DatabaseConnectionManager.executeQuery()` 的唯一入口处。**不管查询从 `/db query`、`db_query` 工具还是任何未来入口发起，它都经过同一道门。**

### 6.2 LIMIT 自动注入

无 LIMIT 的 SELECT 自动追加 `LIMIT 100`（可按连接配置）。几个边界情况处理：

- `SELECT ... LIMIT n` → 不追加（已有）
- `SELECT ... FOR UPDATE` → 不追加（锁定读后面不能跟 LIMIT）
- `SELECT ... (subquery) LIMIT n` → 不追加（外层已有）
- 追加后的最终 SQL 原样展示给用户——自动加上的 LIMIT 是可感知的，不是隐藏行为

### 6.3 db_mutate：AI 提议，人类批准

`db_mutate` 是唯一的写路径。设计原则是**仪式在 facade 里，不在 tool 里**——不管谁调用，都经过同一套校验+确认流程：

```
LLM 调用 db_mutate({ sql, connection?, database? })
  │
  ▼
executeMutationWithApproval(sql, opts, confirm)
  ├─ 1. prepareMutationQuery(sql)     ← DML 校验，DDL 直接抛错
  ├─ 2. resolveTarget(opts)           ← 目标解析
  ├─ 3. confirm({ 校验结果 + 目标 })  ← 弹窗等待人类确认
  │     ├─ Enter → 确认执行
  │     └─ Esc   → 返回 rejected（非错误）
  └─ 4. executeMutation()             ← 执行，返回 affectedRows
```

确认对话框按操作类型颜色编码：INSERT 绿色、UPDATE 黄色、DELETE 红色、REPLACE 橙色。无 WHERE 的 UPDATE/DELETE 会显示**醒目警告**，但不阻止执行——那是人类的判断。

> **[截图位置 8]**：`db_mutate` 确认对话框截图，展示 UPDATE 的黄色框 + SQL 显示 + 警告信息 + Enter/Esc 提示。

DDL（CREATE/DROP/ALTER/TRUNCATE）硬性拒绝，不弹窗，不给确认机会。这是明确的边界——这个工具是「研发工作台」的数据操作入口，不是数据库管理工具。

每次调用独立确认，不存在「缓存确认」「跳过后不再询问」等机制。安全不能靠 AI 自觉。

---

## 七、关联查询：让表关系在查询时生效

### 7.1 问题：物理外键的消失

多数业务系统已经不设物理外键了——性能考虑、分库分表、历史债务。但逻辑关系仍在：`orders.user_id` 指向 `users.id`，`order_items.order_id` 指向 `orders.id`。

这就引出一个常见场景：查一张表，往往需要同时看几张关联表的数据。手写 JOIN 把数据拉平成一张宽表，读起来不直观；查完一张再查另一张，又要反复写 SQL。

### 7.2 方案：双向图 + BFS

关系图引擎的核心数据结构是内存中的**双向图**：

```
注册：orders.user_id → users.id (MANY_TO_ONE)
效果：
  forward["shop.orders.user_id"] → { targets: [users.id] }     ← 前向
  forward["shop.users.id"]       → { targets: [orders.user_id] } ← 反向（自动创建）
```

每条注册的关系自动写入正反两个方向。这意味着 BFS 可以从任意表出发，沿任意方向遍历——从用户查订单、从订单查用户均可。

查询时选择「查询关联表」，BFS 自动沿注册的关系展开：

1. depth 0：执行主表查询
2. 取主表结果中的外键值，`SELECT * FROM ref_table WHERE ref_col IN (val1, val2, ...) LIMIT 10`
3. 同深度的多个方向 `Promise.allSettled` 并行执行
4. `visited` 集合防止环路，`null` 值自动跳过

主表和关联表**分开展示**，关联路径一目了然，比手写 JOIN 直观得多：

> **[截图位置 9]**：带关联表的查询结果截图——主表 orders 的表格 + 分隔线 + `📎 关联表 users — 2 行` + 关联路径 + users 表格。

### 7.3 关联表的三种来源

**手动注册**（`/db relations add`）：选源表 → 源列 → 关联表 → 关联列 → 关系类型（MANY_TO_ONE / ONE_TO_MANY / ONE_TO_ONE / MANY_TO_MANY）。支持额外的关联条件（如 `type=1`）。

> **[截图位置 10]**：`/db relations add` 的完整交互流程截图。

**FK 自动发现**（`/db relations discover`）：查询 `information_schema.KEY_COLUMN_USAGE`，自动导入物理外键。幂等——重复执行不会创建重复关系。

**AI 分析**：`/db relations discover` 的最后一步可以选择「🤖 AI 分析」。扩展把当前数据库所有表的列结构发给 LLM，让 LLM 根据列名约定推断隐含关系（比如所有叫 `user_id` 的列大概率指向 `users.id`），然后调用 `db_relation` 工具自动注册。30 张以内小库秒级完成分析。

### 7.4 关联表浏览器

关联查询的结果可以在一个独立的 overlay 悬浮层中浏览：

> **[截图位置 11]**：关联表浏览器 overlay 截图——顶部 `📎 关联表浏览器 — shop（3 个关联表）`，中间 `▶ users（2 行） products（15 行） orders（8 行）` 的 tab 切换行，下方是当前表的完整表格，底部 `←→ 切换 · ↑↓ 滚动 · Esc 关闭`。

←/→ 切换关联表，↑/↓ 滚动，PgUp/PgDn 翻页。数据来自最近一次关联查询的会话缓存，不需要重新查数据库。

---

## 八、结果展示：终端表格的工程化

在终端里展示 SQL 查询结果，看似简单，实则有不少细节。

### 8.1 自适应布局

表太宽？列太多？行太多？`formatTableDisplay` 根据数据形状自动选择布局：

- **8 列以内、终端够宽** → 横向 Markdown 表格，列宽自适应打包（注水式算法：优先压缩最宽的列）
- **宽但行少（≤10 行）**→ 行列转置（列名变行头，每行数据竖着排）
- **又宽又多** → 纵向键值对（`col_name │ value`，每行一条分隔线）

### 8.2 列折叠

全 NULL 的列自动隐藏。所有行取值相同的列也隐藏（比如 `status = 'active'` 出现在每一行）。底部给一句摘要：

```
ⓘ 已隐藏 3 列（全为 NULL）：deleted_at, updated_by, remark
  已隐藏 1 列（所有行取值相同）：status=active
```

这在排查问题时特别有用——一眼就能看到**有变化的列**，不被噪音干扰。

### 8.3 TUI vs LLM：两套格式，一套数据

| 维度 | TUI（给人） | LLM（给 AI） |
|------|-----------|-------------|
| 格式 | 填充对齐 + 装饰线 | 紧凑无填充 |
| 截断 | 可视区内显示前 20 行 | 全部行，200 字符/格 |
| 颜色 | 主题色 accent/dim/muted | 纯文本 |
| 交互 | 展开/折叠、关联浏览器 | 截断标记 `…[+N]` |

核心设计：`result-document.ts` 只有一个 `renderQueryDocument()` 函数，`audience` 参数决定输出格式。TUI 和 LLM 两个消费方**不会**出现信息不一致——它们从同一份数据装配。

> **[截图位置 12]**：展开模式下的完整结果截图——所有行的纵向键值对完整展示，对比折叠态的「前 20 行 + 展开提示」。

---

## 九、查询历史与收藏

### 9.1 查询历史

每次 `/db query` 或 `db_query` 执行后，SQL 自动存入本地 SQLite。`/db history [关键词]` 打开交互式选择器：

> **[截图位置 13]**：查询历史选择器截图——`📜 查询历史 — 23 条 · ↑↓ 选择 Enter 选中 Esc 取消`，列表每行显示序号、时间、SQL 摘要、行数、耗时。

选中一条后可以：重跑、编辑后跑、收藏、删除。支持关键词搜索历史。

### 9.2 收藏的 SQL 模板

`/db favorite add` 保存常用 SQL。支持多行 SQL 模板编辑器。收藏可以跨会话使用。

> **[截图位置 14]**：收藏列表截图——`⭐ 收藏查询（shop + 全局）— 5 条`，每行显示名称、数据库标签、SQL 摘要。

选中后可以：直接执行、编辑后执行、删除。

这两个功能都很简单，但它们省掉了「我上次那条 SQL 写的是什么来着」的回忆成本。在排查问题的紧张节奏中，这种便利不是锦上添花——是必需品。

---

## 十、db-explore 技能：AI 自主探索数据库

除了单个工具，扩展还注册了一个 `db-explore` skill。Skill 是 Pi 中的一种扩展机制——它会作为系统指令注入 LLM 的上下文，指导 AI 如何在特定场景下使用工具。

`db-explore` 定义了一个系统化的 6 阶段数据库探索工作流：

| 阶段 | 工具调用 | 耗时 | 目标 |
|------|---------|------|------|
| 快速路径 | 1-3 次 | <5s | 用户说了表名/列名 → 直接查 |
| 1 — 定位 | 1-2 次 | <3s | 确认目标连接和数据库 |
| 2 — 扫描 | 1 次 | <2s | 获取表目录，识别核心实体表 |
| 3 — 探查 | 3-5 次 | 5-10s | 查看核心表的列和索引 |
| 4 — 采样 | 3-5 次 | 5-10s | SELECT * LIMIT 5 看真实数据 |
| 5 — 关联 | 3-12 次 | 10-30s | 发现和注册表关联 |
| 6 — 报告 | 0 次 | — | 结构化汇总 |

而且不是死板的 6 阶段——它根据用户目标自适应：

- **查数据**（"查一下 users 表"）→ 走快速路径，1-3 次工具调用搞定
- **分析报表** → 优先事实表，跳过小维度表
- **CRUD 开发** → 优先实体表和外键依赖
- **迁移审计** → 标记疑似废弃表（`_old`、`_bak`），检查软删除模式
- **性能排查** → 检查索引覆盖，用 EXPLAIN 分析慢查询

Skill 还定义了一组反模式要避免：不全量 dump schema（只看核心表）、不盲目 JOIN（先验证列类型和外键存在）、不注册未经确认的关系。

这意味着当用户说「帮我看看这个数据库的结构」时，AI 不会傻傻地把 200 张表的列定义全 dump 出来——它会按照 6 阶段方法系统地、高效地建立理解，然后给出结构化的报告。

---

## 十一、工程细节

### 11.1 扩展开关：不重启也能开关

`/db on` / `/db off` 控制扩展启用状态。关闭后：

- 所有 LLM 工具、skills、renderers 注销——上下文零开销
- `/db` 命令精简为单入口：只响应 `/db on` 重新启用
- 不需要重启 Pi——`ctx.reload()` 重新执行扩展工厂

开关状态存 `~/.pi/database/extension.json`，容错策略是**默认启用**——文件缺失、JSON 损坏一律视为启用，只有显式 `{ "enabled": false }` 才禁用。

### 11.2 测试：真实替身，不 mock

100+ 个单元测试，策略是用真实替身（`:memory:` SQLite、临时目录、stub 函数），不用 mock 框架：

- `StateStore` 接受可选 `baseDir`——测试注入 `tmpdir()`，生产用 `~/.pi/database`
- Store 类接受 `Database` 句柄——测试传 `new Database(":memory:")`
- `RelationGraph.bfsQuery()` 接受 `QueryFn`——测试传 stub 函数，按表名路由返回值
- `DatabaseConnectionManager` 接受 `PoolFactory`——测试传 fake pool，覆盖连接检出和 SQL 执行

好处：测试运行快（无网络 IO）、可并行、可离线、不依赖真实 MySQL。

### 11.3 代码质量

```
tsc --noEmit     ← TypeScript strict mode
vitest run       ← 100+ 单元测试
oxlint           ← Rust linter
oxfmt --check    ← Rust formatter
```

CI 在每次 push 时自动运行全部四项。

---

## 十二、设计决策回顾

这篇文章一路写下来，有几个反复出现的主题值得单独提炼：

### 为什么不做 Schema 缓存？

早期版本有本地 JSON 缓存（`/db refresh-schema` 刷新），后来整体移除，全部实时查询 `information_schema`。理由：

- **实时查询成本很低**——information_schema 是毫秒级本地元数据读取
- **缓存永不过时是不可能的**——自动过期要跟踪 DDL，手动刷新把负担推给用户，AI 拿到陈旧数据无法自愈
- **少一层少一类 bug**——缓存读写、目录管理、刷新命令全部消失，代码路径只剩一条

如果未来某场景证明实时查询是瓶颈，再以「有测量的需求」为前提重新引入。

### 为什么是门面模式？

一个 `/db query` 的执行路径涉及 5 个模块协作。如果命令层直接调用这些模块，每个命令需要理解全部 5 个接口，协作逻辑分散在多处，修改内部架构要改所有命令。

门面把「如何协作」封装在一个地方，命令只关心「做什么」。

### 为什么用双向图而不是单纯的外键？

物理外键只覆盖已声明的约束。实际项目大量关系靠列名约定隐含（`user_id`、`dept_no`）。双向图允许手动注册任意关系，且 BFS 可沿任意方向遍历。

### 为什么是命令而不是 Tool？

这是一个真正影响使用体验的选择。不是所有能力都适合交给 AI 自主调用——SQL 的表达效率远高于自然语言，一个熟悉自己数据库的工程师写 SQL 比跟 AI 描述更快、更准、更省 token。但 AI 看得到人的查询结果——数据你查，推理 AI 做。各司其职。

---

## 十三、写在最后

这个扩展现在 v0.8.1，还不算 1.0。但它的核心能力已经稳定——连接管理、只读查询、变更确认、关联查询、历史收藏、AI 探索。日常开发中的数据库交互，基本不需要切出终端了。

更重要的是，它验证了一件事：**Pi 的 extension 机制给了你把 AI 编码工具改造成研发工作台的自由度。** 你可以自己决定 AI 能触碰什么、人保留什么、哪些操作需要人类确认、哪些工具按需加载。这不是一个「功能更多的 AI」，而是一个你可以自定义工具集的 AI 终端。

下一步的计划：

| 方向 | 说明 |
|------|------|
| SSH 日志查询 | `/log tail <host> <file>`，AI 的 bash 自动走 ProxyJump |
| 测试数据构造 | AI 读表结构 → 生成 INSERT → 人工确认执行 |
| 接口 Mock | 本地起 mock server，描述接口即用 |
| PostgreSQL 支持 | 当前只有 MySQL，Pg 是同构的扩展 |

如果你也在用 AI 编码工具，而且总觉得有些地方「不连贯」——不是你的问题。是工具的设计假设和你的工作流不匹配。Pi 给了你一个机会，让你自己来调这个匹配度。

`devops-tools` 开源在 [GitHub](https://github.com/zavier/pi-devops-tools)，欢迎试用和反馈。
