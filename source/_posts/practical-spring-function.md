---
title: spring 实用功能
date: 2019-11-30 12:06:10
tags: [java, spring]
---

Spring 不仅为我们提供了`IOC` , `AOP`功能外，还在这个基础上提供了许多的功能，我们用的最多的可能就是` Spring MVC`了吧，但是让我们来看下`spring-context`包，其中包含了缓存、调度、校验功能等等

<img src="/images/practical-spring.png" style="zoom:50%;" />

这里主要想介绍一下Spring提供的观察者模式实现(事件发布监听)及异步方法执行，这些功能也都是基于AOP实现的

<!-- more -->

## Spring 事件

观察者模式大家都了解，它可以解耦各个功能，但是自己实现的话比较麻烦，Spring为我们提供了一种事件发布机制，可以按需要发布事件，之后由监听此事件的类或方法来执行各自对应的功能，代码互相不影响，以后修改订单后续的逻辑时不会影响到订单创建，有点类似于使用MQ的感觉～ 

比如在配置中心apollo项目中，在portal创建了app后会发送app创建事件，监听此事件的逻辑处将此消息同步到各个环境的adminsevice中，大家有兴趣可以看下相关代码

现在我们来看看具体如何使用：假设一个下单场景，订单创建成功后可能有一些后续逻辑要处理，但是和创建订单本身没有关系，此时就可以在创建订单完成后，发送一个消息，又相应部分的代码进行监听处理，避免代码耦合到一起

首先创建对应的事件

```java
// 订单创建事件，需要继承 ApplicationEvent
public class OrderCreatedEvent extends ApplicationEvent {
    private String orderSn;

    public OrderCreatedEvent(Object source) {
        super(source);
    }

    public OrderCreatedEvent(Object source, String orderSn) {
        super(source);
        this.orderSn = orderSn;
    }

    public String getOrderSn() {
        return this.orderSn;
    }
}

```

现在还需要一个事件发布者和监听者，创建一下

```java
@Service
public class OrderService {

    private final ApplicationEventPublisher applicationEventPublisher;

    public OrderService(ApplicationEventPublisher applicationEventPublisher) {
        this.applicationEventPublisher = applicationEventPublisher;
    }

    public void createOrder(String orderSn) {
        //todo 创建订单的逻辑

        // 发送创建订单成功的消息
        applicationEventPublisher.publishEvent(new OrderCreatedEvent(this, orderSn));
    }
}
```

```java
@Component
public class OrderEventListener {

    @EventListener
    public void orderCreatedListener(OrderCreatedEvent orderCreatedEvent) {
        System.out.println("listen orderSn:" + orderCreatedEvent.getOrderSn() + " created");
        //todo 其他订单后处理，如通知其他系统等
    }
}
```

因为这里只是一个简单的例子，所以就用配置文件+main方法来执行了

```xml
<?xml version="1.0" encoding="UTF-8"?>
<beans xmlns="http://www.springframework.org/schema/beans"
       xmlns:context="http://www.springframework.org/schema/context"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
       xsi:schemaLocation="http://www.springframework.org/schema/beans
       http://www.springframework.org/schema/beans/spring-beans.xsd
       http://www.springframework.org/schema/context
       http://www.springframework.org/schema/context/spring-context.xsd">

    <context:component-scan base-package="com.zavier.spring" />

</beans>
```

```java
public class Main {
    public static void main(String[] args) {
        ClassPathXmlApplicationContext applicationContext = new ClassPathXmlApplicationContext("spring.xml");
        OrderService orderService = applicationContext.getBean(OrderService.class);

        orderService.createOrder("20191130123");

        applicationContext.close();
    }
}
```

这时我们看下控制台，会打印出如下内容，证明监听者确实收到了消息

```txt
listen orderSn:20191130123 created
```

简单的事件发布就完成了，其中的其他复杂逻辑由Spring替我们处理了

这里我们要注意一点：**发布和监听后处理的逻辑是在一个线程中执行的，不是异步执行**



## 异步方法

有时候我们为了提高响应速度，有些方法可以异步去执行，一般情况下我们可能是手动将方法调用提交到线程池中去执行，但是Spring 为我们提供了简化的写法，在开启了异步情况下，不用修改代码，只使用注解即可完成此功能

下面来看下具体实现（例子中提供了全局统一的线程池），我们接着上面的例子

添加如下配置(此处@slf4j使用了lombok的注解)

```java
@Slf4j
@Configuration
@EnableAsync
public class AsyncConfig implements AsyncConfigurer {

    @Override
    public Executor getAsyncExecutor() {
        // 这里的线程池可以使用业务中已经定义好的，此处只是例子
        ExecutorService executorService = Executors.newFixedThreadPool(5);
        return executorService;
    }

    @Override
    public AsyncUncaughtExceptionHandler getAsyncUncaughtExceptionHandler() {
        // 执行过程中的异常捕获处理
        return new AsyncUncaughtExceptionHandler() {
            @Override
            public void handleUncaughtException(Throwable throwable, Method method, Object... objects) {
                log.error("async execute error, method:{}, param:{}", method.getName(), JSON.toJSONString(objects), throwable);
            }
        };
    }
}
```

这时只需要在要异步执行的方法上添加`@Async`注解即可异步执行, 如

```java
@Slf4j
@Component
public class OrderEventListener {
    @Async // 此注解
    @EventListener
    public void orderCreatedListener(OrderCreatedEvent orderCreatedEvent) {
        log.info("orderCreatedListener threadId:{}", Thread.currentThread().getId());
        log.info("listen orderSn:" + orderCreatedEvent.getOrderSn() + " created");
        //todo 其他订单后处理，如通知其他系统等
    }
}
```

为了验证结果，可以在orderService发送处和事件监听代码中添加日志，打印当前所在的线程，会发现它们并不是同一个线程，大家可以自行打印看下

**注意：如果方法需要返回值的时候，需要让方法返回Future**

这类方法也可使用CompletableFuture异步编排实现

