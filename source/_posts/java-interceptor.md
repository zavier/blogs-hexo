---
title: 如何用非代理的方式实现java拦截器
date: 2023-09-10 12:22:30
tags: [java, 拦截器, interceptor]
---

> 《代码精进之路》中看到的拦截器实现，方式比较巧妙，在此记录一下

一般我们在代码中实现业务拦截器的功能，是通过Spring提供的AOP来实现的，底层也就是基于动态代理及反射，这里看一下使用另一种不同的实现方式

<img src="/images/java-interceptor.jpg" style="zoom:60%" />

<!-- more -->

使用时需要先构建TargetInvocation, 设置好目标类的实现、入参以及具体的拦截器信息，之后将TargetInvocation当做要调用的目标类使用，直接进行调用即可

```java
public void test() {
    // 1. 构建TargetInvocation
    final TargetInvocation targetInvocation = new TargetInvocation();
    // 2. 设置拦截器
    targetInvocation.addInterceptor(new LogInterceptor());
    targetInvocation.addInterceptor(new AuditInterceptor());
    // 3. 设置请求参数
    targetInvocation.setRequest("100");
    // 4. 设置目标接口实现(这里为了简化，直接使用lambda作为函数式接口的实现)
    targetInvocation.setTarget(Integer::parseInt);
	// 5. 调用targetInvocation获取结果
    final Integer result = targetInvocation.invoke();
    System.out.println("main resp:" + result);
}
```

下面看一下具体每个类的实现

1. 首先需要明确好我们要调用的接口和接口具体的实现类，也就是这里的Target

```java
// 目标接口
public interface Target {
    Integer execute(String req);
}

// 目标接口实现类(因为这是一个单方法的接口，可以当做函数式接口使用，直接使用lambda)
Target target = Integer::parseInt;
// 与下面等价
// Target target = new Target() {
//     @Override
//     public Integer execute(String req) {
//         return Integer.parseInt(req);
//     }
// };
```

2. 定义核心的TargetInvocation

```java
public class TargetInvocation {
    // 定义拦截器集合容器
    private List<Interceptor> interceptorList = new ArrayList<>();
    // 定义Iterator, 用于后续递归遍历时不用手动记录执行到的拦截器位置
    private Iterator<Interceptor> interceptors;
    // 实际执行的目标类
    private Target target;
    // 请求参数
    private String request;

    // 实际调用（核心）
    public Integer invoke() {
        // iterator中会自己维护索引，递归调用时，第二次调用会执行第二个interceptor
        if (interceptors.hasNext()) {
            final Interceptor interceptor = interceptors.next();
            // 这里执行interceptor时会递归调用此方法，执行第二个interceptor逻辑
            interceptor.interceptor(this);
        }
        // 所有interceptor执行完毕后，进行最终实际执行
        return target.execute(request);
    }

    public void addInterceptor(Interceptor interceptor) {
        interceptorList.add(interceptor);
        interceptors = interceptorList.iterator();
    }

    public Target getTarget() {
        return target;
    }

    public void setTarget(Target target) {
        this.target = target;
    }

    public void setRequest(String request) {
        this.request = request;
    }
}
```

3. 定义 Interceptor拦截器接口及实现类

```java
public interface Interceptor {
    // 这里返回是实际接口的返回值，但是入参是之前定义的 TargetInvocation
    Integer interceptor(TargetInvocation targetInvocation);
}
```

```java
public class AuditInterceptor implements Interceptor {
    @Override
    public Integer interceptor(TargetInvocation targetInvocation) {
        System.out.println("Audit Succeeded");
        // 递归调用回去，执行其iterator中的下一个拦截器逻辑/或者获取实际执行的结果
        return targetInvocation.invoke();
    }
}

public class LogInterceptor implements Interceptor {
    @Override
    public Integer interceptor(TargetInvocation targetInvocation) {
        System.out.println("Logging Begin");
        // 递归调用
        final Integer resp = targetInvocation.invoke();
        // 执行完成后打印日志并返回结果
        System.out.println("Loggin end resp:" + resp);
        return resp;
    }
}
```

上述代码利用了iterator的特性，在拦截器中递归调用时来实现执行下一个拦截器的功能，最终都拦截器执行完成后再进行实际代码的执行

这时执行之前的代码，执行结果如下：

```
Logging Begin
Audit Succeeded
Loggin end resp:100
main resp:100
```

相比SpringAop方式的实现，因为没有使用反射所以这里的拦截器只能针对单一明确的入参和返回类型，无法做到特别通用
