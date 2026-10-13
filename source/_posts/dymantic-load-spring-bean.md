---
title: 一种动态添加外部Jar包中SpringBean的方式
date: 2021-04-16 22:26:48
tags: [java, spring]
---

我们在日常写代码的过程中，经常会有一个扩展点接口，同时会有多种实现，类似策略模式，在运行时动态获取具体的实现。

如果想在不需要重新部署项目的情况下，新增一种扩展点的实现并且能够生效使用，有什么方式呢？

先想个简单的例子来说明一下上面说的场景，比如价格计算。定义一个扩展点接口：

```java
public interface PriceCalculator {
    BigDecimal calc(GoodsDetail detail);
}
```

这是应用内置的一种策略：

```java
@Service
public class DirectReducePriceCalculator implements PriceCalculator {

    @Resource
    private ActivityService activityService;

    @Override
    public BigDecimal calc(GoodsDetail detail) {
        // 随便写的，只是为了稍微贴近一点实际~~~~
        Activity activity = activityService.getDirectReduceActivity(detail);
        if (activity != null) {
            return detail.getPrice().subtract(activity.getReducePrice());
        }
        return detail.getPrice();
    }
}
```

以及一个用于获取策略实例的工厂类：

```java
@Component
public class PriceCalculatorFactory implements ApplicationContextAware {

    private ApplicationContext applicationContext;

    private Map<String, PriceCalculator> priceCalculatorMap = new HashMap<>();

    @PostConstruct
    public void init() {
        priceCalculatorMap.putAll(applicationContext.getBeansOfType(PriceCalculator.class));
    }

    public PriceCalculator getPriceCalculatorByName(String name) {
        return priceCalculatorMap.get(name);
    }

    @Override
    public void setApplicationContext(ApplicationContext applicationContext) throws BeansException {
        this.applicationContext = applicationContext;
    }
}
```

这时候问题来了：**要添加或更新一个外部 jar 包中定义的 bean（比如一种新的计算策略）到当前应用，要如何做呢？** 假设外部 jar 包中定义如下：

```java
@Service
public class XyPriceCalculator implements PriceCalculator {

    @Resource
    private ActivityService activityService;

    @Override
    public BigDecimal calc(GoodsDetail detail) {
        // 外部 jar 中的新策略实现
        return detail.getPrice().multiply(new BigDecimal("0.9"));
    }
}
```

这篇文章就围绕这个问题展开。整体思路不难，但牵扯到类加载机制和 Spring 父子上下文的一些细节。我会把原理拆开讲透，最后给出一个带**更新和卸载能力**的生产可用版本。

## 核心思路：三块拼图

这个问题的解法由三块拼图组成，缺一不可：

1. **自定义类加载器** —— 解决"同名类无法更新"。类一旦被某个类加载器加载就不可替换，但每次刷新新建一个类加载器，就能以全新的"类身份"重新读取磁盘上的新版本。
2. **子上下文 + 父上下文回退** —— 解决"外部 bean 的归属与依赖"。外部 bean 放进一个独立的子 Spring 容器，容器里找不到的依赖（比如 `ActivityService`）会自动向上回退到当前应用上下文查找。
3. **类加载器的传递** —— 解决"Spring 如何发现并加载外部类"。Spring 类路径扫描默认从线程上下文类加载器取类加载器，也可以显式给子上下文指定类加载器。

三者关系如图：

```text
           当前应用（应用类加载器）
                  │  getBean（找不到时向上回退）/ getBeansOfType
                  ▼
         PriceCalculatorFactory
                  ▲  refresh() 时整体替换策略集合
                  │
         子 ApplicationContext   ← 父上下文 = 当前应用上下文（依赖回退）
                  ▲  显式 setClassLoader
                  │
         CustomizeClassLoader   ← 每次 refresh 新建，重新读取外部 jar
                  ▲
                  │
           external-plugin.jar
```

> 为什么不直接把外部 bean 注册进主上下文？主上下文 refresh 之后无法再对新增包做类路径扫描；用 `registerBeanDefinition` 手工注册虽然可行，但类仍然由应用类加载器加载，同名类的更新/卸载依旧无法实现。子上下文的价值一是托管外部 bean 的**完整生命周期**（创建、销毁回调），二是**容器隔离**让新旧版本的同名类可以并存。

