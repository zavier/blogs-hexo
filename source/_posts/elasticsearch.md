---
title: Elasticsearch 入门：写给 SQL 开发者的实战指南
date: 2024-01-21 20:48:25
updated: 2026-06-20
tags: [elasticsearch, AI辅助]
---

假设你在做一个电商后台，商品表 `products` 有 100 万行。产品经理说：「用户搜『无线鼠标』，要把名字、描述里包含这些词的商品都找出来，按相关性排序。」

你写下 MySQL：

```sql
-- 慢，而且语义粗糙
SELECT * FROM products
WHERE name LIKE '%无线%' OR name LIKE '%鼠标%'
   OR description LIKE '%无线%' OR description LIKE '%鼠标%';
```

三个问题立刻冒出来：

- **慢**：`LIKE '%...%'` 走不了 B+Tree 索引，100 万行全表扫描。
- **不准**：「无线鼠标垫」也会被匹配——它并不真的是鼠标。
- **排不出相关性**：哪个排前面？MySQL 给不了你打分。

这就是 Elasticsearch（下称 **ES**）诞生的场景。它是一个**分布式的全文搜索与分析引擎**，核心能力是把文档按「词」组织起来（倒排索引），让「找出包含某些词的文档、并按相关性排序」这件事变得快且智能。

本文面向有 SQL 基础、但没接触过 ES 的后端开发者，用一个贯穿全文的电商商品表 `products`，带你从心智模型一路跑到进阶查询。

<!-- more -->

## 一、心智模型：MySQL 的概念在 ES 里叫什么

别去背新词，先和你已经懂的 SQL 对齐。

### 概念对照表

| MySQL | ES | 心智锚点 |
|---|---|---|
| Table（表） | **Index**（索引，名词） | 一类文档的集合。注意 ES 的 index 是**名词**，不是动词。 |
| Row（行） | **Document**（文档） | 一条记录 = 一个 JSON。 |
| Column（列） | **Field**（字段） | 文档里的一个 JSON key。 |
| Schema（DDL） | **Mapping** | 字段 → 类型 + 是否分词。可显式定义，也可动态推断。 |
| B+Tree 索引 | **Inverted Index**（倒排索引） | 这是核心差异，下文展开。 |
| `SELECT ... WHERE` | **Query DSL**（JSON） | 用 `match` / `term` / `bool` 等 JSON 描述查询。 |
| `GROUP BY` + 聚合函数 | **Aggregations**（聚合） | 桶聚合（bucket）+ 指标聚合（metric）。 |
| 主键 | `_id` | 文档唯一标识，可自动生成或指定。 |
| 事务 / ACID | — | **ES 没有事务**。单文档原子，跨文档不保证。 |

所以「往 ES 里写一条商品」≈「往一个 index 里插一个 JSON 文档」。index 里有什么字段、什么类型，由 mapping 决定。

### 三个关键差异：为什么 ES 能干 MySQL 干不好的活

**差异 1：写入时就把内容「切碎」**

MySQL 存 `name = "罗技无线鼠标"` 时，存的是整个字符串。ES 在写入时会先做**分词（analysis）**，把它拆成 token，再用这些 token 建**倒排索引**：

```
"罗技无线鼠标"  →  ["罗技", "无线", "鼠标"]
```

查询「鼠标」时，直接定位到「鼠标」这个词对应的文档列表，**不需要扫表**。

**差异 2：查询用 JSON 描述**

ES 没有 SQL，所有操作（建索引、查数据、删数据）都是 HTTP 请求，请求体是 JSON。先看一眼长什么样，不用记：

```
GET /products/_search
{
  "query": {
    "match": { "name": "无线鼠标" }
  }
}
```

你可以用 curl、Kibana Dev Tools，或任意语言（Java 的 RestClient、Python 的 requests）和 ES 交互。

**差异 3：ES 是「近实时」**

MySQL 写入立即可查。ES 是近实时（NRT）系统，可见性由 refresh_interval 控制，默认约 1s，但可配置或强制刷新。99% 的搜索场景这点延迟无所谓，但你要知道这个特性。

> **记三件事就够**：① ES 的 index ≈ MySQL 的表；② ES 写入时分词，查询时按倒排索引定位；③ ES 是近实时，没有事务。

