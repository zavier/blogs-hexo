---
title: 基于Trae开发自动表关联查询工具
date: 2025-02-02 15:01:39
tags: [工具, trae]
---

对于复杂的一些业务，会涉及很多张表，其间有各种各样的关联关系，在开发&测试过程中，随时需要查看这些表中的数据状态，这种情况下需要我们写一些关联查询的SQL或者多条SQL执行来查看结果，个人感觉用起来还是不太方便，所以想开发一个关联表自动进行查询的工具

后端基于spring boot自行开发；前端部分使用了Trae，让大模型来进行的开发～

[后端项目代码](https://github.com/zavier/table-relation)、 [前端项目代码](https://github.com/zavier/table-relation-front)、 [体验地址](https://zhengw-tech.com/table/index.html)

<!-- more -->

服务主要还是本地部署个人使用，为了简化，本地数据库使用了sqlite的文件形式存储，同时采用了将前端项目打包结果复制到后端项目中同步部署，所以没有其他任务外部依赖

在后端项目中启动后，直接访问 `http://localhost:8080` 即可使用，或者打包后通过 `java -jar xxx.jar` 执行

注意：

1. 需要 jdk 版本大于等于 21
1. 只支持MySQL数据库
1. 没有做鉴权及SQL注入等处理，所以只建议本地安装个人使用

下面进行一下对应功能介绍

## 数据源管理

用来管理数据库（MySQL）的连接（需要服务所在的机器可以连接到数据库）

![image-20250202150929799](/images/table-relation/data-source-1.png)

## 表字段关系管理

这里主要进行字段关系的维护，如果使用了外键的话，会自动进行同步，支持跨库关联

![image-20250202151636888](/images/table-relation/table-relation.png)

比如员工表(employees)的部门编码字段(dept_no)对应了，部门表(departments)的(dept_no)字段，那么我们可以这样配置（主表可以理解为包含类似外键的表）

其中的关联条件部分，使用场景为一张表根据条件关联不同的表

假设有多张表，它们的操作日志都记录在了一个叫做操作日志的表里面，同时操作日志表有一个类型字段来区分对应的表是哪个，那么我们可以在关联条件中输入对应的条件即可，如（type=1），如果没有这种场景就可以不填写

![新增字段关系](/images/table-relation/add-table-relation.png)

## ER图查看

在创建好数据源以及维护好字段关系后，我们可以通过查看ER图来确认一下配置是否正确，并且也可以让新人快速熟悉表间关系

需要输入一下对应的db和table即可，会查找所有关联的表进行展示，并同时展示关联的字段关系，支持跨库关联

![image-20250221214249445](/images/table-relation/er-diagram.png)

## 数据查询

最后就是数据的查询，选择db和表后，需要输入对应的查询条件，这时会查询对应的数据，同时会将关联的表和数据同时在下方进行展示（目前限制了单表数据最多10条）

目前是会根据选择的表向外查询关联表，是广度优先，并且对于相同的表只会查询一次，所以选择的表不同，结果可能会有所差异

同时如果我们的表有逻辑删除相关的字段，也可以在配置文件中添加对应的条件，这样在查询的时候会自动添加这个条件，过滤掉逻辑删除的数据

```properties
# logic no-delete condition
logic.no.delete.condition=is_deleted=0
```

具体查询页面如下

其中会展示查询的表对应的数据，以及全部能查询到的关联的表数据，可以很方便的切换查看数据

![image-20250221214100985](/images/table-relation/data-query.png)



## AI赋能

### 自动识别表关系

在没有设置外键的情况下，自己维护表字段的关系还是一件比较麻烦的事情，这时候可以让大模型帮我们处理一下

在每次新增数据源时，我们可以获取其中的全部表信息，传递给大模型帮我们进行分析，生成对应关系的数据记录下来

可以在项目的application.properties文件中进行开启/关闭配置，目前还不是很稳定～～

```properties
# llm analyze table column usage
analyze.column.usage.auto=true/false
```



### 自然语言生成SQL

在有个表关系的ER图后，我们可以比较容易的让大模型来帮助我们根据自然语言来生成查询SQL了

将memaid格式的ER图文本和自然语言提供给大模型即可，代码已放在[github](https://github.com/zavier/table-relation/commit/3017c387f4ef2b01aa7eadcdd0f55806eff19f06)，具体效果如下

![image-20250215234632834](/images/table-relation/sql-generate-01.png)

生成结果后，可以直接进行执行

![image-20250215234822560](/images/table-relation/sql-generate-02.png)
