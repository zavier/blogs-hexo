---
title: spring-aop 使用及浅浅析
date: 2019-11-28 12:28:10
tags: [spring, java]
---



看过了前面的[Spring Beans](tags/spring/)相关的 IOC 功能, 接下来我们来看看 AOP 是如何实现的

我们都知道 AOP 是通过动态代理来实现的, 但是代理这一步是如何实现的呢? 其实就是之前提到过的, 在Spring Bean的创建过程中, 实现`BeanPostProcessor`的接口可以对创建好的Bean进行修改替换等操作

```java
protected Object initializeBean(String beanName, Object bean, RootBeanDefinition mbd) {
    invokeAwareMethods(beanName, bean);
    Object wrappedBean = applyBeanPostProcessorsBeforeInitialization(wrappedBean, beanName);
    invokeInitMethods(beanName, wrappedBean, mbd);
  
    // 依次执行beanFactory中所有实现BeanPostProcessor的后置方法,对Bean进行修改(*AOP创建返回代理处*)
    wrappedBean = applyBeanPostProcessorsAfterInitialization(wrappedBean, beanName);
    return wrappedBean;
}
```

<!-- more -->

下面来具体看一下实现方式

Spring AOP的基本接口是 `Advisor`, 它持有一个 AOP Advice「在joinpoint处要执行的增强行为」, 同时还持有一个决定 Advice是否适用的过滤器, 如pointcut;  也就是说 `Advisor`决定是否要对某个方法进行增强以及增强的具体逻辑实现是什么

![aop](images/aop.jpg)

还有一个我们需要注意的接口就是`Interceptor`, 这个接口继承了`Advice`, 也就是说它是用来对方法进行修改增强的, 它还有一些子类, 如`MethodBeforeAdviceInterceptor`用来在方法执行前进行处理, `MethodInterceptor`用来在方法执行前后进行自定义逻辑处理



当定义好了 `Advisor`后, 需要一个类来负责在创建bean的时候用所有的`Advisor`进行匹配并生成对应的代理类返回, 这个类就是`AbstractAutoProxyCreator`的实现类, 它继承了`BeanPostProcessor`接口,在创建bean的过程中进行拦截处理

```java
// ********  AbstractAutoProxyCreator   *********
@Override
public Object postProcessAfterInitialization(@Nullable Object bean, String beanName) {
	if (bean != null) {
		Object cacheKey = getCacheKey(bean.getClass(), beanName);
		if (this.earlyProxyReferences.remove(cacheKey) != bean) {
      // 对类进行代理包装
			return wrapIfNecessary(bean, beanName, cacheKey);
		}
	}
	return bean;
}

protected Object wrapIfNecessary(Object bean, String beanName, Object cacheKey) {
	if (StringUtils.hasLength(beanName) && this.targetSourcedBeans.contains(beanName)) {
		return bean;
	}
	if (Boolean.FALSE.equals(this.advisedBeans.get(cacheKey))) {
		return bean;
	}
	if (isInfrastructureClass(bean.getClass()) || shouldSkip(bean.getClass(), beanName)) {
		this.advisedBeans.put(cacheKey, Boolean.FALSE);
		return bean;
	}

	// 如果有匹配的advice,则创建代理
	Object[] specificInterceptors = getAdvicesAndAdvisorsForBean(bean.getClass(), beanName, null);
	if (specificInterceptors != DO_NOT_PROXY) {
		this.advisedBeans.put(cacheKey, Boolean.TRUE);
    // 创建代理
		Object proxy = createProxy(
				bean.getClass(), beanName, specificInterceptors, new SingletonTargetSource(bean));
		this.proxyTypes.put(cacheKey, proxy.getClass());
		return proxy;
	}

	this.advisedBeans.put(cacheKey, Boolean.FALSE);
	return bean;
}

```



现在写一个例子代码来感受一下, 验证一下前面的结论

首先创建一个正常的服务

```java
public class DemoService {
    public void service() {
        System.out.println("this is demoService");
    }
}
```

创建Advice类

```java
public class LogAdvice implements MethodInterceptor {
    @Override
    public Object invoke(MethodInvocation invocation) throws Throwable {
        long st = System.nanoTime();
        Object result = invocation.proceed();
        System.out.println("cost time: " + (System.nanoTime() - st));
        return result;
    }
}
```

定义配置文件

```xml
<bean id="logAdvice" class="com.demo.spring.advice.LogAdvice"/>
<bean id="demoService" class="com.demo.spring.service.DemoService"/>

<!-- 定义Advisor -->
<bean id="advisor" class="org.springframework.aop.support.RegexpMethodPointcutAdvisor">
    <!-- 定义使用的advice -->
    <property name="advice" ref="logAdvice"/>
    <!-- 定义匹配方式 -->
    <property name="pattern" value="com.demo.spring.service.*" />
</bean>

<!-- 定义AspectJAwareAdvisorAutoProxyCreator Bean, 用来在创建bean实例时匹配生成代理类 -->
<bean class="org.springframework.aop.aspectj.autoproxy.AspectJAwareAdvisorAutoProxyCreator"/>
```

测试方法如下:

```java
public class Main {
    public static void main(String[] args) {
        ClassPathXmlApplicationContext applicationContext = new ClassPathXmlApplicationContext("spring.xml");
        DemoService demoService = applicationContext.getBean(DemoService.class);
        demoService.service();
    }
}

// 结果
// this is demoService
// cost time: 17346041
```



当然我们也可以使用aop标签来简化配置文件

```xml
<aop:config proxy-target-class="false">
    <aop:pointcut id="service"
                  expression="execution(* com.demo.spring.service..*(..)))"/>
    <aop:advisor advice-ref="logAdvice"
                 pointcut-ref="service"/>
</aop:config>
```

执行结果是一样的, 只是这种配置会自动注册`AspectJAwareAdvisorAutoProxyCreator` Bean, Advisor等, 具体可以参数 `AopNamespaceHandler`类



参考资料: [Spring AOP 源码解析](https://www.javadoop.com/post/spring-aop-source)