<!-- more -->

## 前置知识：类加载隔离机制

要理解为什么"新建一个类加载器就能更新"，必须先理解 JVM 对"类"的管理方式。

### 类身份 = 全限定类名 + 定义它的类加载器

同一份字节码，被两个不同的类加载器各加载一次，就是**两个不同的类**。JVM 对"已加载的类"只保留引用，**没有卸载接口，也无法替换**。

由此得出两个推论：

- **为什么同名类更新不了？** 因为类一旦被某个加载器（比如应用类加载器）加载，就永远是它。即使磁盘上的 jar 换了内容，JVM 也不会重新读取。
- **为什么"每次 new 一个类加载器"就行？** 因为新加载器 = 新的类身份。它从磁盘重新读取字节码，得到的是全新的一批类；旧类只属于旧加载器，互不干扰。这就是热更新能成立的根本原因。

### 双亲委派：向"上"问，不向"下"看

默认的类加载模型（双亲委派）里，加载一个类时先交给父加载器：引导类加载器 → 扩展类加载器 → 应用类加载器 → 自定义类加载器。好处是核心类（`java.*`、`org.springframework.*`）全局只有一份，避免重复加载。

这个模型有两个隐含结论，是本方案的关键：

1. **子加载器能看到父加载器加载的类。** 外部 jar 里的 `XyPriceCalculator` 引用 `PriceCalculator`、`ActivityService` 时，会优先由父（应用）加载器解析出**应用里已经加载的那份**。于是外部类实现的接口、注入的依赖和应用是**同一个类身份**——这是后面 `getBeansOfType` 能匹配、`@Resource` 能注入的前提。
2. **父加载器看不到子加载器的类（单向可见性）。** Spring 是"父"这一侧的代码，正常情况根本扫描不到外部 jar 里的类。这就要用到线程上下文类加载器了。

### 单向可见性 + 线程上下文类加载器（TCCL）

"父看不到子"在双亲委派里是设计如此，不是缺陷。真正的问题场景是：**位于委派链高层的框架代码，需要加载位于应用层的实现类**——方向是"向下"，而委派是"向上问"。

经典案例正是 JDBC：`java.sql.DriverManager` 由引导类加载器加载，第三方数据库驱动（MySQL、ojdbc）却在应用 classpath 上，普通委派根本看不到。于是 JDK 1.2 引入了**线程上下文类加载器（Thread Context ClassLoader，简称 TCCL）**——一个线程级的 `ClassLoader` 槽位，配合一条约定："加载跟当前执行上下文相关的实现类时，先从线程的上下文类加载器里取一个来用。"

到了 JDBC 4.0 / Java 6，驱动发现改成了 SPI（`META-INF/services` + `ServiceLoader`），而 `ServiceLoader.load(Class)` 无参版本的第一行就是取 TCCL——**SPI 是发现机制，TCCL 是它默认使用的类加载器**，两者是叠加关系，不是二选一。

Spring 也是这套约定的执行者：`ClassUtils.getDefaultClassLoader()` 优先取线程上下文类加载器（见下文源码），类路径扫描、反射创建 bean 都从这里出发。所以只要把自定义类加载器放到线程上下文里（或显式交给子上下文），Spring 就能"顺着"它找到外部 jar 里的类。

### 两个必须记住的失败模式

1. **外部 jar 自带 Spring / 接口副本**（shade 打包常见）：`PriceCalculator`、`@Service` 这些类被 jar"晒"了一份 → 同全限定名、两个类身份 → `getBeansOfType` 匹配不上、运行时 `ClassCastException`。**约定：外部 jar 只允许依赖，不允许自带这些类。**
2. **同名类已经在应用 classpath 上**：由于父优先委派，新 jar 里的类永远不会被加载，更新静默失效。**约定：外部 jar 的类不得存在于应用 classpath。**

## 逐步实现

### Step 1：自定义类加载器

因为可能更新，同名的类无法在同一个加载器里被替换，所以需要一个自定义类加载器，我们定义一个继承 `URLClassLoader` 的类加载器：