## 二、起步：建索引 + 写文档

下面用一个电商商品表 `products` 贯穿全文。字段：商品名 `name`、价格 `price`、品牌 `brand`、是否有货 `in_stock`。

### 2.1 创建索引（建「表」）

MySQL 对应 `CREATE TABLE products (...)`。在 Kibana Dev Tools 或 curl 发：

```
PUT /products
{
  "mappings": {
    "properties": {
      "name": {
        "type": "text",
        "fields": {
          // name.keyword 不分词，存完整字符串，超过 256 字符的部分会被忽略
          // 这样一个字段同时具备「分词搜索」和「精确匹配/排序」两种能力
          "keyword": { "type": "keyword", "ignore_above": 256 }
        }
      },
      "price":    { "type": "float" },
      "brand":    { "type": "keyword" },
      "in_stock": { "type": "boolean" }
    }
  }
}
```

> **第一个坑：`text` vs `keyword`**。这是 mapping 设计最核心的选择：
> - `text`：**会被分词**，适合全文搜索（name、description）。
> - `keyword`：**不分词**，存完整字符串，适合精确匹配和排序（brand、category、状态枚举）。
>
> 一个字段想同时支持「按词搜索」和「整体精确匹配」，用 `fields` 配一个 `keyword` 子字段（上面的 `name.keyword`）。

### 2.2 文档 CRUD

```
// 新增（指定 ID）：PUT 会用给定 ID，ID 已存在则覆盖原数据
// MySQL ≈ INSERT INTO products (id, ...) VALUES (1, ...)
PUT /products/_doc/1
{
  "name": "罗技 MX Master 3S 无线鼠标",
  "price": 499.00,
  "brand": "罗技",
  "in_stock": true
}

// 新增（自动生成 ID）：不指定 ID 时用 POST
POST /products/_doc
{
  "name": "苹果 AirPods Pro 无线耳机",
  "price": 1799.00,
  "brand": "苹果",
  "in_stock": false
}

// 按 ID 查：MySQL ≈ SELECT * FROM products WHERE id = 1
GET /products/_doc/1

// 局部更新（只改传的字段，没传的保持原值）
POST /products/_update/1
{
  "doc": { "price": 479.00 }
}

// 删除一条文档：MySQL ≈ DELETE FROM products WHERE id = 1
DELETE /products/_doc/1

// 删除整个索引（删「表」）：MySQL ≈ DROP TABLE products
DELETE /products
```

> **更新的真相**：ES 的 update 实际上是**标记删除旧文档 + 插入新文档**（用 `_version` 字段保证并发安全），和 MySQL 的原地修改不同。这是 ES 底层存储（不可变段）决定的——下文讲乐观锁时你会看到它为什么重要。

把上面的三条商品都写进去，我们就有了一个贯穿全文的示例数据集。

### 2.3 MySQL CRUD ↔ ES REST 速查

| 操作 | MySQL | ES |
|---|---|---|
| 建表 | `CREATE TABLE t (...);` | `PUT /索引名` + mappings JSON |
| 插入 | `INSERT INTO t VALUES (...);` | `PUT /索引名/_doc/id` 或 `POST /索引名/_doc` |
| 按 ID 查 | `SELECT * FROM t WHERE id=1;` | `GET /索引名/_doc/1` |
| 更新 | `UPDATE t SET ... WHERE id=1;` | `POST /索引名/_update/1` |
| 删除行 | `DELETE FROM t WHERE id=1;` | `DELETE /索引名/_doc/1` |
| 删表 | `DROP TABLE t;` | `DELETE /索引名` |

## 三、搜索：match / term / 分词

前面都是按 `_id` 精确查，搜索的真正威力在 `_search` 端点（≈ MySQL 的 `SELECT` 关键字）。但要先用对查询，必须先搞懂**分词**。

### 3.1 用 `_analyze` 亲眼看到分词

想知道「无线鼠标」被切成了什么？用 `_analyze` API：

```
POST /_analyze
{ "text": "无线鼠标" }
```

返回（默认标准分词器）：

```json
{
  "tokens": [
    { "token": "无线", "position": 0 },
    { "token": "鼠标", "position": 1 }
  ]
}
```

