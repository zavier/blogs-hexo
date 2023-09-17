---
title: JSONPath简介
date: 2022-09-11 22:43:19
tags: [java, json, jsonpath]
---

JSON目前是使用的比较多的一种数据格式，前后端的交互就是都是使用JSON格式，后端存储的时候就算使用MySQL，有时候也会存在使用字符串等类型字段存储JSON数据（现在MySQL也支持了JSON类型字段并提供相关的语法）

JSONPath比较适合使用在一些结构不确定，或者比较灵活的场景下，从json中获取想要的数据

1. 有一些变更频繁的扩展类的非核心数据，可以直接当做一个json字符串进行存储，在获取的数据可以通过配置的JsonPath来从其中进行取值使用
2. 在做类似网关等场景下，可以通过配置JsonPath完成数据的转换，当然如果转换逻辑特别复杂时可能还是模版引擎更合适一些

<!-- more -->

## 使用

我们先看下JSONPath的使用，这里使用的是[https://github.com/json-path/JsonPath](https://github.com/json-path/JsonPath)，其README中已经提供了相关的介绍和使用示例，这里再简单介绍下，我们这里直接使用其中的示例数据

```json
{
  "store": {
    "book": [
      {
        "category": "reference",
        "author": "Nigel Rees",
        "title": "Sayings of the Century",
        "price": 8.95
      },
      {
        "category": "fiction",
        "author": "Evelyn Waugh",
        "title": "Sword of Honour",
        "price": 12.99
      },
      {
        "category": "fiction",
        "author": "Herman Melville",
        "title": "Moby Dick",
        "isbn": "0-553-21311-3",
        "price": 8.99
      },
      {
        "category": "fiction",
        "author": "J. R. R. Tolkien",
        "title": "The Lord of the Rings",
        "isbn": "0-395-19395-8",
        "price": 22.99
      }
    ],
    "bicycle": {
      "color": "red",
      "price": 19.95
    }
  },
  "expensive": 10
}
```

1. JSONPath的表达式都是以 `$` 开始，表示根节点

2. 属性值获取：子节点可以使用 `.<name>` 来进行表示，如: `$.store.bicycle.color`  或者 `$['store']['bicycle']['color']`可以获取其中的color值

3. 获取多个属性值：JSONPath表达式**最后一级**子节点可以同时获取多个值，如 `$['store']['bicycle']['color', 'price']`
4. 数组数据获取：可以根据索引获取指定位置元素，如： `$.store.book[0,1]` 或者 `$.store.book[:2]` 或者 `$.store.book[-1]`
5. 可以使用通配符`*`进行匹配，如：`$.store.book[*]` 或者 `$.store.bicycle.*`
6. 深度查找可以使用`..<name>`来对属性进行查找，而不管它的具体位置，如：`$..price`
7. 属性/数组过滤可以使用`[?(<expression>)]`，其中的表达式需要能解析为boolean值，如：`$.store.bicycle[?(@.color=='red')]` 或者 `$.store.book[?(@.price < 10)]`
8. 函数使用：可以使用lengh()等函数，如：`$.store.book.length()` 、`$.numbers.sum()`

相关API用法如下：

```java
final JsonPath compile = JsonPath.compile("$.store.book[0].author");
String json = "...";
final String author = compile.read(json);

// 或者如果不重复使用的话，可以直接写成一步
List<String> authors = JsonPath.read(json, "$.store.book[*].author");

// 函数使用（需要注意函数能作用的数据类型，如 min(), max(), sum()等只能作用于数值数组）
String json = "{\"numbers\":[1,3,4,7,-1]}";
final Object read = JsonPath.read(json, "$.numbers.sum()"); // 输出：14.0
```

除此之外，JsonPath还提供了一些额外的配置项，以仓库中的json为例子

```json
[
   {
      "name" : "john",
      "gender" : "male"
   },
   {
      "name" : "ben"
   }
]
```

**DEFAULT_PATH_LEAF_TO_NULL** 

叶子节点找不到时默认为null： 正常情况下通过Path找不到数据值，JsonPath会抛出异常（使用了通配符如[*]等除外，这种找不到路径是会返回空集合），增加此配置后在叶子结点找不到数据时会返回null 而不是异常（仅限叶子结点，中间节点不存在时仍然会抛出异常）

```java
Configuration configuration =    Configuration.builder().options(Option.DEFAULT_PATH_LEAF_TO_NULL).build();
Object data = JsonPath.using(configuration).parse(json).read("$[1]['gender']");
// data == null
```

**ALWAYS_RETURN_LIST**

不管JsonPath获取的结果是单个值还是集合，都会包装成集合返回

```java
Configuration configuration = Configuration.builder().options(Option.DEFAULT_PATH_LEAF_TO_NULL, Option.ALWAYS_RETURN_LIST).build();
Object data = JsonPath.using(configuration).parse(json).read("$[*]['gender']");
// data == ["male",null]
```

**SUPPRESS_EXCEPTIONS**

当处理发生异常时，如果配置了 ALWAYS_RETURN_LIST，则返回空集合，否则返回null

```java
Configuration configuration = Configuration.builder().options(Option.ALWAYS_RETURN_LIST, Option.SUPPRESS_EXCEPTIONS).build();
Object data = JsonPath.using(configuration).parse(json).read("$[0]['abc']['def']");
// data = []
```

**REQUIRE_PROPERTIES**

路径中属性不存在时，会抛出异常，因为本身路径不存在就会抛出异常，所以这个配置主要体现在配置通配符的场景下，且如果同时配置了 SUPPRESS_EXCEPTIONS， 则 SUPPRESS_EXCEPTIONS 优先（不会抛出异常）

```java
Configuration configuration = Configuration.builder().options(Option.ALWAYS_RETURN_LIST).build();
Object data = JsonPath.using(configuration).parse(json).read("$[*]['gender']");
// 抛出异常
```

### 值替换

以上主要是读取的操作，同时它还支持对数据进行修改，调用对应的set方法即可

```java
String newJson = JsonPath.parse(json).set("$['store']['book'][0]['author']", "Paul").jsonString();
```

### 组合jsonPath

组合json与JsonPath使用，在做一些数据转换时，如果使用单个jsonPath无法满足，我们可以同时结合json使用

```json
{
    "key1": "jsonpath1",
    "key2": "jsonpath2"
}
```

这样我们可以通过遍历这个json, 将对应jsonPath位置的值替换成具体获取到的值，即可获取到最终的结果数据



## 实现简介

使用方法基本如下，下面大概说一下它的实现

1. 先将JSONPath表达式进行编译解析为一系列的token，并按顺序使用链表连接起来
2. 解析json时，依次调用每个token的解析方法，将自己所在层解析出来后，将解析结果交给之后的token继续进行处理，像剥洋葱一样层层解析
3. 解析过程中使用配置的json工具类来对数据进行查询操纵
4. 到最后一个节点后，使用 EvaluationContent对结果进行收集结束

其中包含的token有如下几类

1. RootPathToken，根节点，支持表达式：`$`
2. PropertyPathToken，支持表达式: `.<name> 或 ['<name1>' (,'<name2>')] `
3. ArrayIndexToken，支持表达式：`[<number> (, <number>)]`
4. ArraySliceToken，支持表达式：`[start:end]`
5. WildcardPathToken，支持表达式： `* 或者 [*]`
6. PredicatePathToken，支持表达式：`[?(<expresion>)]`
7. ScanPathToken，支持表达式：`..<name>`
8. FunctionPathToken，用于支持内置的函数

这样就可以将对应的表达式映射成一系列的token，然后依次解析

```java
// PathCompiler.java
private boolean readNextToken(PathTokenAppender appender) {
    char c = path.currentChar();
    switch (c) {
        case OPEN_SQUARE_BRACKET:
            if (!readBracketPropertyToken(appender) && !readArrayToken(appender) && !readWildCardToken(appender)
                && !readFilterToken(appender) && !readPlaceholderToken(appender)) {
                fail("Could not parse token starting at position " + path.position() + ". Expected ?, ', 0-9, * ");
            }
            return true;
        case PERIOD:
            if (!readDotToken(appender)) {
                fail("Could not parse token starting at position " + path.position());
            }
            return true;
        case WILDCARD:
            if (!readWildCardToken(appender)) {
                fail("Could not parse token starting at position " + path.position());
            }
            return true;
        default:
            if (!readPropertyOrFunctionToken(appender)) {
                fail("Could not parse token starting at position " + path.position());
            }
            return true;
    }
}
```

我们以获取属性使用的PropertyPathToken来看下解析过程

```java
class PropertyPathToken extends PathToken {
    // 这里是解析JSONPath处理的属性名称
    private final List<String> properties;
    // 这里是解析JSONPath处理的属性包含符号，单引号或者双引号
    private final String stringDelimiter;
    
    public void evaluate(String currentPath, PathRef parent, Object model, EvaluationContextImpl ctx) {
        // 使用提供的json工具类判断json是否能转换成一个map
        if (!ctx.jsonProvider().isMap(model)) {
            // 不能转成map则跳过或者抛出异常
            // 为了看起来简洁一点，这里代码进行了删除，正常json对象解析都是map
        }
    
        // 一般会进入到这里，解析一个或多个属性
        if (singlePropertyCase() || multiPropertyMergeCase()) {
            // 这里调用PathToken中提供的方法
            handleObjectProperty(currentPath, model, ctx, properties);
            return;
        }
    
        assert multiPropertyIterationCase();
        final List<String> currentlyHandledProperty = new ArrayList<String>(1);
        currentlyHandledProperty.add(null);
        for (final String property : properties) {
            currentlyHandledProperty.set(0, property);
            handleObjectProperty(currentPath, model, ctx, currentlyHandledProperty);
        }
    }
}
```



```java
public abstract class PathToken {
    void handleObjectProperty(String currentPath, Object model, EvaluationContextImpl ctx, List<String> properties) {
        // 单个属性处理
        if(properties.size() == 1) {
            String property = properties.get(0);
            String evalPath = Utils.concat(currentPath, "['", property, "']");
            // 调用提供的json工具获取对应的属性值
            Object propertyVal = readObjectProperty(property, model, ctx);
            // 读取结果为空
            if(propertyVal == JsonProvider.UNDEFINED){
                // 跳过或者抛出异常
                // 这里代码我们先忽略
            }
            
            PathRef pathRef = ctx.forUpdate() ? PathRef.create(model, property) : PathRef.NO_OP;
            // 如果是最后一个节点(叶子节点)，则收集结果结束
            if (isLeaf()) {
                String idx = "[" + String.valueOf(upstreamArrayIndex) + "]";
                if(idx.equals("[-1]") || ctx.getRoot().getTail().prev().getPathFragment().equals(idx)){
                    ctx.addResult(evalPath, pathRef, propertyVal);
                }
            }
            else {
                // 否则使用下一个token处理当前解析到的属性值
                next().evaluate(evalPath, pathRef, propertyVal, ctx);
            }
        } else {
            // 这里是多个属性的处理逻辑，先忽略，大家有兴趣可以自行看下相关源码
        }
    }
    
    // 使用提供的json工具获取对应的属性值
    private static Object readObjectProperty(String property, Object model, EvaluationContextImpl ctx) {
        return ctx.jsonProvider().getMapValue(model, property);
    }
}


```

以上就是全部内容，整体比较简略，大致介绍了下使用和大概实现，希望抛砖引玉吧

其中如有错误，欢迎指正，感谢～