```java
public class CustomizeClassLoader extends URLClassLoader {

    public CustomizeClassLoader() {
        // 不指定父加载器，默认父加载器是系统（应用）类加载器。
        // 注意父优先委托：外部 jar 中的类必须不在应用 classpath 上，
        // 否则会被父加载器"抢走"，更新永远不会生效（见"失败模式 2"）。
        super(new URL[0]);
    }

    public void addFile(File file) {
        try {
            addURL(file.getCanonicalFile().toURI().toURL());
        } catch (IOException e) {
            throw new IllegalStateException("添加 jar 失败: " + file, e);
        }
    }
}
```

### Step 2：加载外部 jar 中的 class

```java
CustomizeClassLoader classLoader = new CustomizeClassLoader();
classLoader.addFile(new File("xx/yy/cc.jar"));
```

到这里我们只是把 class 加载进 JVM，它还不是 Spring 容器中的 bean，还需要初始化它。

### Step 3：创建子上下文：用「父上下文回退」解决跨容器依赖

外部 jar 中定义的类可能还依赖当前项目中的 bean（比如 `ActivityService`），所以不能简单 new 一个对象了事，需要一个"能找到依赖"的容器。

做法：**创建一个子 `ApplicationContext`，把当前应用上下文设置为它的父上下文。** Spring 容器在 `getBean()` 找不到 bean 时会向上回退到父容器查找——外部 bean 的 `@Resource` / `@Autowired` 依赖就能顺利在父容器里解析。

这里有一个高频笔误要提醒：是 `newContext.setParent(applicationContext)`，**不是** `newContext.setParent(newContext)`。把子上下文设成它自己当父容器，依赖解析会向上递归到自己，直接 `StackOverflowError`。

### Step 4：让 Spring 用上自定义类加载器

#### 方式一：设置线程上下文类加载器（原始做法）

上一节讲过，Spring 类路径扫描默认从线程上下文类加载器取类加载器，所以可以把自定义加载器放进当前线程：

```java
Thread.currentThread().setContextClassLoader(classLoader);
```

对应的 Spring 源码调用链（基于 Spring 5.x）如下：

```text
ClassPathBeanDefinitionScanner#scan
 └─ ClassPathBeanDefinitionScanner#doScan
     └─ ClassPathScanningCandidateComponentProvider#findCandidateComponents
         └─ ClassPathScanningCandidateComponentProvider#scanCandidateComponents
             Resource[] resources = getResourcePatternResolver().getResources(packageSearchPath);
             └─ getResourcePatternResolver()
                 └─ new PathMatchingResourcePatternResolver()
                     └─ new DefaultResourceLoader()
                         └─ ClassUtils.getDefaultClassLoader();   // ← 优先取线程上下文类加载器
```

`ClassUtils.getDefaultClassLoader()` 的逻辑就是 TCCL 第一优先、逐级回退：

```java
// ClassUtils.java (Spring 5.x)
public static ClassLoader getDefaultClassLoader() {
    ClassLoader cl = null;
    try {
        cl = Thread.currentThread().getContextClassLoader(); // 第一优先级：线程上下文类加载器
    } catch (Throwable ex) {
        // Cannot access thread context ClassLoader - falling back...
    }
    if (cl == null) {
        cl = ClassUtils.class.getClassLoader();              // 回退 1：Spring 自己的类加载器
        if (cl == null) {
            try {
                cl = ClassLoader.getSystemClassLoader();     // 回退 2：系统类加载器
            } catch (Throwable ex) {
                // Cannot access system ClassLoader - oh well, maybe the caller can live with null...
            }
        }
    }
    return cl;
}
```

两条注意事项：

- 上面这条调用链是"未显式指定 ResourceLoader"时的路径；在 `AnnotationConfigApplicationContext.scan()` 里，扫描器构造时传入的 resourceLoader 是上下文本身，最后仍会落到上下文的 `getClassLoader()`——未显式设置时同样是 `ClassUtils.getDefaultClassLoader()`，结论一致。
- 在无 resourceLoader 路径下，`new DefaultResourceLoader()` 会把 `ClassUtils.getDefaultClassLoader()` 的结果**在构造时缓存**下来。也就是说"先设置 TCCL、再创建扫描相关对象"的顺序很关键，反了就会扫描不到外部类。这个时序依赖很脆，所以最终实现建议用下面的方式二。