「无线鼠标」被切成了两个独立的 token。**这是理解后续所有查询的钥匙**：ES 的倒排索引里存的是 token，不是原始文本。遇到任何「为什么搜不到」的疑惑，第一反应就是用 `_analyze` 看一眼到底被切成了什么。

### 3.2 `match`：全文搜索（查询词会分词）

`match` 是 ES 全文搜索的主力。它会做两件事：① 对查询词分词；② 去倒排索引找**包含任意一个词**的文档，按相关性打分排序。

```
POST /products/_search
{
  "query": {
    "match": { "name": "无线鼠标" }
  }
}
```

查询词「无线鼠标」被分成 `["无线", "鼠标"]`，结果里同时命中两个词的文档（罗技无线鼠标）得分最高，只命中一个的（雷蛇游戏鼠标只命中「鼠标」）得分较低。类比 SQL 的全文检索 `WHERE MATCH(name) AGAINST('无线鼠标')`。

需要**所有词都命中**（AND 语义），加 `operator`：

```
POST /products/_search
{
  "query": {
    "match": {
      "name": { "query": "无线 鼠标", "operator": "and" }
    }
  }
}
```

需要多个词**按顺序相邻**出现（短语匹配），用 `match_phrase`：

```
POST /products/_search
{
  "query": {
    "match_phrase": { "name": "无线鼠标" }
  }
}
```

在多个字段里搜同一个词，用 `multi_match`：

```
POST /products/_search
{
  "query": {
    "multi_match": {
      "query": "无线鼠标",
      "fields": ["name", "description"]
    }
  }
}
```

### 3.3 `term`：精确匹配（查询词不分词）

`term` 跟 `match` 的根本区别：**`term` 不对查询词分词**，直接去倒排索引找完全相等的 token。

```
POST /products/_search
{
  "query": {
    "term": { "brand": "罗技" }
  }
}
```

`brand` 是 `keyword` 类型，倒排索引里存的就是完整的「罗技」，所以 `term` 精确命中。类比 SQL 的 `WHERE brand = '罗技'`。

> **需要注意：`term` 查 `text` 字段大概率搜不到。**
>
> 试一下 `term: { "name": "无线鼠标" }`——**结果为空**。因为 `name` 是 `text`，倒排索引里只有 `["无线", "鼠标"]` 这两个 token，没有「无线鼠标」这个完整 token。
>
> 规则：**`term` 用在 `keyword` / 数字 / 日期 / 布尔这些不分词的字段上**。要搜 `text` 字段，用 `match`。

### 3.4 match vs term 对照

| | `match` | `term` |
|---|---|---|
| 查询词分词 | ✅ 会分词 | ❌ 不分词 |
| 适合字段 | `text`（全文搜索） | `keyword` / 数字 / 日期 / 布尔 |
| 是否打分 | ✅ 按相关性打分 | ❌ 不打分（要么匹配要么不匹配） |
| 类比 SQL | `MATCH(...) AGAINST(...)` | `WHERE x = '值'` |

### 3.5 其他常用精确查询（速查）

```
// terms：多值 OR 查询（brand 是罗技或苹果）
POST /products/_search
{
  "query": {
    "terms": { "brand": ["罗技", "苹果"] }
  }
}

// range：范围查询
GET /products/_search
{
  "query": {
    "range": { "price": { "gte": 300, "lte": 1000 } }
  }
}

// exists：是否存在某个字段
GET /products/_search
{
  "query": { "exists": { "field": "description" } }
}

// ids：按文档 ID 批量查
GET /products/_search
{
  "query": { "ids": { "values": ["1", "2"] } }
}
```

### 3.6 中文分词：为什么必须装 IK

用 `_analyze` 看「我是一个程序员」在标准分词器下被切成什么：每个汉字都是独立 token——`["我", "是", "一", "个", "程", "序", "员"]`，「程序员」三个字分道扬镳了。搜「程序员」会匹配不到任何文档，因为倒排索引里根本没有「程序员」这个 token。

原因：标准分词器按**空白和标点**切词，英文天然有空格，**中文没有**，所以只能逐字拆分，完全失去语义。

**解决：安装 IK 分词器**（ES 中文社区事实标准）。它能识别中文词汇边界，把「我是一个程序员」切成 `["我", "是", "一个", "程序员"]`。

