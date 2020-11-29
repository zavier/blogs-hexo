---
title: 状态模式笔记
date: 2019-10-19 13:35:32
tags: [设计模式]
---

在介绍状态模式之前，我们先看个简单的例子

比如我们正常的网上购物的订单，对于订单它有许多个不同的状态，在不同状态下会有不同的行为能力，如状态有待支付、已支付待发货、待收货、订单完成等等，在整个订单流转过程中，由不同的事件行为导致它状态的变更，可以看下它简单的状态图

![order-state](/images/order-state.png)

这些状态虽然不同，但是都是属于订单的状态，对应的行为也是订单的行为，在编码的过程中，一种写法是将这些行为(方法)都写到订单这个类或者类似OrderService这种类中，如

```java
public class OrderService {
  	private OrderDao orderDao;

    public void pay(Long orderId) {
        Order order = orderDao.findById(orderId);
        // 下面逻辑也可以改成使用switch
        if (order.getStatus() == OrderStatus.WAIT_PAY) {
            // 待支付，则进行支付
        } else if (order.getStatus() == OrderStatus.PAYING) {
            // 支付中，则进行相应提示
        } else if (order.getStatus() == OrderStauts.PART_PAID) {
            // 部分支付，则进行相应处理
        } else {
            // 其他状态进行对应处理
        }
    }
}
```

这样每次进行操作时，我们要先进行一下当前状态的判断，如用户支付时，我们要判断一下当前订单的状态，如果是待支付，则进行支付操作后，将状态改为已支付；如果当前状态是已支付时，就要提示用户当前订单已支付，不能再次支付等等，如果订单状态比较复杂时就会导致这个类中充斥大量的`if`、`switch`等判断逻辑，维护不便

而状态模式则提供了另一种解决方案，它将**与特定状态相关的行为局部化**，也使得状态转换现实化，下面我我们来具体看一下

<!-- more -->

## 状态模式

状态模式的目的：允许一个对象在其内部状态改变时改变它的行为，使得对象看起来似乎修改了它的类

我们先看一下状态模式的类图

![state-pattern](/images/state-pattern.jpg)

Context为客户感兴趣的接口，State为状态，ConcreteState为具体状态子类，每一个子类实现一个与Context的一个状态相关的行为

Context将与状态相关的请求委托给对应的ConcreteState对象处理，同时可将自身作为一个参数传递给该请求对应的状态对象

下面我们使用《敏捷软件开发：原则、模式与实践（C#版）》中的闸机例子来分析一下

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

以上基本就是状态模式的主要使用方式，相比起聚在一起的判断代码，它将不同状态的行为分割开来，让每一个状态相关的代码都集中在对应的State状态类中，如果有新的状态子类，可以很容易的增加扩展，而不需要改动之前的代码（符合开闭原则）

当然，这样带来的一个副作用就是增加了子类的数目，但是如果状态复杂时，这个成本还是值得的



最后我们总结一个状态模式的适用场景

1. 一个对象的行为取决于它的状态，并且它必须在运行时刻根据状态改变它的行为
2. 一个操作中含有庞大的多分支的条件语句，且这些分支依赖于该对象的状态。这个状态通常用一个或多个枚举常量表示。通常，有多个操作包含这一相同的条件结构。State模式将每一个条件分支放入一个独立的类中。这使得你可以根据自身的情况将对象的状态作为一个对象，这一对象可以不依赖于其他对象而独立变化



参考资料

1. 《设计模式-可复用面向对象软件的基础》
2. 《敏捷软件开发：原则、模式与实践（C#版）》