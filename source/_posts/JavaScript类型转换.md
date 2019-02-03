---
title: JavaScript类型转换
date: 2019-02-03 08:57:33
tags: javascript
---



ECMAScript中有五种基本数据类型：`Undefined`, `Null`, ` Boolean`, `Number`, `String`，一种复杂数据类型：`Object`



### 数据类型检测方法

`typeof` 函数，例： 

```javascript
var s = xx;
var res = typeof(s);
```

| 返回结果=typeof(res)        | 意义           |
| --------------------------- | -------------- |
| typeof(res) === “undefined” | 值未定义       |
| typeof(res) === "boolean"   | 值为布尔类型   |
| typeof(res) === "string"    | 值是字符串     |
| typeof(res) === "number"    | 值为数值       |
| typeof(res) === "object"    | 值是对象或null |
| typeof(res) === "function"  | 值是函数       |

<!-- more -->

### Boolean类型转换

```javascript
# Boolean
Boolean(true) == true
Boolean(false) == false

# String
Boolean("") == false
Boolean("ad") == true

# Number
Boolean(0) == false
Boolean(NaN) == false
Boolean(10) == true

# Object
Boolean({}) == ture
Boolean(null) = false

# Undefined
Boolean(undefined) == false
```



### 数值类型转换

`Number()`, `parseInt()` 和 `parseFloat()`，第一个函数可以用于任何数量类型，而另外两个函数则专门用于把字符串转换成数值

| 参数      | Number()                         | parseInt();  parseInt("xx", [8\|10\|16])      |
| --------- | -------------------------------- | --------------------------------------------- |
| true      | Number(ture) === 1               | parseInt(true) === NaN(isNaN)                 |
| false     | Number(false) === 0              | parseInt(false) === NaN(isNaN)                |
| 13        | Number(13) === 13                | parseInt(13) === 13                           |
| null      | Number(null) === 0               | parseInt(null) === NaN(isNaN)                 |
| undefined | Number(undefined) === NaN(isNaN) | parseInt(undefined) === NaN(isNaN)            |
| "234"     | Number("234") === 234            | parseInt("234") === 234                       |
| "1.1"     | Number("1.1") === 1.1            | parseInt("1.1") === 1                         |
| "070"     | Number("070") === 70             | parseInt("070") = 70; parseInt("070", 8) = 56 |
| "0xf"     | Number("0xf") === 15             | parseInt("0xf") === 15                        |
| ""        | Number("") === 0                 | parseInt("") === NaN(isNaN)                   |
| "123abc"  | Number("123abc") === NaN(isNaN)  | parseInt("123abc") === 123                    |

Number()函数，如果参数是对象，则调用对象的valueOf()方法，然后依照前面的规则进行转换，如果结果是NaN，则调用对象的 toString()方法，然后依照前面的规则进行转换



### 字符串类型转换

```javascript
String(10) === "10"
String(true) === "true"
String(null) === "null"
String(undefined) === "undefined"
```