IK 提供两种分词粒度，**最佳实践是索引和搜索用不同的粒度**：

| 分词器 | 粒度 | 适用 | 「中华人民共和国国歌」的结果 |
|---|---|---|---|
| `ik_max_word` | 最细，尽可能多切 | **索引时**用（提高召回率） | `["中华人民共和国", "中华人民", "中华", "华人", "人民共和国", "人民", "共和国", "共和", "国歌"]` |
| `ik_smart` | 最粗，只切最合理的 | **搜索时**用（提高准确率） | `["中华人民共和国", "国歌"]` |

在 mapping 里分别指定 `analyzer`（索引分词器）和 `search_analyzer`（搜索分词器）：

```json
"name": {
  "type": "text",
  "analyzer": "ik_max_word",
  "search_analyzer": "ik_smart"
}
```

> **小结**：match / term / range / exists 这些都是**叶子查询（基本查询）**，每个负责一种匹配方式。但现实搜索条件往往需要把多个条件组合起来——下一节的 `bool` 就是干这个的。

## 四、组合查询与聚合

现实中的搜索条件从来不是单一的：「搜索无线鼠标，价格 200–1000 之间，要有货，排除苹果品牌」。

单个 `match` 或 `term` 搞不定。**`bool` 查询的职责就是把上一节的叶子查询组装起来**——它是组合框架，里面的每个子句都是一个 `match` / `term` / `range`。

### 4.1 bool 的四根柱子

| 子句 | 语义 | 类比 SQL | 是否打分 |
|---|---|---|---|
| `must` | 必须匹配（AND） | `WHERE ... AND ...` | ✅ 贡献分数 |
| `filter` | 必须匹配（AND），但不贡献分 | `WHERE ... AND ...` | ❌ 不算分，**可缓存** |
| `should` | 或匹配（OR），有 `must`/`filter` 时是加分项 | `WHERE ... OR ...` | ✅ 命中时加分 |
| `must_not` | 排除（NOT） | `WHERE NOT ...` | ❌ 不算分 |

### 4.2 逐层搭建

**must + filter**：搜「鼠标」且有货且价格 ≤ 500

```
POST /products/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "name": "鼠标" } }
      ],
      "filter": [
        { "term": { "in_stock": true } },
        { "range": { "price": { "lte": 500 } } }
      ]
    }
  }
}
```

> **filter vs must 的关键区别**：`must` 里的 `match` 参与打分（相关性高的排前面）；
>
> `filter` 里的条件只过滤不算分，**而且 ES 可能会缓存 filter 结果，性能更好**。
>
> 规则：范围过滤、布尔标记、枚举值这类纯过滤条件，**能放 filter 的就别放 must**。

**should 作加分项**：搜「耳机」，有货的优先

```
POST /products/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "name": "耳机" } }
      ],
      "should": [
        { "term": { "in_stock": true } }
      ]
    }
  }
}
```

有货的耳机 `_score` 更高排前面，没货的不会被排除，只是排后面。

> **should 的双语义**：当 bool 里**没有** `must`/`filter` 时，`should` 起 OR 作用（匹配任一即可）；当**有** `must`/`filter` 时，`should` 只起加分作用（不匹配也不排除）。

**must_not 排除**：搜「无线」但排除苹果品牌

```
POST /products/_search
{
  "query": {
    "bool": {
      "must":     [{ "match": { "name": "无线" } }],
      "must_not": [{ "term":  { "brand": "苹果" } }]
    }
  }
}
```

### 4.3 聚合（Aggregations）：ES 的 GROUP BY

搜索是找「哪些文档」，聚合是**对文档分组统计**——相当于 SQL 的 `GROUP BY` + `COUNT / AVG / SUM`。聚合和搜索可以在同一个请求里完成。ES 把聚合分成两大类：

- **Bucket（桶）**：把文档分组，类似 GROUP BY。如按品牌分组。
- **Metric（指标）**：对组内文档做数值计算。如算平均价格。

先加几条数据让聚合更有看头（华为、索尼等），然后：

**按品牌统计商品数**（`size: 0` 表示不要文档，只要聚合结果）：

```
POST /products/_search
{
  "size": 0,
  "aggs": {
    "by_brand": {
      "terms": { "field": "brand" }
    }
  }
}
```

