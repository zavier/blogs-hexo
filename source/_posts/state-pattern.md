---
title: 有限状态机与状态模式
date: 2019-10-19 13:35:32
tags: [java, 设计模式]
---

## 有限状态机

维基百科中是这样定义的：有限状态机(FSM)又称有限状态自动机(FSA)，简称状态机，是表示有限个**状态**以及在这些状态之间的转移和动作等行为的数学计算模型，在任何给定时间都可以恰好处于有限数量的状态之一

它可以响应一些外部输入或其他条件而从一种状态更改为另一种状态。从一种状态到另一种状态的改变被称为过渡。有限状态机由其状态、初始状态和每个过渡条件的列表定义

下面我们举几个具体点的例子来看下

比如对于订单，它有待支付、已支付待发货、待收货、订单完成等状态，在整个过程中，由不同的事件触发它的状态变更，但是对于同样的事件，如果订单处在不同的状态则它的响应结果也是不同的

如果是在未支付状态下进行支付，则它会变更状态为已支付待发货，但如果是已支付待发货状态下仍然支付，它则会失败并提示用户已经支付过。这其实就是状态改变了，对于同一事件的响应行为也发生了变化

还有就是地铁闸机，它在关闭状态和开启状态，对于用户的投币、通过闸机事件的响应就是不同的

<!-- more -->

## 状态模式

状态模式允许一个对象在其内部状态改变时改变它的行为。对象看起来似乎修改了它的类

这时我们会发现，状态模式就是有限状态机的一种实现方法

如果我们不使用状态模式，那么代码中就会充斥着许多的`if`、`switch`等判断逻辑，在状态很多比较复杂时不易理解并修改且容易出错，而状态模式正好解决了这个问题

![state-pattern](/images/state-pattern.jpg)

Context为客户感兴趣的接口，State为状态，ConcreteState为具体状态子类，每一个子类实现一个与Context的一个状态相关的行为

Context将与状态相关的请求委托给对应的ConcreteState对象处理，同时可将自身作为一个参数传递给该请求对应的状态对象（这其实也是状态模式与策略模式的主要区别）



下面我们来看一个具体的例子及实现

地铁闸机：

| 状态 | 行为（事件） | 响应 |
| ---- | ------------ | ---- |
| 关闭 | 投币         | 开门 |
| 关闭 | （强行）通过 | 报警 |
| 开启 | 通过         | 关门 |
| 开启 | 投币         | 致谢 |

具体代码

状态接口

```java
public interface TurnstileState {
    // 行为
    void coin(Turnstile t);
    void pass(Turnstile t);
}
```

闸机控制器

```java
public class TurnstileController {
    public void unlock() {
        // todo 开门
    }
    
    public void alarm() {
        // todo 报警
    }

    public void thankyou() {
        // todo 致谢
    }

    public void lock() {
        // todo 关门
    }
}
```

门关闭状态类

```java
public class LockedTurnstileState implements TurnstileState {
    //投币后门打开
    @Override
    public void coin(Turnstile t) {
        t.setUnlock();
        t.unlock();
    }
    // 关闭时通过则报警
    @Override
    public void pass(Turnstile t) {
        t.alarm();
    }
}

```

门开启时状态类

```java
public class UnLockedTurnstileState implements TurnstileState {
    // 投币时致谢
    @Override
    public void coin(Turnstile t) {
        t.thankyou();
    }
    // 通过后将门关闭
    @Override
    public void pass(Turnstile t) {
        t.setLocked();
        t.lock();
    }
}

```

闸机功能实现

```java
public class Turnstile {
    // 维护两个具体状态类
    private static TurnstileState lockedState = new LockedTurnstileState();
    private static TurnstileState unlockedState = new UnLockedTurnstileState();
    // 闸机控制器
    private TurnstileController turnstileController;
    // 当前状态（初始状态为关闭）
    private TurnstileState state = lockedState;

    public Turnstile(TurnstileController turnstileController) {
        this.turnstileController = turnstileController;
    }
    // 投币后调用当前状态类处理
    public void coin() {
        state.coin(this);
    }
    // 人通过后调用当前状态类处理
    public void pass() {
        state.pass(this);
    }
  
  
    // 设置状态为关闭状态
    public void setLocked() {
        state = lockedState;
    }
    // 设置状态为开启状态
    public void setUnlock() {
        state = unlockedState;
    }
    // 判断是否时关闭状态
    public boolean isLocked() {
        return state == lockedState;
    }
    // 判断是否时开启状态
    public boolean isUnlocked() {
        return state == unlockedState;
    }
    // 调用控制器致谢
    void thankyou() {
        turnstileController.thankyou();
    }
    // 调用控制器报警
    void alarm() {
        turnstileController.alarm();
    }
    // 调用控制器关门
    void lock() {
        turnstileController.lock();
    }
    // 调用控制器开门
    void unlock() {
        turnstileController.unlock();
    }
}

```



好了，对于状态模式要说的就是这些，订单的处理也与上面的例子类似，其实还有许多种情况可以改造成状态模式来让代码更清晰易懂、容易维护。

对于状态机，Spring还提供了[spring-statemachine](https://projects.spring.io/spring-statemachine/)，大家如果有兴趣可以去了解下，谢谢～
