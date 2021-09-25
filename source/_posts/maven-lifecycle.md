---
title: maven生命周期与插件笔记
date: 2021-09-25 22:24:06
tags: [java, maven]
---

工作中大部分Java项目都是基于maven来进行项目的构建等工作，但是对于maven这个高频用到的工具其实了解程度还不够，下面主要是学习《Maven实战》中记录的关于生命周期与插件相关的笔记

## maven生命周期与插件

maven的生命周期是从大量项目和构建工作中总结抽象出来的对所有构建过程进行的抽象和统一，这个生命周期包含了项目的清理、初始化、编译、测试、打包、集成测试、验证、部署和站点生成等几乎所有构建步骤

虽然maven抽象出了生命周期的概念，但是它并没有对相关的功能进行实现，就像它是负责定义了接口，但是具体实现是由插件来完成，这样可以很好的保证自身的轻量和扩展性

<!-- more -->

而对于maven插件，还有个插件目标的概念，就是可以认为一个插件本身是可以提供很多种功能的，一种功能就是一个插件目标，比如对于 maven-dependency-plugin 这个插件，我们通过执行`mvn dependency:help`可以看到它有21个插件目标，截取部分内容如下，其中就包含我们平时分析依赖使用的`mvn dependency:tree`（其中冒号前面是插件前缀，冒号后面是该插件的目标）

```
[INFO] --- maven-dependency-plugin:2.8:help (default-cli) @ maven-code ---
[INFO] Maven Dependency Plugin 2.8
  Provides utility goals to work with dependencies like copying, unpacking,
  analyzing, resolving and many more.

This plugin has 21 goals:

dependency:analyze
  Analyzes the dependencies of XXX(已省略)

dependency:analyze-dep-mgt
  This mojo looks at the dependencies after final resolution XXX(已省略)
```



### maven插件绑定

平时我们执行的`mvn clean` 、`mvn compile` 、`mvn package`等等其实都是在调用maven的生命周期阶段，而这些生命周期又与插件进行绑定，执行插件的目标来完成功能，在执行后的命令行输出中可以看到执行的插件目标

maven已经预置了常用的一些绑定配置

| 声明周期阶段 | 插件目标                      |
| ------------ | ----------------------------- |
| compile      | maven-compiler-plugin:compile |
| test         | maven-surefire-plugin:test    |
| package      | maven-jar-plugin:jar          |
| install      | maven-install-plugin:install  |
| deploy       | maven-deploy-plugin:deploy    |



### 自定义绑定

如果我们想将某个插件目标绑定到生命周期上，可以在文件中自行配置，如想配置在compile阶段就生成源码包：

```xml
<!-- pom.xml -->
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-source-plugin</artifactId>
    <version>2.2.1</version>
    <executions>
        <execution>
            <id>attach-sources</id>
            <!-- 插件目标要绑定的生命周期阶段，这里指定compile阶段 -->
            <phase>compile</phase>
            <goals>
                <!-- 这里指定要执行的插件目标， jar-no-fork目标负责将源码打成jar包 -->
                <goal>jar-no-fork</goal>
            </goals>
        </execution>
    </executions>
</plugin>
```

这样在执行`mvn compile`的时候就会发现源码包自动生成在target目录下

可以通过`mvn help:describe -Dplugin=org.apache.maven.plugins:maven-source-plugin:2.2.1 -Ddetail`查看插件信息，其中包含插件目标默认绑定的生命周期阶段



## 编写maven插件

### 创建插件

对于一些特殊场景，我们可以编写自己的maven插件

```shell
# 通过maven插件骨架创建项目（也可以通过idea等选择后创建）
mvn archetype:generate \
    -DarchetypeGroupId=org.apache.maven.archetypes \
    -DarchetypeArtifactId=maven-archetype-plugin
```

创建项目后会生成一些样例代码，主要有一个核心代码`MyMojo.java`

```java
// 这是一个生成一个固定文件(touch.txt)到指定目录的插件
// 必须继承 AbstractMojo， @Mojob注解中的name就是插件目标名称，defaultPhase为默认执行阶段
@Mojo(name = "touchA", defaultPhase = LifecyclePhase.COMPILE)
public class MyMojo extends AbstractMojo {
    /**
     * 输出路径目录
     */
    @Parameter(defaultValue = "${project.build.directory}", property = "outputDir", required = true)
    private File outputDirectory;

    public void execute() throws MojoExecutionException {
        // 正常的业务逻辑，这里是写文件
        File f = outputDirectory;
        if (!f.exists()) {
            f.mkdirs();
        }
        File touch = new File(f, "touch.txt");
        FileWriter w = null;
        try {
            w = new FileWriter(touch);
            w.write("touch.txt");
        } catch (IOException e) {
            throw new MojoExecutionException("Error creating file " + touch, e);
        } finally {
            if (w != null) {
                try {
                    w.close();
                } catch (IOException e) {
                    // ignore
                }
            }
        }
    }
}
```

之后执行`mvn install`即可安装到本地

### 自定义插件使用

在项目中引入对应插件

```xml
<plugin>
    <groupId>org.example</groupId>
    <artifactId>maven-plugin-demo</artifactId>
    <version>1.0-SNAPSHOT</version>
</plugin>
```

之后在命令行中执行`mvn org.example:maven-plugin-demo:1.0-SNAPSHOT:touchA`即可在target目录下发现创建的touch.txt文件