类比 SQL：`SELECT brand, COUNT(*) FROM products GROUP BY brand ORDER BY COUNT(*) DESC`。

**每个品牌的平均价格**（桶里嵌套指标）：

```
POST /products/_search
{
  "size": 0,
  "aggs": {
    "by_brand": {
      "terms": { "field": "brand" },
      "aggs": {
        "avg_price": { "avg": { "field": "price" } }
      }
    }
  }
}
```

类比 SQL：`SELECT brand, COUNT(*), AVG(price) FROM products GROUP BY brand`。

**一步拿全统计量**（min/max/avg/sum/count）：

```
POST /products/_search
{
  "size": 0,
  "aggs": {
    "price_stats": { "stats": { "field": "price" } }
  }
}
```

**先过滤再聚合**：只统计有货商品的品牌分布

```
POST /products/_search
{
  "query": {
    "bool": {
      "filter": [{ "term": { "in_stock": true } }]
    }
  },
  "size": 0,
  "aggs": {
    "by_brand": { "terms": { "field": "brand" } }
  }
}
```

类比 SQL：`SELECT brand, COUNT(*) FROM products WHERE in_stock = TRUE GROUP BY brand`。query 决定「对谁算」，aggs 决定「怎么算」。

## 五、进阶：批量、分页、嵌套

前面覆盖了日常 80% 的操作。下面这些是真实项目里迟早会用到、但容易踩坑的进阶能力。

### 5.1 批量写入 `_bulk`

一次 HTTP 请求做多种操作，大幅减少网络往返。每两行一组：第一行声明操作类型和目标，第二行是数据。

```
POST /products/_bulk
{"index":  {"_id": 10}}                       // index：ID 存在则覆盖
{"name": "罗技 G304", "price": 199, "brand": "罗技"}
{"create": {"_id": 11}}                       // create：ID 存在则报错
{"name": "小米鼠标垫", "price": 49, "brand": "小米"}
{"update": {"_id": 1}}                        // 局部更新
{"doc": {"price": 459}}
{"delete": {"_id": 2}}                        // 删除（没有第二行数据）
```

> `index` vs `create` 的区别只在 ID 已存在时显现：`index` 静默覆盖，`create` 抛异常。导入数据时按需选择。

### 5.2 乐观并发控制

因为 ES 的更新是「删旧插新」，如果两个客户端同时改同一条文档，后写的会覆盖先写的（丢更新）。ES 用乐观锁解决：在更新请求的 URL 后拼 `if_seq_no` 和 `if_primary_term`，值取自上次查询返回的结果。

```
PUT /products/_doc/1?if_seq_no=0&if_primary_term=1
{
  "name": "罗技 MX Master 3S 无线鼠标",
  "price": 469.00,
  "brand": "罗技",
  "in_stock": true
}
```

如果文档在此期间被别人改过（`seq_no` 已变），ES 会返回 409 冲突，让你重新读取后再改——和 Git 的版本冲突思路一致。

### 5.3 分页：三种方式怎么选

**方式一：`from` + `size`（浅分页）**

```
GET /products/_search
{
  "query": { "match_all": {} },
  "from": 0,
  "size": 10,
  "track_total_hits": true,        // 返回精确总数
  "sort": [{ "price": { "order": "desc" } }]
}
```

适合前几页的浏览。**深翻页性能差**：查 `from=10000, size=10` 时，ES 要在每个分片上取 10010 条排序后再合并丢弃 10000 条。生产环境一般限制 `from + size ≤ 10000`。

**方式二：`scroll`（快照遍历，用于全量导出）**

```
// 第一次查询，建立 1 分钟有效的快照
POST /products/_search?scroll=1m
{
  "query": { "match_all": {} },
  "size": 100
}

// 后续用返回的 _scroll_id 翻页
POST /_search/scroll
{
  "scroll": "1m",
  "scroll_id": "<上一步返回的 _scroll_id>"
}

// 用完手动释放，避免占用资源
DELETE /_search/scroll
{ "scroll_id": "<_scroll_id>" }
```

适合**后台全量导出/重建索引**，不适合用户实时分页——因为它是某个时间点的快照，期间的新增/修改不会出现。

**方式三：`search_after`（实时深分页首选）**

基于上一页最后一条的排序值作为游标，查下一页：

