---
title: spring-beans 中 Bean解析创建过程（下）
date: 2019-05-04 23:22:43
tags: [java, spring]
---

这篇来跟踪一下`AbstractBeanFactory#getBean(java.lang.String, java.lang.Class<T>)`这个方法获取bean实例的流程，由于过程比较复杂，我们这里以一个简单的例子来跟进一下主要的流程

## Spring 配置使用

下面我们看下具体的例子代码

spring配置文件

```xml
<?xml version="1.0" encoding="UTF-8"?>
<beans xmlns="http://www.springframework.org/schema/beans"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
       xsi:schemaLocation="http://www.springframework.org/schema/beans http://www.springframework.org/schema/beans/spring-beans.xsd">

    <bean class="com.zavier.spring.beans.TestBean"
          id="testBean" init-method="myinit" destroy-method="mydestroy">
        <property name="name" value="testBeanName" />
    </bean>

</beans>
```

<!-- more -->

对应要创建的bean的定义

```java
public class TestBean implements BeanNameAware, BeanFactoryAware,
        InitializingBean, DisposableBean {
    public TestBean() {
        System.out.println("执行无参构造器");
    }

    @Override
    public void afterPropertiesSet() throws Exception {
        System.out.println("执行 InitializingBean 接口的 afterPropertiesSet 方法进行初始化");
    }

    @Override
    public void destroy() throws Exception {
        System.out.println("执行 DisposableBean 接口的 destroy 方法");
    }

    @Override
    public void setBeanName(String name) {
        System.out.println("执行 BeanNameAware 接口的 setBeanName 方法，用来声明 Bean 名称");
    }

    @Override
    public void setBeanFactory(BeanFactory beanFactory) throws BeansException {
        System.out.println("执行 BeanFactoryAware 接口的 setBeanFactory 方法，用来声明其所在的 BeanFactory");
    }

    public void myinit() {
        System.out.println("执行自己在配置文件中定义的初始化方法");
    }

    public void mydestroy() {
        System.out.println("执行自己在配置文件中定义的结束方法");
    }
}
```

main方法

```java
public static void main(String[] args) {
    ClassPathResource resource = new ClassPathResource("spring-bean.xml");
    DefaultListableBeanFactory beanFactory = new DefaultListableBeanFactory();
    XmlBeanDefinitionReader beanDefinitionReader = new XmlBeanDefinitionReader(beanFactory);
    beanDefinitionReader.loadBeanDefinitions(resource);
    // 手动注册beanPostProcessor（只要是实现BeanPostProcessor接口的类即可，不必须是TestBean）
    beanFactory.addBeanPostProcessor(new TestBean());

    TestBean bean = beanFactory.getBean("testBean", TestBean.class);
}
```

执行结果如下

```java
执行无参构造器
执行 BeanNameAware 接口的 setBeanName 方法，用来声明 Bean 名称
执行 BeanFactoryAware 接口的 setBeanFactory 方法，用来声明其所在的 BeanFactory
执行 InitializingBean 接口的 afterPropertiesSet 方法进行初始化
执行自己在配置文件中定义的初始化方法
```



## Spring 创建流程

现在来跟踪一下获取单例Bean实例的主要过程:



### 1.根据Bean名称, 创建RootBeanDefinition

这一步可以简单理解为执行了以下三个操作

#### 1.1 从registry中根据beanName获取到对应的BeanDefinition

#### 1.2 创建一个RootBeanDefinition，并将BeanDefinition的属性复制到其中

#### 1.3 如果其未设置scope, 则设置其默认的scope为 singleton(单例)



### 2.开始单例模式Bean的创建

```java
// 创建Bean
protected Object createBean(String beanName, RootBeanDefinition mbd, Object[] args) {
    // 主要执行了如下两个步骤
    // 可以在这步骤中创建代理取代原来的Bean返回
    Object bean = resolveBeforeInstantiation(beanName, mbdToUse);
    if (bean != null) {
        return bean;
    }
    // 此时执行真正的创建Bean
    Object beanInstance = doCreateBean(beanName, mbdToUse, args); 
}

protected Object doCreateBean(final String beanName, final RootBeanDefinition mbd, final Object[] args) {

    // 反射调用(如默认构造方法等)进行实例化
    BeanWrapper instanceWrapper = createBeanInstance(beanName, mbd, args);
    
    Object exposedObject = bean;
    try {
        // 为bean的属性赋值(配置文件中bean标签下配置的property, constructor-arg等)
        populateBean(beanName, mbd, instanceWrapper);
        // 调用初始化方法等,详情见下面
        exposedObject = initializeBean(beanName, exposedObject, mbd);
    }
    return exposedObject;
}

protected Object initializeBean(String beanName, Object bean, RootBeanDefinition mbd) {
    // 如果实现了BeanNameAware、BeanFactoryAware等方法,则调用进行赋值
    invokeAwareMethods(beanName, bean);
    // 依次执行beanFactory中所有实现BeanPostProcessor的前置方法,对Bean进行修改
    Object wrappedBean = applyBeanPostProcessorsBeforeInitialization(wrappedBean, beanName);
    // 执行初始化方法,先执行afterPropertiesSet,后执行配置文件中的init-method方法
    invokeInitMethods(beanName, wrappedBean, mbd);
    // 依次执行beanFactory中所有实现BeanPostProcessor的后置方法,对Bean进行修改
    wrappedBean = applyBeanPostProcessorsAfterInitialization(wrappedBean, beanName);
    return wrappedBean;
}
```



### 3.返回最终创建的bean实例，创建结束



