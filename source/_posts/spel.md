---
title: SpEL使用
date: 2022-01-15 23:05:24
tags: [java, spring, spel]
---

Spring Expression Language(SpEL) 是一个表达式语言，可以用来在运行时查询和操作对象图，比较类似于EL表达式，相比其他的表达式语言，可以更好的与Spring集成，如果使用Spring的话，也可以不用再引入额外的依赖

同时它也是可以单独引入并且使用的，这里我们主要就是看一下单独使用的情况下它能做什么以及如何使用

首先需要引入依赖包

```xml
<dependency>
    <groupId>org.springframework</groupId>
    <artifactId>spring-expression</artifactId>
    <version>5.3.12</version>
</dependency>
```

<!-- more -->

## 普通表达式求值

```java
ExpressionParser parser = new SpelExpressionParser();

String helloWorld = parser.parseExpression("'Hello World'").getValue(String.class);
// helloWorld: 'Hello World'

Expression expression = parser.parseExpression("'hello' + ' world'");
String value = expression.getValue(String.class);
// value: 'hello world'

Expression expression1 = parser.parseExpression("5 + 8");
Integer v1 = expression1.getValue(Integer.class);
// v1: 13
```

在表达式中，支持各种关系、算数、逻辑表达式，同时还可以调用相关的类或者方法

```java
Expression expression = parser.parseExpression("('hello' + ' world').toUpperCase()");
String value = expression.getValue(String.class);
// value: 'HELLO WORLD'

// 对于特定类型，需要使用T(<类型>)来进行表示
Boolean value1 = parser.parseExpression("T(org.apache.commons.lang3.StringUtils).isNoneBlank('aa')").getValue(Boolean.class);
// value1: true
```



## 操作对象

当需要使用表达式解析属性、方法等时，都需要用到`EvaluationContext`这个接口，只不过当我们没有显示提供的时候，SpEL会自动创建一个实现`StandardEvaluationContext`

```java
// 创建一个对象user, 并将其作为EvaluationContext的rootObject
User user = new User();
user.setUserName("zhangsan");
user.setAge(18);
EvaluationContext context = new StandardEvaluationContext(user);
// StandardEvaluationContext对应构造函数如下
// public StandardEvaluationContext(Object rootObject) {
// 	   this.rootObject = new TypedValue(rootObject);
// }

// 使用表达式进行解析rootObject的userName属性，#root.userName中的#root可以省略，即简化为 userName
ExpressionParser parser = new SpelExpressionParser();
Expression expression = parser.parseExpression("#root.userName");
String value = expression.getValue(context, String.class);
// value: 'zhangsan'


public class User {
    private String userName;
    private Integer credits;
    // 忽略 getter, setter方法
}
```

对于只有一个rootObject的情况，可以不显示指定EvaluationContext，即上述写法可以简化为

```java
User user = new User();
user.setUserName("zhangsan");
user.setAge(18);

String userName = parser.parseExpression("userName").getValue(user, String.class);
// userName: 'zhangsan'
```

但是如果除了rootObject外还需要设置其他属性的话，那么EvaluationContext就不能省略了

```java
// 设置user为EvaluationContext的rootObject
User user = new User();
user.setUserName("zheng");
user.setAge(18);
EvaluationContext context = new StandardEvaluationContext(user);
// 设置额外的属性 addAge:10
context.setVariable("addAge", 10);

// 使用表达式计算结果，  获取属性值的方式为：  #属性名
ExpressionParser parser = new SpelExpressionParser();
Expression expression = parser.parseExpression("age + #addAge");
Integer value = expression.getValue(context, Integer.class);
// value: 28
```



同时使用SpEL不仅可以用来读取对象，还可以用来修改对象的值

```java
User user = new User();
user.setUserName("zhangsan");
user.setAge(18);

ExpressionParser parser = new SpelExpressionParser();
Expression expression = parser.parseExpression("userName");
// 将userName的值设置为lisi
expression.setValue(user, "lisi");

String res = user.getUserName();
// res: 'lisi'
```



## 集合操作

可以用过SpEL表达式实现集合过滤和数据转换操作

### 过滤

通过`.?[selectionExpression]`可以对集合中的元素进行筛选过滤

```java
List<User> userList = new ArrayList<>();
{
    User user = new User();
    user.setUserName("zhangsan");
    user.setAge(18);
    userList.add(user);
}
{
    User user = new User();
    user.setUserName("lisi");
    user.setAge(10);
    userList.add(user);
}
{
    User user = new User();
    user.setUserName("wangwu");
    user.setAge(20);
    userList.add(user);
}
ExpressionParser parser = new SpelExpressionParser();
final Expression expression = parser.parseExpression("#this.?[age > 10]");
final List<User> value = expression.getValue(userList, List.class);
// value: [User(userName=zhangsan, age=18), User(userName=wangwu, age=20)]
```

过滤操作还可以用于map类型的数据

```java
Map<String, Integer> map = new HashMap<>();
map.put("key1", 10);
map.put("key2", 20);
map.put("key3", 30);
ExpressionParser parser = new SpelExpressionParser();
final Expression expression = parser.parseExpression("#root.?[value>10]");
final Map value = expression.getValue(map, Map.class);
// value: {key2=20, key3=30}
```

### 数据映射转换

通过`.![projectionExpression]`可以对数据进行转换

```java
// 使用上例中的List<User>数据, 忽略设值代码
List<User> userList = new ArrayList<>();

ExpressionParser parser = new SpelExpressionParser();
// 映射为年龄信息
Expression expression = parser.parseExpression("#this.![age]");
List<?> value = expression.getValue(userList, List.class);
// value: [18, 10, 20]
```



## 其他

### Elvis操作符

这个操作符相当于对`?:`这个三元操作符的简化，比如当左侧表达式不为null时返回值本身，否则返回一个固定值

```java
// 三元操作符写法
String realName = name != null ? name : 'Guest';

// 使用Elvis操作符
String realName = name ?: 'Guest';
```

使用示例

```java
User user = new User();

ExpressionParser parser = new SpelExpressionParser();
Expression expression = parser.parseExpression("userName ?: 'Guest'");
String value = expression.getValue(user, String.class);
// value: 'Guest'

user.setUserName("zhangsan");
value = expression.getValue(user, String.class);
// value: 'zhangsan'
```

### 安全导航操作符

对于在取属性时可能遇到的空指针问题，如获取user的姓名时，我们通常需要判断user是否为null，这种代码比较啰嗦，取值时可以使用`?.`方式进行简化

```java
User user = null;

ExpressionParser parser = new SpelExpressionParser();
// 使用 ?. 取值时，如果对象对null不会出现空指针，只会最终返回null
Expression expression = parser.parseExpression("#root?.userName");
String value = expression.getValue(user, String.class);
// value: null
```

Elvis操作符和安全导航操作符在Groovy中也有同样的功能





参考资料：https://docs.spring.io/spring-framework/docs/current/reference/html/core.html#expressions
