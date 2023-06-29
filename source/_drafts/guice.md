



@Inject

构造器注入



module允许应用程序指定如果满足其依赖



guice is a map

guice Key: 绑定接口和一个可选的自定义注解

```
Key<String> databaseKey = Key.get(String.class);
Key<String> key = Key.get(String.class, English.class);
```

provider:  用于创建对象实例

大部分应用不会直接使用provider接口，而是使用Module来配置Guice injector, 其内部为其知道的所有对象创建provder



作用域 scope



绑定

绑定的对象不一定需要自己实例化

```java
@Provides
TransactionLog provideTransactionLog(DatabaseTransactionLog impl) {
    // impl不需要自己创建实例
    return impl;
}
```

```java
@Inject
public RealBillingService(@Named("Checkout") CreditCardProcessor processor,
    TransactionLog transactionLog) {
  ...
}

final class CreditCardProcessorModule extends AbstractModule {
  @Override
  protected void configure() {
    bind(CreditCardProcessor.class)
      .annotatedWith(Names.named("Checkout"))
      .to(CheckoutCreditCardProcessor.class);
  }
}
```



- 绑定注解和实现类(非实例)，可通过加上自定义注解
- 绑定类型和常量（字符串、数值等）
- 绑定类型和实例
- 绑定provider接口实现
- 无接口绑定（只有实例自己）