#### 方式二：显式 setClassLoader（推荐）

把类加载器直接交给子上下文，不依赖线程全局状态：

```java
newContext.setClassLoader(classLoader);
```

既没有 TCCL 时序问题，也不污染线程，还省掉一个 try/finally 恢复的负担。TCCL 的知识保留下来用于理解原理，实现上只解释、不承载。

### Step 5：完整可运行的刷新代码

先给一个"最小可用版"，用于理解思路：

```java
public void refresh() {
    // 1. 每次刷新都新建类加载器并加载外部 jar（新加载器 = 新类身份，同名类可重新加载）
    CustomizeClassLoader classLoader = new CustomizeClassLoader();
    classLoader.addFile(new File("xx/yy/cc.jar"));

    // 2. 备份并设置线程上下文类加载器
    ClassLoader oldClassLoader = Thread.currentThread().getContextClassLoader();
    Thread.currentThread().setContextClassLoader(classLoader);
    try {
        // 3. 创建子上下文，把当前应用上下文设为父上下文（外部 bean 的依赖向上回退解析）
        AnnotationConfigApplicationContext newContext = new AnnotationConfigApplicationContext();
        newContext.setParent(applicationContext);   // ← 注意是 applicationContext，不是 newContext 本身
        newContext.scan("xxx.yyy");
        newContext.refresh();

        // 4. 注意：子上下文的 getBeansOfType 只会返回它自己创建的 bean，取不到父容器中的 bean
        Map<String, PriceCalculator> newMap = newContext.getBeansOfType(PriceCalculator.class);
        if (!newMap.isEmpty()) {
            priceCalculatorMap.putAll(newMap);
        }
    } finally {
        // 5. 无论成败都恢复 TCCL，避免污染当前线程
        Thread.currentThread().setContextClassLoader(oldClassLoader);
    }
}
```

这个版本能跑通基本场景，但作为生产方案还有三个隐患：

1. **依赖 TCCL 时序**，已被方式二替代；
2. **旧资源不回收**：子上下文、旧类加载器、旧 bean 从不关闭，每次刷新都泄漏一份；被删掉的策略也永远留在 map 里；
3. **线程不安全**：裸 `HashMap` 在并发读写下有风险，刷新和读取可能交错。

把它们一起修掉，就是最终版：

