---
title: spring-beans 中 Bean解析创建过程（下）
date: 2019-05-04 23:22:43
tags: [java, spring]
---

这篇来跟踪一下`AbstractBeanFactory#getBean(java.lang.String, java.lang.Class<T>)`这个方法获取bean实例的流程，由于过程比较复杂，我们这里以一个简单的例子来跟进一下主要流程，具体未用到的创建细节大家有兴趣可以自己查看一下源码～

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
        InitializingBean, DisposableBean, BeanPostProcessor {

    private String name;

    public TestBean() {
        System.out.println("执行无参构造器");
    }

    public TestBean(String name) {
        System.out.println("执行有参构造器");
        this.name = name;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
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

    @Override
    public Object postProcessBeforeInitialization(Object bean, String beanName) throws BeansException {
        System.out.println("postProcessBeforeInitialization");
        System.out.println("Object:" + bean + ", beanName:" + beanName);
        return bean;
    }

    @Override
    public Object postProcessAfterInitialization(Object bean, String beanName) throws BeansException {
        System.out.println("postProcessAfterInitialization");
        System.out.println("Object:" + bean + ", beanName:" + beanName);
        return bean;
    }

    @Override
    public String toString() {
        return "TestBean{" +
                "name='" + name + '\'' +
                '}';
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
执行无参构造器
执行 BeanNameAware 接口的 setBeanName 方法，用来声明 Bean 名称
执行 BeanFactoryAware 接口的 setBeanFactory 方法，用来声明其所在的 BeanFactory
postProcessBeforeInitialization
Object:TestBean{name='testBeanName'}, beanName:testBean
执行 InitializingBean 接口的 afterPropertiesSet 方法进行初始化
执行自己在配置文件中定义的初始化方法
postProcessAfterInitialization
Object:TestBean{name='testBeanName'}, beanName:testBean
```



现在来跟踪一下`beanFactory.getBean("testBean", TestBean.class);`的执行流程

1.首先调用`AbstractBeanFactory.transformedBeanName(beanName)`处理转换对应的beanName

1.1 如果是以&开头的名称（FactoryBean），则将符号去掉

1.2 如果是alias名称，则获取到最终的bean名称

<br>


2.调用`AbstractBeanFactory.getSingleton(beanName)`，判断是否有缓存好的单例类，是则获取实例返回

<br>

3.如果当前的beanFactory中没有对应的bean，则从对应的parentBeanFactory中获取处理

<br>

4.标记当前beanName正在被创建中-markBeanAsCreated(beanName)

<br>

5.调用`RootBeanDefinition mbd = getMergedLocalBeanDefinition(beanName)`方法

对于上面的例子来说，可以理解为只执行了三个操作

5.1 从registry中根据beanName获取到对应的BeanDefinition

5.2 创建一个RootBeanDefinition，并将BeanDefinition的属性复制到其中

5.3 设置其默认的scope为 singleton

<br>

6.开始创建单例模式下的Bean  

```java
// Create bean instance.
if (mbd.isSingleton()) {
    // 获取单例对象，如果是新创建的，则创建后添加到singletonObjects对应的Map中
    sharedInstance = getSingleton(beanName, new ObjectFactory<Object>() {
        @Override
        public Object getObject() throws BeansException {
            try {
                return createBean(beanName, mbd, args);
            }
            catch (BeansException ex) {
                destroySingleton(beanName);
                throw ex;
            }
        }
});
// 此处用来处理FactoryBean相关的功能，从FactoryBean中获取其中真正的对象
bean = getObjectForBeanInstance(sharedInstance, name, beanName, mbd);
}
```

调用AbstractBeanFactory.getSingleton(beanName, new ObjectFactory…)

它会调用`AbstractAutowireCapableBeanFactory#createBean(String, RootBeanDefinition, Object[])`来创建bean实例

6.1 调用`AbstractBeanFactory#resolveBeanClass`将对应bean类的字符串转换为对应的Class

6.2 复制一个RootBeanDefinition实例，将之前得到的Class赋值给 BeanClass属性，供之后使用

<br>

7.调用`AbstractAutowireCapableBeanFactory#resolveBeforeInstantiation(beanName, mbdToUse)`

```java
// 可以在此处实现aop，返回代理的类实例
// Give BeanPostProcessors a chance to return a proxy instead of the target bean instance.
Object bean = resolveBeforeInstantiation(beanName, mbdToUse);
if (bean != null) {
    return bean;
}
```

<br>

8.之后调用`AbstractAutowireCapableBeanFactory#doCreateBean`开始**真正创建bean实例**

8.1 创建实例`BeanWrapper instanceWrapper = AbstractAutowireCapableBeanFactory#createBeanInstance`

在之前配置中会调用默认构造方法创建bean实例，之后会使用BeanWrapper对其进行包装

8.2 调用`applyMergedBeanDefinitionPostProcessors(mbd, beanType, beanName)`，如果实现了MergedBeanDefinitionPostProcessor接口，则可以在此处修改bean definition

8.3 处理循环依赖

8.4 对bean实例中的属性进行赋值，调用 `AbstractAutowireCapableBeanFactory#populateBean(String beanName, RootBeanDefinition mbd, BeanWrapper bw)`

8.5 `AbstractAutowireCapableBeanFactory#initializeBean(String, Object, RootBeanDefinition)`

8.5.1 如果实现对应Aware方法，则对其进行调用

```java
private void invokeAwareMethods(final String beanName, final Object bean) {
		if (bean instanceof Aware) {
			if (bean instanceof BeanNameAware) {
				((BeanNameAware) bean).setBeanName(beanName);
			}
			if (bean instanceof BeanClassLoaderAware) {
				((BeanClassLoaderAware) bean).setBeanClassLoader(getBeanClassLoader());
			}
			if (bean instanceof BeanFactoryAware) {
				((BeanFactoryAware) bean).setBeanFactory(AbstractAutowireCapableBeanFactory.this);
			}
		}
	}
```

8.5.2 处理BeanPostProcessor的接口实现的前置处理，`applyBeanPostProcessorsBeforeInitialization`方法

8.5.3 调用afterPropertiesSet方法及定义的initMethods方法， `AbstractAutowireCapableBeanFactory#invokeInitMethods`

8.5.4 BeanPostProcessor接口实现的后置处理 `applyBeanPostProcessorsAfterInitialization`方法

<br>

9.注册销毁方法 ` DisposableBean.destroy`及自定义的 destroyMethod

<br>

10.返回最终创建的bean实例，创建结束



