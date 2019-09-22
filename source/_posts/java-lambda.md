---
title: 浅谈Java Lambda表达式及其使用
date: 2019-06-07 13:50:06
tags: java
---

## 什么是 Lambda表达式？

对于 Java 中的 lambda 表达式，我们可以把它简单的理解为一个函数。

比如，我们需要这样一个函数，它需要把两个数字相加，将结果返回 则可以这样定义

```java
int add(int a, int b);
```

但是我们知道，Java中函数是没有办法单独定义存在的，所以我们需要一个接口才能声明这个函数功能

```java
interface Function {
    int add(int a, int b);
}
```

当我们需要实现这个方法的时候，一种方法就是定义一个新的类来实现这个接口

```java
class Calc implements Function {
    @Override
    public int add(int a, int b) {
        return a + b;
    }
}
```

<!-- more -->

除此之外，还有一种方法就是使用匿名类

```java
Function addFunc = new Function() {
    @Override
    public int add(int a, int b) {
        return a + b;
    }
};
```

而在 Java8 中，我们又有了一种更简单的写法，这也就是lambda表达式

```java
Function addFunc1 = (a, b) -> a + b;
```

当然，既然是为了表达一个函数所创建的接口，所以定义的接口中就必须只能有一个方法。对于这类接口，它还有一个特殊的名字: **函数式接口**，我们可以在对应的接口上面添加`@FunctionalInterface`注解来表明它的身份。

## 如何使用?

上一节我们可以知道，lambda就是函数式接口的实现，所以要想使用lambda表示式，我们必须先定义一个函数式接口，这样任何需要函数式接口的地方，我们都可以传递lambda表达式进去。我们也可以自己定义方法，接受lambda表达式参数

JDK中已经定义了很多常用的函数式接口，比如`Comparator`接口

```java
@FunctionalInterface
public interface Comparator<T> {
    int compare(T o1, T o2);
}
```

这样我们在排序的时候，接受 Comparator接口的地方就可以传递lambda表达式了，非常方便

```java
List<String> list = ...;
list.sort((s1, s2) -> s1.compareTo(s2));
```

基本常用的函数式接口，JDK已经都帮我们内置好了，不需要自己定义，大致有以下几类

### 常用函数式接口

#### Predicate 

谓词 - 用来对数据进行判断，返回true或false

```java
@FunctionalInterface
public interface Predicate<T> {
    boolean test(T t);
}
```

#### Function

用于转换数据，将前一个参数的类型转为后面的类型

```java
@FunctionalInterface
public interface Function<T, R> {
    R apply(T t);
}
```

#### Supplier

生产者，用来生产数据，无参数，返回一个对象

```java
@FunctionalInterface
public interface Supplier<T> {
    T get();
}
```

#### Consumer

消费者，就是用来消费数据，接受一个数据，无返回值

```java
@FunctionalInterface
public interface Consumer<T> {
    void accept(T t);
}
```

## Lambda表达式复合使用

函数式接口的功能都比较单一，有时候无法满足我们的需求，这时候就需要将多个lambda表达式组合到一起使用来完成功能

### 比较器复合

```java
// 对于用户类，有两个比较器
Comparator<User> ageComparator = (u1, u2) -> u1.getAge().compareTo(u2.getAge());
Comparator<User> nameComparator = (u1, u2) -> u1.getAge().compareTo(u2.getAge());

// 如果我们需要按照年龄倒序排序
Comparator<User> comparator = ageComparator.reversed();
// 年龄相等时，我们需要再根据姓名进行比较
comparator = ageComparator.thenComparing(nameComparator);
```

上面只是为了方便理解，实际比较时，可以使用 `Comparator.comparing()`方法

如按照年龄排序: `Comparator<User> newAgeComparator = Comparator.comparing(User::getAge);`

### 谓词复合

谓词接口有三个方法，`negate`, `and` ,`or`来分别表示 非、与、或

```java
// 获取年龄大于18岁的用户
Predicate<User> userPred1 = u -> u.getAge() > 18;
// 获取体重大于80的人
Predicate<User> userPred2 = u -> u.getWeight() > 80;

// 同时获取年龄大于18 且 体重大于80的人
Predicate<User> newPred = userPred1.and(userPred2);
// 获取年龄大于18 或者 体重大于80的人
Predicate<User> newPred2 = userPred1.or(userPred2);
```

**注意：如果`and`和`or`在一起使用，则会按照书写顺序来定优先级**

### 函数复合

`Function`接口提供了两个方法`andThen`和`compose`用来组合函数

andThen用在执行完当然函数，将结果用户参数中的下一个函数

而 compose顺序则相反，是执行完参数中的函数，将结果用于当前调用函数

```java
Function<Integer, Integer> f = x -> x + 1;
Function<Integer, Integer> g = x -> x * 2;

// 先执行 f 再执行 g
Function<Integer, Integer> h = f.andThen(g);
// == (10 + 1) * 2 = 22
System.out.println(h.apply(10));

// 先执行 g 再执行 f
Function<Integer, Integer> compose = f.compose(g);
// == (10 * 2) + 1 = 21
System.out.println(compose.apply(10));
```



## 附：Java8其他

### 流的扁平化-flatMap

flatMap方法让你把一个流中的每个值都换成另一个流，然后把所有的流连接起来成为一个流
```java
// 获取所有的各不相同的字符
List<String> words = Arrays.asList("hello", "world");
List<String> result = words.stream()
        // 转换为字符串数组流
        .map(word -> word.split(""))
        // Arrays.stream会将数组转换成一个流，之后将其合并为一个流
        .flatMap(Arrays::stream)
        .distinct()
        .collect(Collectors.toList());
System.out.println(result);

```

```java
// 生成所有数对，如：[(1,3), (1,3), (1,4), (2,3), (2,4), (3,3), (3,4)]
List<Integer> num1 = Arrays.asList(1, 2, 3);
List<Integer> num2 = Arrays.asList(3, 4);

List<int[]> collect = num1.stream()
        // 将每个num1中的数值转换为对应的流，并合成一个
        .flatMap(n1 -> num2.stream().map(n2 -> new int[]{n1, n2}))
        .collect(Collectors.toList());
collect.stream()
        .map(Arrays::toString)
        .forEach(System.out::println);
```


### 查找和匹配
#### 至少一个匹配
`boolean b = words.stream().anyMatch("hello"::equals);`
#### 匹配全部元素
```
boolean b1 = words.stream().allMatch("hello"::equals);
boolean b2 = words.stream().noneMatch("hello"::equals);
```
#### 查找元素
```
Optional<String> h1 = words.stream().filter("hello"::equals).findAny();
Optional<String> h2 = words.stream().filter("hello"::equals).findFirst();
```

### 收集器接口
```java
/**
 *
 * @param <T> 要收集的项目的范型
 * @param <A> 累加器的类型，累加器在收集过程中累积部分结果的对象
 * @param <R> 收集操作得到的对象的类型
 */
interface Collector<T, A, R> {
    /**
     * 建立新的结果容器
     */
    Supplier<A> supplier();

    /**
     * 将元素添加到结果容器
     */
    BiConsumer<A, T> accumulator();

    /**
     * 对结果容器应用最终转换
     */
    Function<A, R> finisher();

    /**
     * 合并两个结果容器（并行处理使用）
     */
    BinaryOperator<A> combiner();

    /**
     * 定义收集器的行为（是否可以并行归约等）
     * @return
     */
    Set<Characteristics> characteristics();
}
```

> 具体例子可参考 `Collectors.toList`实现



参考资料：《Java8 实战》