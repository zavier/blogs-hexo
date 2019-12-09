---
title: Drools入门使用
date: 2019-10-01 19:36:06
tags: drools
---



Drools是一款基于Java语言的开源规则引擎，通过drools特定的语法，将复杂多变的业务规则统一管理。



## 环境配置

### 一、使用`maven`创建项目

添加相关依赖，`pom.xml`如下

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project ...>
    <packaging>kjar</packaging>

    <dependencies>
        <dependency>
            <groupId>org.drools</groupId>
            <artifactId>drools-compiler</artifactId>
            <version>7.27.0.Final</version>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.kie</groupId>
                <artifactId>kie-maven-plugin</artifactId>
                <version>7.27.0.Final</version>
                <extensions>true</extensions>
            </plugin>
        </plugins>
    </build>

</project>
```

<!-- more -->

### 二、创建kmodule.xml文件

在src/main/resources/META-INF下创建kmodule.xml文件

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<kmodule xmlns="http://www.drools.org/xsd/kmodule">
    <!-- 
        packages指定的路径为规则所在的包（规则文件需要在src/main/resources下） 
        读取包下的所有规则文件到kbase中
    -->
    <kbase name="rules" packages="rules">
        <!-- session中的name需要唯一，可以通过此名称获取会话，type分为有状态无状态 -->
        <ksession name="testhellowrold" type="stateful" />
        <ksession name="testhellowrold_1" type="stateless" />
    </kbase>
</kmodule>
```

### 三、创建会话执行规则

```java
public class SessionTest {
    public void testRun() {
        KieServices kieServices = KieServices.Factory.get();
        // 读取 META-INF/kmodule.xml文件，生成KieContainer
        KieContainer kieClasspathContainer = kieServices.getKieClasspathContainer();
        // 根据kmodule.xml中ksession中的name属性获取创建会话
        KieSession ks = kieClasspathContainer.newKieSession("testhellowrold");
        // 执行规则(可以在此之前执行insert等方法插入Fact数据执行规则)
        int count = ks.fireAllRules();
        System.out.println("总共执行了" + count + "条规则");
        // 释放会话的资源
        ks.dispose();
    }
}

// 或者也可以不使用xml, 手动获取规则文件生成KieSession:
KieHelper helper = new KieHelper();
for (KieRuleInfo ruleInfo : rules) {
    helper.addContent(ruleStr, ResourceType.DRL);
}
KieBase kieBase = helper.build();
KieSession kieSession = kieBase.newKieSession();
```



## 规则使用

规则文件的后缀名为drl

```drl
rule "规则名称"
    "规则属性"
    when
        规则校验
    then
        when中的条件都为true时，执行的逻辑
end
```

下面依次介绍上面的部分

### when中条件匹配

#### 字符串匹配

1、str1 matches "正则表达式"
2、str1 str[startwWith|endsWith|length] 

使用

```drl
rule "matchesTest001"
    when
        $p : Person(name matches "张.*");
    then
        System.out.println("matchesTest001 success");
end

rule "strTest001"
    when
        $p : Person(name str[startsWith] "张")
    then
        System.out.println("strTest001 success");
end
```



#### 集合匹配 - in/ not in

判断元素是否（在/不在）集合中

使用

```drl
rule "in使用"
    when
        $s: School($cn: className)
        $p: Person(className in ("五班", "六班", $cn))
    then
        System.out.println("check in的使用: " + $s + "," + $p);
end
```

或者可以反过来使用`contains`关键字


#### 实体匹配 - not/ exists

判断实体是否存在

使用

```drl
rule "测试not"
    when
        not Person()
    then
        System.out.println("Person不存在");
end

rule "测试exists"
    when
        exists Person()
    then
        System.out.println("Person存在");
end
```



#### 将表达式转换为bool值 - eval

使用

```drl
rule "测试eval"
    when
        eval(1 == 1)
    then
        System.out.println("eval true");
end
```



#### 全匹配- forall

当其中的条件都为true时，为true

使用

```drl
rule "测试forall"
    when
        forall($p : Person(name == "张三")
                Person(this == $p, age == 30))
    then
        System.out.println("forall true");
end
```



#### 引用资源 - from

引用指定的资源，用于数据匹配或对集合进行遍历

使用

```drl
rule "测试from"
    when
        $p: Person($ps: school)
        $s: School(className == "一班") from $ps;
    then
        System.out.println("测试from: " + $p + "," + $s);
end

rule "测试from1"
    when
        $s: School()
        $p: Person(className == "一班") from $s.classNameList
    then
        System.out.println("测试from1: " + $p + "," + $s);
end
```



#### 收集集合及过滤 - collect

使用

```drl
rule "测试from collect"
    when
        $al: ArrayList() from collect($p: Person(className == "一班"))
    then
        System.out.println("res size: " + $al.size());
end


rule "测试from collect pattern"
    when
        $al: ArrayList(size >= 3) from collect($p: Person(className == "一班"))
    then
        System.out.println("res size: " + $al.size());
end
```



#### 集合的复杂处理 - accumulate

使用

```drl
rule "测试accumulate 取最大值、最小值"
    when
        accumulate(Person($age: age), $min:min($age), $max:max($age), $sum:sum($age))
    then
        System.out.println("max:" + $max + ", min: " + $min + ",sum:" + $sum);
end

rule "测试accumulate 第二种用法"
    when
        $total: Integer() from
            accumulate(Person($value: age),
                        init(Integer total = 0;),
                        action(total += $value;),
                        result(total)
                       )
    then
        System.out.println("total:" + $total);
end
```



### then中的后续处理

在`when`中的条件满足后，进行`then`的后续逻辑处理，此时可对传进来的数据进行修改等操作

#### update(对象)

单纯的调用对象的方法修改其中的属性，不会触发其他规则的校验

但修改后调用update则会告诉引擎对象已经改变，如果满足条件则会触发规则

也可以简写为： modify() {}，如：

```drl
rule "测试更新"
    when
        $p : Person(name matches "张.*");
    then
        modify($p){
            setName("李四")
        }
        System.out.println("matchesTest001 success");
end
```



#### insert(对象)

将新的对象放入工作空间



#### delete(对象)

将工作空间的对象删除



#### drools.halt()

终止规则的执行



### 规则属性

#### no-loop

当update修改对象后，可能会再次触发自身规则，形成死循环

当其值为true时，可以避免自己被自己触发



#### lock-on-active

当其值为true时，则只会被触发一次



#### salience

规则的执行顺序，默认值为0，也可以设置为负数，数值越大，优先级越高



#### activation-group

激活分组，具有相同组名称的规则体只有一个规则被激活，属性受salience影响



样例代码：https://github.com/zavier/drools-demo



