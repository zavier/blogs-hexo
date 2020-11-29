---
title: 状态机简介
date: 2020-11-29 20:20:32
tags: [状态机]
---

之前通过[《状态模式》](2019/10/19/state-pattern/)介绍了一下状态模式的使用，这次我们来介绍一下有限状态机

维基百科中是这样定义的：有限状态机(FSM)又称有限状态自动机(FSA)，简称状态机，是表示有限个状态以及在这些状态之间的转移和动作等行为的数学计算模型，在任何给定时间都可以恰好处于有限数量的状态之一

其实状态模式也可以算是状态机的一种实现，除了状态模式，还有一种实现方式就是创建一个描绘迁移的数据表，该表被一个处理事件的处理引擎解释。引擎查找与事件匹配的迁移，调用响应的动作并更改状态，这样状态机的逻辑全部集中在了一个地方

所以表驱动的状态机和状态模式的主要区别就是：**状态模式对于状态相关的行为进行建模，而表驱动的方法着重于定义状态转换**

<!-- more -->

这里我们介绍一下表驱动的状态机实现，虽然这方式叫基于表驱动的状态机，但是这个表不是说特指我们平时用的数据库的表，而是一种关系的记录

现在已经有了很多成熟开源的状态机可以使用，如 [Spring Statemachine](https://github.com/spring-projects/spring-statemachine)、[Squirrel Statemachine](https://github.com/hekailiang/squirrel)和[stateless4j](https://github.com/stateless4j/stateless4j)，平时工作如果需要，直接使用就好而不需要自己再开发，这次就以最轻量级的 stateless4j 为例来介绍一下状态机的使用

还是使用《状态模式》中的闸机例子

![trunstile](/images/trunstile.jpg)

具体代码如下

```java
// <dependency>
//     <groupId>com.github.stateless4j</groupId>
//     <artifactId>stateless4j</artifactId>
//     <version>2.6.0</version>
// </dependency>

StateMachineConfig<State, Trigger> phoneCallConfig = new StateMachineConfig<>();

// 配置状态机在关门状态下，对于不同事件触发的状态变化及行为
phoneCallConfig.configure(State.LOCKED)
        // 投币则状态变为打开状态，并且进行开门操作
        .permit(Trigger.COIN, State.UNLOCKED, () -> {
            System.out.println("opening...");
        })
        // 关门状态下通过，则状态不变，且触发警报行为
        .permitInternal(Trigger.PASS, () -> {
            // alarm
            System.out.println("alarming...");
        });

phoneCallConfig.configure(State.UNLOCKED)
        // 开门状态下，通过则状态改为关门状态，并且触发关门动作
        .permit(Trigger.PASS, State.LOCKED, () -> {
            System.out.println("locking...");
        })
        // 开门状态下，投币状态不变，且触发致谢行为
        .permitInternal(Trigger.COIN, () -> {
            // thank you
            System.out.println("thank you...");
        });

StateMachine<State, Trigger> turnStileSm =
        new StateMachine<>(State.LOCKED, phoneCallConfig);

// 投币开门
turnStileSm.fire(Trigger.COIN);
Assert.assertEquals(State.UNLOCKED, turnStileSm.getState());

// 开门投币-致谢
turnStileSm.fire(Trigger.COIN);
Assert.assertEquals(State.UNLOCKED, turnStileSm.getState());

// 通过关门
turnStileSm.fire(Trigger.PASS);
Assert.assertEquals(State.LOCKED, turnStileSm.getState());

// 关门通过-报警
turnStileSm.fire(Trigger.PASS);
Assert.assertEquals(State.LOCKED, turnStileSm.getState());
```

当然，这里只是展示了一下简单的用法，具体有兴趣的可以去了解一下对应状态机提供的API

状态机可以应用的地方还有很多，如

1. TCP协议中，在连接的不同状态（建立连接、监听中、关闭），对于发送等行为处理逻辑不同
2. 一些画图类工具，用户选择了如画矩形、画圆形等按钮，则触发状态转换，此时拖动数据会触发画图的不同画圆或者画矩形等行为
3. 用户界面，对于哪些按钮是激活态，哪些按钮置灰不可用，则可以通过状态来进行控制，不同状态下的展示效果不同





参考资料

1. 《设计模式-可复用面向对象软件的基础》
2. 《敏捷软件开发：原则、模式与实践（C#版）》