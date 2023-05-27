---
title: Java项目中使用Groovy的几种方式
date: 2023-03-25 17:23:17
tags: [java, groovy]
---

Groovy本身是一门完整的编程语言，同时也可以作为脚本集成到我们的应用中，为静态语言提供一些动态的能力，比如将 groovy 的脚本放到一些动态配置中或者数据库中进行管理，实现一些动态的规则计算等，在规则新增或变更的时候可以实时更新而无需开发代码上线，这次主要介绍一下Java中如何使用Groovy脚本

关于在应用中集成Groovy，官方文档已经提供了相关的[资料](http://www.groovy-lang.org/integrating.html)，本次基于此文档进行一下说明

首先需要引入相应的包，这里基于的版本是`3.0.16`

```xml
<dependency>
    <groupId>org.codehaus.groovy</groupId>
    <artifactId>groovy-all</artifactId>
    <version>3.0.16</version>
</dependency>
```

<!-- more -->

## Eval

Eval是最简单的一种用法

```java
import groovy.util.Eval;

// 1.执行没有参数的表达式，其中可以调用方法
Eval.me("33*3");  // 99
Eval.me("'foo'.toUpperCase()"); // FOO

// 2. 执行有一个参数的表达式
// x赋值为4，执行表达值（变量名固定为x）
Eval.x(4, "2 * x"); // 8
// k赋值为4，，执行表达值（自定义变量名，并在脚本中使用）
Eval.me("k", 4, "2 * k"); // 8

// 3. 执行有两个参数的表达式
// x赋值为4， y赋值为6，执行表达值（变量名固定依次为x、y）
Eval.xy(4, 5, "x * y"); // 20

// 3. 执行有三个参数的表达式
// x赋值为4， y赋值为6，z赋值为6，执行表达值（变量名固定依次为x、y、z）
Eval.xyz(4, 5, 6, "x * y + z"); // 26
```

表达式中可以调用自定义类的方法，如

```java
@Data
@AllArgsConstructor
static class Goods {
    private String goodsName;
    private BigDecimal price;
    private Integer num;

    public BigDecimal totalPrice() {
        return price.multiply(new BigDecimal(num));
    }
}

Goods goods = new Goods("goods1", new BigDecimal("100.54"), 5);
Object result = Eval.me("goods", goods, "goods.totalPrice()");
// result == 502.70
```

同时，表达式中也支持多行

```java
Object result = Eval.me("def i = 5; def j = 6; i + j");
// result == 11

// 甚至可以定义函数并执行(定义函数之后，需要手动调用函数才能执行)
Object result = Eval.me("def run1() {def i = 5;def j = 's'; j + i}; run1()");
// result == s5
```

但是使用Eval需要注意，它是不支持缓存的，每次执行都会创建类（会占用永久代/元空间），虽然占用的空间在GC的时候会被回收，不过表达式需要频繁执行的话，还是尽量不要使用



## GroovyShell

GroovyShell可以认为是Eval的升级版，主要有如下几个方面的改进

1. 支持多种脚本来源，而不仅仅只能通过字符串传递脚本

```java
URI uri = new URL("https://example.test/script.groovy").toURI();
Object evaluate = groovyShell.evaluate(uri);
```

2. 支持设置和返回更多的参数

```java
// 通过bindng传递参数给Shell
Binding sharedData = new Binding();
GroovyShell shell = new GroovyShell(sharedData);
sharedData.setProperty("text", "I am shared data");
sharedData.setProperty("num", 10);
Object result = shell.evaluate("text + ': ' + num");
// I am shared data: 10

Binding sharedData = new Binding();
GroovyShell shell = new GroovyShell(sharedData);
// 脚本中的变量如果前面有def或者int等声明，则无法通过Binding获取
Object result = shell.evaluate("i = 10; i + 1");
// result == 11
Object i = sharedData.getProperty("i");
// i == 10
```

3. 可以先解析脚本，延迟执行

```java
// 解析脚本，生成Script
GroovyShell shell = new GroovyShell();
Script script = shell.parse("4 * num");

// 给Script绑定变量
Binding binding = new Binding();
binding.setProperty("num", 7);
script.setBinding(binding);

// 执行脚本
Object run = script.run();
// run == 28
```

GroovyShell每次执行时也是会创建新的类，解析创建的Script实例是可以进行缓存的，避免每次都加载新的类和创建对应实例，但是因为涉及到外部绑定的变量，所以如果变量有变更，在并发的情况下会有问题，不能在并发情况下使用



## GroovyClassLoader

之前说过的不管是 Eval 还是 GroovyShell ，它们最终都是使用 GroovyClassLoader进行脚本的解析、创建并加载类来执行的

```java
GroovyClassLoader classLoader = new GroovyClassLoader();
Class aClass = classLoader.parseClass("class Foo {String doIt() {return \"ok\"}}");
Object object = aClass.newInstance();
Method method = object.getClass().getDeclaredMethod("doIt");
Object invoke = method.invoke(object);
// invoke == "ok"


// 解析类的脚本，也不一定非要使用class来定义，如下定义方式也是可以使用的（默认解析为Script类，会有run方法）
GroovyClassLoader classLoader = new GroovyClassLoader();
Class aClass = classLoader.parseClass("def doIt(i) {return \"ok \" + i}");
Object object = aClass.newInstance();
Method method = object.getClass().getDeclaredMethod("doIt", Object.class);
Object invoke = method.invoke(object, 6);
// invoke == "ok 6"

// 对于没有参数的场景，甚至可以这样写（默认解析为Script类，会有run方法）
GroovyClassLoader classLoader = new GroovyClassLoader();
Class aClass = classLoader.parseClass("3 + 5");
Script object = (Script) aClass.newInstance();
Object result = object.run();
// result == 8
```

使用这种方式的时候，我们可以缓存创建的实例和对应的方法，之后就可以根据这两个信息进行方法的调用了，同时如果脚本类写的没有问题时，也不会有并发的问题

以上就是在 Java 项目中使用 Groovy脚本的几种主要方式，大家可以根据具体的使用场景进行选择，尽量缓存创建的实例

