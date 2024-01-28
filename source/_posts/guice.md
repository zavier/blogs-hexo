---
title: DI框架-Guice入门
date: 2024-01-27 23:49:59
tags: [guice, java, di]
---

在使用Spring框架时，我们应该已经非常熟悉依赖注入这一概念，它可以帮我们节省构建类及设置相应依赖类的成本，只需要声明自己需要哪些类/接口即可使用，同时还可以更好的支持单元测试

这次我们看一下另一款依赖注入的框架[guice](https://github.com/google/guice)，下面介绍的内容也都是来自[官方文档](https://github.com/google/guice/wiki/)

<!-- more -->

首先需要引入包

```xml
<dependency>
    <groupId>com.google.inject</groupId>
    <artifactId>guice</artifactId>
    <version>7.0.0</version>
</dependency>
```

首先需要定义好相关的接口和实现类，如果有外部依赖的类，可以使用构造器注入，添加上@Inject注解

```java
public class RealBillingService implements BillingService {
    private final CreditCardProcessor processor;
    private final TransactionLog transactionLog;

    @Inject
    public RealBillingService(CreditCardProcessor processor, TransactionLog transactionLog) {
        this.processor = processor;
        this.transactionLog = transactionLog;
    }

    public Receipt chargeOrder(PizzaOrder order, CreditCard creditCard) {
        try {
            ChargeResult result = processor.charge(creditCard, order.getAmount());
            transactionLog.logChargeResult(result);

            return result.wasSuccessful()
                    ? Receipt.forSuccessfulCharge(order.getAmount())
                    : Receipt.forDeclinedCharge(result.getDeclineMessage());
        } catch (Exception e) {
            transactionLog.logConnectException(e);
            return Receipt.forSystemFailure(e.getMessage());
        }
    }
}
```

之后需要构造一个模块，将接口和实现类进行绑定

```java
public class BillingModule extends AbstractModule {
    @Override
    protected void configure() {
        // 绑定接口和对应的实现类
        bind(TransactionLog.class).to(DatabaseTransactionLog.class);
        bind(CreditCardProcessor.class).to(PaypalCreditCardProcessor.class);
        bind(BillingService.class).to(RealBillingService.class);
    }
}
```

使用时也需要通过Guice来获取接口实现

```java
// 构造注入器
Injector injector = Guice.createInjector(new BillingModule());
// 获取接口实现类
BillingService billingService = injector.getInstance(BillingService.class);
// 进行使用
billingService.chargeOrder(xx, )
```

如果熟悉spring的同学可能会意识到，Guice自动将代码分成了各个模块，分别独立注入，但是spring默认是全局只有一个容器

同时，guice不仅可以注入接口实现类，也可以注入如字符串、数值类型的值，不过这类注入需要使用自定义的注解

先来定义一下自定义的注解

```java
@Retention(RUNTIME)
@interface Message {}

@Retention(RUNTIME)
@interface Count {}
```

其次定义需要注入的类，及声明注入信息

```java
public class Greeter {
    private final String message;
    private final int count;

    @Inject
    Greeter(@Message String message, @Count int count) {
        this.message = message;
        this.count = count;
    }
}
```

模块声明中需要提供对应的值

```java
public class DemoModule extends AbstractModule {
    @Provides
    @Count
    static Integer provideCount() {
        return 3;
    }

    @Provides
    @Message
    static String provideMessage() {
        return "hello world";
    }
}
```