```java
@Component
public class PriceCalculatorFactory implements ApplicationContextAware {

    private ApplicationContext applicationContext;

    /** 应用自身内置的实现，刷新时作为基础保留 */
    private final Map<String, PriceCalculator> builtInMap = new HashMap<>();

    /**
     * 当前生效的策略集合（内置实现 + 外部实现）。
     * volatile + 整体替换：读取方不加锁也能拿到某一完整版本，不会看到半新半旧。
     */
    private volatile Map<String, PriceCalculator> priceCalculatorMap = Collections.emptyMap();

    /** 当前生效的子上下文与类加载器 */
    private AnnotationConfigApplicationContext pluginContext;
    private CustomizeClassLoader pluginClassLoader;

    @PostConstruct
    public void init() {
        builtInMap.putAll(applicationContext.getBeansOfType(PriceCalculator.class));
        priceCalculatorMap = new HashMap<>(builtInMap);
    }

    public PriceCalculator getPriceCalculatorByName(String name) {
        return priceCalculatorMap.get(name);
    }

    @Override
    public void setApplicationContext(ApplicationContext applicationContext) throws BeansException {
        this.applicationContext = applicationContext;
    }

    /**
     * 动态加载 / 更新 / 卸载外部 jar 中的策略实现。
     * 整体采用「先新后旧」：新版本全部就绪并对外可见后，才释放旧资源；失败自动回滚到旧版本。
     */
    public synchronized void refresh(String jarPath, String scanPackage) {
        AnnotationConfigApplicationContext newContext = null;
        CustomizeClassLoader newClassLoader = null;
        try {
            // 1. 新建类加载器并加载外部 jar（每次刷新都是全新的类身份）
            newClassLoader = new CustomizeClassLoader();
            newClassLoader.addFile(new File(jarPath));

            // 2. 创建子上下文：父上下文回退依赖 + 显式指定类加载器
            newContext = new AnnotationConfigApplicationContext();
            newContext.setParent(applicationContext);
            newContext.setClassLoader(newClassLoader);
            newContext.scan(scanPackage);
            newContext.refresh();

            // 3. 新的策略集合 = 内置实现 + 新的外部实现，全部就绪后一次性对外可见。
            //    子上下文的 getBeansOfType 只返回它自己创建的 bean（取不到父容器中的 bean）。
            Map<String, PriceCalculator> newMap = new HashMap<>(builtInMap);
            newMap.putAll(newContext.getBeansOfType(PriceCalculator.class));
            priceCalculatorMap = newMap;

            // 4. 新版本生效后再释放旧资源：
            //    关旧子上下文（销毁单例、触发 @PreDestroy），关旧类加载器（释放 jar 文件句柄）。
            closeOldResources();

            pluginContext = newContext;
            pluginClassLoader = newClassLoader;
            newContext = null;
            newClassLoader = null;
        } catch (Exception e) {
            // 刷新失败：关闭半成品，旧版本继续生效
            if (newContext != null) {
                newContext.close();
            }
            closeQuietly(newClassLoader);
            throw new IllegalStateException("外部 jar 刷新失败，已回滚到旧版本", e);
        }
    }

    private void closeOldResources() {
        if (pluginContext != null) {
            pluginContext.close();
            pluginContext = null;
        }
        closeQuietly(pluginClassLoader);
        pluginClassLoader = null;
    }

    private void closeQuietly(CustomizeClassLoader classLoader) {
        if (classLoader == null) {
            return;
        }
        try {
            classLoader.close();
        } catch (IOException ignored) {
            // 释放 jar 文件句柄失败不阻断主流程
        }
    }
}
```

几个关键点再强调一下：

- `synchronized` 保证同时只有一个刷新在跑；`priceCalculatorMap` 用 **volatile + 整体替换**，刷新期间的读取永远拿到完整旧版或完整新版，不需要加锁。
- **先新后旧 + 失败回滚**：新上下文创建成功、对外可见之后才释放旧资源；`refresh` 抛异常时旧版本原封不动。
- `pluginContext.close()` 销毁子容器单例（触发 `@PreDestroy` 等销毁回调）；`pluginClassLoader.close()` 释放 jar 文件句柄——**Windows 上不关的话 jar 文件会被锁住，导致无法覆盖或删除**。

## Spring 父子上下文机制：几个容易误解的点

用子上下文方案之前，有几条容器行为值得讲清楚，否则排查问题时会走弯路：

1. **只有 `getBean()` 会向父容器回退，`getBeansOfType()` / `getBeanNamesForType()` 不回退。** 所以外部 bean 的依赖注入能靠父上下文解决，但"按类型枚举外部 bean"必须在子上下文里做——这正是代码里 `newContext.getBeansOfType(...)` 的原因。
2. **父子上下文是两个完全独立的容器。** 各自持有独立的 BeanFactory、单例池、BeanPostProcessor、事件广播器。子上下文发布的事件不会自动广播到父上下文；**父容器注册的切面增强（`@Transactional`、`@Async`、自定义 AOP）也不作用于子上下文创建的 bean**。如果外部 bean 需要事务/异步能力，需要在子上下文中另行配置。
3. **`close()` 是"卸载"的正规入口。** 子上下文 `close()` 销毁容器内所有单例，触发 `@PreDestroy`、`DisposableBean`、`destroy-method`。只 `new` 不 `close`，这些销毁回调永远不会执行，容器、bean、类加载器全部泄漏。
4. **bean 身份一致性依赖"接口由谁加载"。** 外部 bean 能被识别成 `PriceCalculator`，是因为双亲委派让外部 jar 里的实现类拿到的接口和应用是同一个类身份。一旦破坏这个前提（自带副本），一切类型匹配都会失效。

## 动态更新与卸载

### 更新：jar 覆盖 → 新类加载器重读 → 原子替换

更新不需要"修改已加载的类"。流程是：

