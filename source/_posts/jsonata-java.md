---
title: JSON查询及转换语言- JSONata
tags:
  - json
  - jsonata
date: 2023-07-01 22:48:32
---


之前介绍过 [JSONPath](https://www.zhengw-tech.com/2022/09/11/json-path/) 的使用，但是它只能支持一些简单场景下快速从json中获取指定的值，这次我们来看一款更强大的工具 [JSONata](http://docs.jsonata.org/overview)，它是一种针对 JSON 数据的轻量级查询和转换语言，可以实现一些比较复杂的逻辑，现在我们就来看一下如何进行使用

<!-- more -->

先以一段json作为基础数据，看一下可以支持进行的操作

```json
{
  "FirstName": "Fred",
  "Surname": "Smith",
  "Age": 28,
  "Address": {
    "Street": "Hursley Park",
    "City": "Winchester",
    "Postcode": "SO21 2JN"
  },
  "Phone": [
    {
      "type": "home",
      "number": "0203 544 1234"
    },
    {
      "type": "office",
      "number": "01962 001234"
    },
    {
      "type": "office",
      "number": "01962 001235"
    },
    {
      "type": "mobile",
      "number": "077 7700 1234"
    }
  ],
  "Email": [
    {
      "type": "work",
      "address": ["fred.smith@my-work.com", "fsmith@my-work.com"]
    },
    {
      "type": "home",
      "address": ["freddy@my-social.com", "frederic.smith@very-serious.com"]
    }
  ],
  "Other": {
    "Over 18 ?": true,
    "Misc": null,
    "Alternative.Address": {
      "Street": "Brick Lane",
      "City": "London",
      "Postcode": "E1 6RF"
    }
  }
}
```

### 查询

可以直接通过属性名获取对应的数据，或者根据条件过滤取数据（相比 JSONPath 不再需要前面的`$`符号）

当前节点使用 \$ ， 上一级节点可以使用 %

| JSONata                     | 结果                                            |
| --------------------------- | ----------------------------------------------- |
| FirstName                   | "Fred"                                          |
| Address.Street              | "Hursley Park"                                  |
| Phone[0].number             | "0203 544 1234"                                 |
| Phone[-1]                   | { "type": "mobile", "number": "077 7700 1234" } |
| Phone[type='home']          | { "type": "home",  "number": "0203 544 1234" }  |
| Phone[type='office'].number | [ "01962 001234",  "01962 001235" ]             |
| Phone[type='office'].%.Age  | [28, 28]  -- (%表示上一级)                      |

### 表达式

支持字符串的拼接，数值计算，计较等逻辑计算

| JSONata                        | 结果                       | 说明                       |
| ------------------------------ | -------------------------- | -------------------------- |
| FirstName & ' ' & Surname      | "Fred Smith"               | 通过 & 连接字符串          |
| Address.(Street & ', ' & City) | "Hursley Park, Winchester" | 通过括号可以连接不同属性值 |
| 5 & 0 & true                   | "50true"                   | 可以将其他类型转换为字符串 |
| Age + 1                        | 29                         | 可以支持数值的加减乘除     |
| Age > 20                       | true                       | 可以进行比较逻辑运算       |
| "01962 001234" in Phone.number | true                       | 判断集合是否包含元素       |
| [1..5]                         | [1, 2, 3, 4, 5]            | 获取范围区间               |
| [1..5].(\$*\$)                 | [1, 4, 9, 16, 25]          | 获取范围区间并进行计算     |
| Age < 50 ? "Young" : "Old"     | "Young"                    |                            |

### 结果结构转换

可以对结果进行结构的转换

| JSONata                                       | 结果                                                         | 说明                                                         |
| --------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| Email.address                                 | ["fred.smith@my-work.com","fsmith@my-work.com","freddy@my-social.com","frederic.smith@very-serious.com"] | address为数组时，会自动打平                                  |
| Email.[address]                               | [["fred.smith@my-work.com","fsmith@my-work.com"],["freddy@my-social.com","frederic.smith@very-serious.com"]] | 这种写法会将address以数组格式返回                            |
| [Address, Other.\`Alternative.Address\`].City | ["Winchester","London"]                                      | 可以同时取多个对象的同一个属性                               |
| Phone.{type: number}                          | [{"home":"0203 544 1234"},{"office":"01962 001234"},{"office":"01962 001235"},{"mobile":"077 7700 1234"}] | 将Phone中的type作为key, number作为value转换成一个对象，最终放到一个集合中 |
| Phone{type: number}                           | {"home":"0203 544 1234", "office":["01962 001234","01962 001235"],"mobile":"077 7700 1234"} | 将Phone中的type作为key, number作为value转换成一个对象，重复的数据会转成一个集合，相当于groupby操作 |
| Phone{type: number[]}                         | {"home":["0203 544 1234"],"office":["01962 001234","01962 001235"],"mobile":["077 7700 1234"]} | 将Phone中的type作为key, number作为value转换成一个对象，value强制使用集合类型 |
| Phone{'PhoneNumber': number[]}                | {"PhoneNumber":["0203 544 1234","01962 001234","01962 001235","077 7700 1234"]} | 转换时，key和value也可以使用普通的类型                       |
| Phone.(type & ': ' & number)                  | ["home: 0203 544 1234","office: 01962 001234","office: 01962 001235","mobile: 077 7700 1234"] | 可以通过括号对一个对象中的属性进行操作                       |

### 分组与聚合

| JSONata                                       | 结果                                                         | 说明                                                      |
| --------------------------------------------- | ------------------------------------------------------------ | --------------------------------------------------------- |
| Phone{type: {'name':type, 'phone': number}}   | {"home":{"name":"home","phone":"0203 544 1234"},"office":{"name":["office","office"],"phone":["01962 001234","01962 001235"]},"mobile":{"name":"mobile","phone":"077 7700 1234"}} | 按照type分组，之后针对每个组内的元素获取name和phone(多个) |
| Phone{type: $}                                | {"home":{"type":"home","number":"0203 544 1234"},"office":[{"type":"office","number":"01962 001234"},{"type":"office","number":"01962 001235"}],"mobile":{"type":"mobile","number":"077 7700 1234"}} | 将Phone按照type分组                                       |
| Phone{type: $.{'name':type, 'phone': number}} | {"home":{"name":"home","phone":"0203 544 1234"},"office":[{"name":"office","phone":"01962 001234"},{"name":"office","phone":"01962 001235"}],"mobile":{"name":"mobile","phone":"077 7700 1234"}} | 将Phone按照type分组后，针对每个value对象进行转换          |
| Phone{type: $.(type & ': ' & number)}         | {"home":"home: 0203 544 1234","office":["office: 01962 001234","office: 01962 001235"],"mobile":"mobile: 077 7700 1234"} | 按照type分组后，针对每组内的对象进行转换计算              |

### 函数支持

JSONata内置支持了许多函数，同时也支持自定义的函数，如使用自定义函数

```json
(
  $volume := function($l, $w, $h){ $l * $w * $h };
  $volume(10, 10, 5);
)
```

将输出结果：`500`

同时还支持函数的链式调用：`value ~> $funcA ~> $funcB`，如

```json
(
   $normalize := $uppercase ~> $trim;
   $normalize("   Some   Words   ")
)
```

输出结果：`"SOME WORDS"`

全部的内置函数如下，具体用法可以参考 http://docs.jsonata.org/overview

#### 字符串函数

| $string         | $length             | $substring | $substringBefore    |
| --------------- | ------------------- | ---------- | ------------------- |
| $substringAfter | $uppercase          | $lowercase | $trim               |
| $pad            | $contains           | $split     | $join               |
| $match          | $replace            | $eval      | $base64encode       |
| $base64decode   | $encodeUrlComponent | $encodeUrl | $decodeUrlComponent |
| $decodeUrl      |                     |            |                     |

#### 数值函数

| \$number      | $floor      | $abs           | $ceil         |
| ------------- | ----------- | -------------- | ------------- |
| \$round       | $power      | $sqrt          | $random       |
| $formatNumber | $formatBase | $formatInteger | $parseInteger |

#### 聚合函数

| \$sum | \$max | \$min | \$average |
| ----- | ----- | ----- | --------- |

#### 布尔函数

| $boolean | $not | $exists |      |
| -------- | ---- | ------- | ---- |

#### 数组函数

| $count   | $append   | $sort | $reverse |
| -------- | --------- | ----- | -------- |
| $shuffle | $distinct | $zip  |          |

#### 对象函数

| $keys | $lookup | $spread | $merge  |
| ----- | ------- | ------- | ------- |
| $sift | $each   | $error  | $assert |
| $type |         |         |         |

#### 时间函数

| $now | $millis | $fromMillis | $toMillis |
| ---- | ------- | ----------- | --------- |

#### 高阶函数

| $map  | $filter | $single | $reduce |
| ----- | ------- | ------- | ------- |
| $sift |         |         |         |

