---
title: Hive解析json数据
date: 2022-11-11 22:49:55
tags: [hive, json]
---

我们平时在使用关系数据库存储数据时，在某种情况下可能会有使用字符串类的字段来存储json格式的数据，然后在代码里面进行解析处理等，这样比较方便扩展，但是在使用数据进行分析等场景下就会很不方便，这时候就需要对json进行一些解析的操作，这次主要看下如何使用Hive来解析json格式的数据

<!-- more -->

## get_json_object

Hive为我们提供了`get_json_object`函数，可以指定路径来获取json字符串中的属性值，如

```sql
-- 处理对象
select get_json_object('{"name":"zhangsan", "age":10}', '$.name')
-- 输出: zhangsan
-- 如果需要获取对象中的多个数据，可以使用json_tuple
select json_tuple('{"name":"zhangsan", "age":10}', 'name', 'age')
-- 输出: zhangsan   10

-- 处理数组
select get_json_object('["ab", "cd"]', '$.[0]')
-- 输出: ab
-- 处理对象数组
select get_json_object('[{"name":"zhangsan", "age":10},{"name":"lisi", "age":15}]', '$.[1].name')
-- 输出: lisi
```

以上这种方式基本就能满足获取指定位置数据的需求了

## explode

在实际使用时，我们可能需要将json拆开解析成一张宽表，方便后面的分析使用，这时候我们需要遍历json字符串中的全部数据，然后与其他字段值做笛卡尔积，下面我们看下这种的实现方式

这里先介绍一下 explode这个函数，这个函数的作用是什么呢？它可以将array类型的数据转换成每个元素占用一行，对于map类型的数据可以将其每个键值对转换成一行（注意：这里说的array和map不是说的字符串类型的json数据，而是指hive自己的字段类型），我们执行看一下效果

先创建对应的表结构，并插入数据

```sql
create table page_view (userid int, friends array<int>, properties map<string, string>);
insert into table page_view values (1, array(1,2,3), map('a', 'b', 'c', 'd')),  (10, array(10,20,30), map('af', 'bf', 'cg', 'dg'));
select * from page_view;
/* 输出 *
1   [1,2,3]      {"a":"b","c":"d"}
10  [10,20,30]   {"af":"bf","cg":"dg"}
*/
```

这里我们用 explode 来处理一下 friends 和 properties列看一下

```sql
-- 处理list数据，转成单列多行
select explode(friends) as f from page_view;
/** 输出 **
1
2
3
10
20
30
*/

-- 处理map数据，转成两列(k-v)多行数据
select explode(properties) as (m, n) from page_view;
/** 输出 **
a    b
c    d
af   bf
cg   dg
*/
```

这个函数只能处理对应的map和array结构，我们可以通过split函数将字符串处理后，转换成array类型；通过str_to_map将字符串转换为map类型

```sql
-- 使用split将字符串变成list结构
select split('1,2,3,4', ',');
-- 输出：["1", "2", "3", "4"]

-- 使用str_to_map将字符串变成map结构
select str_to_map('a:b,c:d');
-- 输出：{"a":"b","c":"d"}
```

对于json格式的字符串与此函数支持的数据格式不同的地方，可以使用regexp_replace等字符串函数处理后使用

```sql
select replace(replace('[12,45,67]', '[', ''), ']', '');
-- 输出：12,45,67
select substr('[12,45,67]', 2, length('[12,45,67]')-2);
-- 输出：12,45,67

```

## lateral view

explode还有一个问题就是无法与表中的其他字段同时获取，即查询到的结果只能是explode涉及到的字段，如之前的page_view表，使用explode后就无法同时获取到userid字段的值

这时候就需要 lateral view，它结合 explode结合使用，可以帮我们把数据进行组合

格式：`lateral view explode(<map/array>) <tableAlias> as <col>`

```sql
select userid, m, n from page_view lateral view explode(properties) t as m, n where userid = 10;
/* 输出 *
10    af    bf
10    cg    dg
*/
```



总结一下

1. 简单的场景，可以直接通过get_json_object配置jsonPath来获取到对应的值

2. 复杂的场景

    先通过字符串处理函数将字符串数据转换成map或list

    再使用explode将list/map转成多行数据

    结合 lateral view 与 explode 将多行数据与其他字段进行组合，获取最终结果