```
GET /products/_search
{
  "query": { "match_all": {} },
  "size": 10,
  "sort": [
    { "price": { "order": "desc" } },
    { "_id": "asc" }              // 加 _id 作 tiebreaker，保证排序唯一
  ],
  "search_after": [459, "1"]      // 上一页最后一条的 [price, _id]
}
```

**实时、无深翻页性能问题**，是用户态深分页（比如「下一页」「下一页」翻很深）的推荐方案。限制：不能跳页（只能前进/后退），且依赖一个全局唯一的排序字段。

**三种分页选型小结**：

| 方式 | 适合场景 | 深翻页 | 实时性 |
|---|---|---|---|
| `from` + `size` | 前几页浏览、结果不多 | ❌ 差 | ✅ |
| `scroll` | 全量导出、重建索引 | ✅ | ❌ 快照 |
| `search_after` | 用户实时深分页 | ✅ | ✅ |

### 5.4 只取需要的字段

默认返回整个文档，用 `_source` 指定需要的字段，减少网络传输：

```
GET /products/_search
{
  "query": { "match_all": {} },
  "_source": ["name", "price"]
}
```

### 5.5 嵌套对象 `nested`

商品里如果有一个评论数组：

```json
{
  "name": "罗技无线鼠标",
  "comments": [
    { "user": "张三", "rating": 5 },
    { "user": "李四", "rating": 2 }
  ]
}
```

用默认 mapping，`comments` 会被拍平成数组——`user` 和 `rating` 各自独立索引。于是查「user=张三 且 rating=2」会**错误命中**这条文档（张三的 5 分和李四的 2 分被当成了一对）。

解决：把 `comments` 设成 `nested` 类型，ES 会把每个数组元素当成独立的隐藏文档，保证字段之间的配对关系：

```
PUT /products
{
  "mappings": {
    "properties": {
      "comments": {
        "type": "nested",
        "properties": {
          "user":   { "type": "keyword" },
          "rating": { "type": "integer" }
        }
      }
    }
  }
}
```

查询时用 `nested` 查询，配 `inner_hits` 看是数组里的哪个元素命中了：

```
POST /products/_search
{
  "query": {
    "nested": {
      "path": "comments",
      "query": {
        "bool": {
          "must": [
            { "term": { "comments.user": "张三" } },
            { "term": { "comments.rating": 2 } }
          ]
        }
      },
      "inner_hits": {}
    }
  }
}
```

现在只有「张三本人打了 2 分」才会命中，「张三的 5 分 + 李四的 2 分」不再被错误匹配。

## 六、收尾：核心记忆点

如果只能带走几条，记住这些：

1. **ES 的 index ≈ MySQL 的表**（名词，不是加速结构）；ES 不提供跨文档事务，但提供单文档原子更新 + 乐观并发控制，不保证多文档 ACID 一致性。
2. **写入时分词，查询时按倒排索引定位**——这是 ES 比 `LIKE` 快的根本原因。
3. **`term` 查 `text` 字段是头号陷阱**：倒排索引里存的是分词后的 token，不是原文。要搜 `text` 用 `match`，要精确匹配用 `keyword` + `term`。
4. **中文必须装 IK 分词器**：索引用 `ik_max_word`（多切，提高召回），搜索用 `ik_smart`（精切，提高准确）。
5. **`match` / `term` 是叶子查询，`bool` 是组合框架**：能放 `filter` 的别放 `must`（不算分、可缓存）。
6. **分页选型**：浅翻页用 `from/size`，全量导出用 `scroll`，实时深翻页用 `search_after`。

### 什么时候不该用 ES

- 需要**强事务**（转账、库存扣减）→ 用 MySQL。
- 需要**复杂 JOIN** → 还是用 MySQL，或提前做宽表。
- 只是**按主键精确查** → Redis / MySQL 足够，ES 是杀鸡用牛刀。
- 数据量**很小**（< 10 万）→ MySQL 加好索引就够了。

> **生产常见架构**：MySQL 当主库，ES 当搜索副本，通过 Binlog / 同步工具（如 Canal、Logstash）把数据喂给 ES。MySQL 管「存储 + 事务 + 关系」，ES 管「搜索 + 聚合 + 模糊匹配」，各司其职。