```text
旧 jar(v1) ──> 旧类加载器 ──> 类A1 + bean1      （当前生效）
    │ 用 v2 覆盖 jar 文件
新 jar(v2) ──> 新类加载器重读磁盘 ──> 类A2 + bean2   （新的类身份）
```

调用 `refresh()` 即可切换到新实现。两点提醒：

- **接口不能演进**：`PriceCalculator` 由应用 classpath 加载，接口加方法或改签名需要应用一起重部署。
- **业务方不要长期持有旧实例**：`close()` 销毁的是容器注册表和触发销毁回调；已经用 `getPriceCalculatorByName()` 拿走的旧对象仍可继续被调用。约定业务代码每次需要时从工厂取实例，不要缓存。

### 卸载：Java 不能显式卸载类

这是最容易误解的一点：**Java 没有 `Class.unload()`**。类元数据（JDK 8+ 存放于 Metaspace）被回收的唯一条件是——**定义它的类加载器成为不可达**，且等到 GC 真正到点。所以"卸载" = 主动切断所有指向旧加载器的强引用：

| 强引用来源 | 切断方式 |
| --- | --- |
| 工厂 map 里的旧 bean | 整体替换 `priceCalculatorMap = newMap`（旧 map 连同 bean 一起脱离引用） |
| 旧子上下文单例池 | `pluginContext.close()`（触发 `@PreDestroy`） |
| 旧类加载器持有的 jar 文件句柄 | `pluginClassLoader.close()`（Windows 上必须，否则文件被锁） |
| 线程上下文类加载器残留 | 采用 `setClassLoader` 方案后不再有；若用 TCCL 方案务必 try/finally 恢复 |
| 外部 bean 自己写出去的引用 | ThreadLocal、静态集合、事件监听器——无法自动追踪，靠代码约定审查 |
| 正在执行的调用栈 | 无需处理，请求结束自动释放 |

验证卸载的手段（任选其一）：

- `jmap -clstats <pid>` 或 `jcmd <pid> GC.class_stats`：观察类加载器与类的数量是否只增不减；
- 启动参数 `-XX:+TraceClassUnloading`：输出类被回收的日志；
- 频繁热更的场景关注 `-XX:MaxMetaspaceSize`：单次刷新会产生一批新类元数据，要等后续 GC 才回收，高频刷新会让元空间增长、GC 压力上升。

## 局限与替代方案

| 局限 / 约束 | 说明 |
| --- | --- |
| 接口不能演进 | 接口由应用 classpath 加载，改接口仍需应用重部署 |
| 切面不跨容器 | 父容器的 `@Transactional` / `@Async` 等增强不作用于子上下文 bean |
| 外部 jar 有硬性要求 | 不得自带 Spring / 接口副本；类不得出现在应用 classpath |
| 安全风险 | 加载不可信 jar 等于在本进程执行任意代码，务必校验来源 |
| 元空间压力 | 高频热更制造大量待回收的类元数据 |

替代方案视场景选择：

- **SPI 思路**（`META-INF/services` + `ServiceLoader`）：外部 jar 里以 SPI 方式注册 `PriceCalculator` 的实现，配合 TCCL（或显式 `ServiceLoader.load(clazz, classLoader)`），可以避开子上下文及其生命周期问题。本文讨论的 TCCL 知识在这里同样适用——`ServiceLoader.load(Class)` 无参版本正是从 TCCL 取类加载器的。
- **OSGi**：把类的版本管理、依赖解析、自动卸载做得最彻底，代价是引入整套容器。
- **成熟插件框架**：如 PF4J，社区方案更省心。
- **可接受重启**：直接 `ServiceLoader` + 重启部署，最简单可靠。

## 小结

本文从"想不重启就增加一个扩展点实现"这个需求出发，拆解了三块拼图：自定义类加载器解决"同名类更新"，子上下文 + 父上下文回退解决"外部 bean 的归属和依赖"，类加载器传递（TCCL 的原理 + 显式 `setClassLoader` 的实现）解决"Spring 如何发现外部类"。最后补上了生命周期管理（先新后旧、卸载与清理）和适用边界，算是一个自洽可用的完整方案，抛砖引玉。

如果你在动态加载外部 bean 上踩过坑，或者有更好的方案，欢迎提出指正，谢谢。