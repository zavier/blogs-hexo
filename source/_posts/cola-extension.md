---
title: 统一流程下的差异点解决方案-扩展点
date: 2023-09-17 10:07:04
tags: [java]
---

我们都知道设计原则，追求开放封闭原则，封装变化

比如我们有一个统一的流程，运转良好且自认为设计的不错，这时来了个需求，说需要针对不同的来源要有一些特殊的处理，这时候我们如何支持呢？

一种简单的解决方案是加一个 if 判断，做一点特殊逻辑，但是这不是一个好的实践

这时候我们想到可以将这部分差异功能抽象为一个接口，然后有一种特殊的实现类还有一个默认的实现类。但是这时候另一个问题出现了，在执行到这部分逻辑的时候，如何确认使用哪个实现类呢（需要一个定位逻辑）

后面可能对于这个来源，还有一个地方需要处理，这时候又要有一套接口和定位逻辑

这时候我们可以考虑一下使用扩展点的方案，我们看下 [COLA](https://github.com/alibaba/COLA/tree/master/cola-components/cola-component-extension-starter) 提供的扩展点（示例来自源码）

<!-- more -->

首先引入一下依赖的包

```xml
<dependency>
    <groupId>com.alibaba.cola</groupId>
    <artifactId>cola-component-extension-starter</artifactId>
    <version>4.3.2</version>
</dependency>
```

### 定义扩展点

接下来我们正式开始开发，需要先将需要扩展的功能抽离出来，定义成扩展点（接口）

这里我们就以COLA提供的添加客户流程为例子吧，添加客户时首先需要对客户信息等进行校验，对于不同的客户校验的点是不同的，所以这里将客户校验提取成一个扩展点

```java
// 这里需要注意两点
// 1. 扩展点接口需要继承 ExtensionPointI 接口
// 2. 扩展点的类名称必须以 ExtPt 结尾
public interface AddCustomerValidatorExtPt extends ExtensionPointI {
    // 这里是我们定义的接口方法
    void validate(AddCustomerCmd addCustomerCmd);
}
```

### 扩展点实现

现在需要对接口进行实现，对于不同的实现，需要使用 Extension 注解进行描述实现的功能对应的场景

这里先看下这个注解的参数，这里使用原文档中的解释

```java
@Repeatable(Extensions.class) // 可以在一个实现类上添加多个扩展定位注解（一个实现对应支持多个场景）
public @interface Extension {
    // 就是一个自负盈亏的财务主体，比如tmall、淘宝和零售通就是三个不同的业务
    String bizId()  default BizScenario.DEFAULT_BIZ_ID;
    // 描述了用户和系统之间的互动，每个用例提供了一个或多个场景。比如，支付订单就是一个典型的用例
    String useCase() default BizScenario.DEFAULT_USE_CASE;
    // 场景也被称为用例的实例（Instance），包括用例所有的可能情况（正常的和异常的）。比如对于“订单支付”这个用例，就有“可以使用花呗”，“支付宝余额不足”，“银行账户余额不足”等多个场景
    String scenario() default BizScenario.DEFAULT_SCENARIO;
}
```

这里我们可以不必拘泥于它的解释，可以按照自己的业务场景进行定义，只要统一即可

```java
@Extension(bizId = Constants.BIZ_1)
public class AddCustomerBizOneValidator implements AddCustomerValidatorExtPt {
    public void validate(AddCustomerCmd addCustomerCmd) {
        //For BIZ TWO CustomerTYpe could not be VIP
        if(CustomerType.VIP == addCustomerCmd.getCustomerDTO().getCustomerType())
            throw new BizException("Customer Type could not be VIP for Biz One");
    }
}
```

```java
@Extension(bizId = Constants.BIZ_2)
public class AddCustomerBizTwoValidator implements AddCustomerValidatorExtPt {
    public void validate(AddCustomerCmd addCustomerCmd) {
        //For BIZ TWO CustomerTYpe could not be null
        if (addCustomerCmd.getCustomerDTO().getCustomerType() == null)
            throw new BizException("CustomerType could not be null");
    }
}
```

### 使用

使用的时候就要考虑扩展点实现的定位了，目前COLA实现的定位逻辑

1. 先根据入参中的 bizId+useCase+scenario完全匹配定位扩展点
2. 如果获取不到，则根据 bizId+useCase 去匹配实现的扩展点（扩展点实现中也不能声明scenario属性值）
3. 还获取不到的话，则根据 bizId 去匹配实现的扩展点（扩展点实现中也不能声明scenario属性值）
4. 仍然获取不到则抛出异常

```java
@Component
public class AddCustomerCmdExe {

    /**
     * 这里注入 ExtensionExecutor 
     *
     */
    @Resource
    private ExtensionExecutor extensionExecutor;

    public Response execute(AddCustomerCmd cmd) {
        logger.info("Start processing command:" + cmd);

        // 根据请求中的信息，定位到扩展点，执行对应扩展点的校验逻辑
        // ExtensionExecutor中也提供了其他的执行方法，这里就不一一列举出来了
        extensionExecutor.executeVoid(AddCustomerValidatorExtPt.class, cmd.getBizScenario(), extension -> extension.validate(cmd));
        
        // 下面为其他的统一业务逻辑

        // Convert CO to Entity
        CustomerEntity customerEntity = extensionExecutor.execute(CustomerConvertorExtPt.class, cmd.getBizScenario(), extension -> extension.clientToEntity(cmd));
        // Call Domain Entity for business logic processing
        logger.info("Call Domain Entity for business logic processing..."+customerEntity);
        customerEntity.addNewCustomer();

        logger.info("End processing command:" + cmd);
        return Response.buildSuccess();
    }
}
```

这里我们可以借鉴它的思路，其中包括扩展点的定义，以及定位匹配逻辑，可以根据业务灵活实现自己的一套扩展点功能

这样对于一般的场景就都通过定义扩展点支持了，其实这个也可以做的复杂一些，就是将扩展点接口独立打包，具体实现由各个业务线来实现（但是这样有一个问题就是扩展点实现中很难再调用通用的功能了），这部分有兴趣可以看一下 [PF4j](https://github.com/pf4j/pf4j)，之前也简单写过一篇笔记[PF4J入门使用](https://www.zhengw-tech.com/2022/01/02/pf4j-use/)

