---
title: Java-Agent
date: 2023-05-27 15:36:50
tags: [java, agent]
---

在介绍Java agent之前，我们先来介绍一下一个比较关键的概念 - 字节码，这个如果大家已经比较熟悉了，可以直接跳到 java agent部分

### 字节码

我们知道Java编写的程序是可以不做任何修改的在不同的操作系统上面运行，也就是跨平台的，但是要想实现跨平台，就是需要能屏蔽掉不同操作系统之间api等的差异

比如说常见的创建线程，linux和window系统提供的接口就不一样

```c
// 不同操作系统下，使用c语言创建线程
// linux
int pthread_create(pthread_t *thread, const pthread_attr_t *attr,     
                   void *(*start_routine) (void*), void *arg);

// windows
HANDLE CreateThread(
  LPSECURITY_ATTRIBUTES   lpThreadAttributes,
  SIZE_T                  dwStackSize,
  LPTHREAD_START_ROUTINE  lpStartAddress,
  LPVOID                  lpParameter,
  DWORD                   dwCreationFlags,
  LPDWORD                 lpThreadId
);
```

除了创建线程，其实还有很多的差异，比如说如果用C语言来实现既能在windows下运行，又能在linux下指定的代码，那么就需要针对有差异的地方，根据不同的操作系统来编写不同的代码，然后在编译的时候根据需要编译成对应系统下的二进制指令，这无疑是很痛苦和低效的方式

而Java下的实现方式是不执行生成最终平台的二进制文件，而是针对不同平台提供对应的不同下的虚拟机，由虚拟机来负责程序的执行，这样自然的操作系统的差异就需要由虚拟机来屏蔽

<img src="/images/jvm-class.png" style="zoom:60%" />

但是既然是虚拟机，那也必然会有对应的执行指令，这个指令就是字节码，我们只需要将源代码编译成字节码（而不是操作系统下的二进制格式），那么虚拟机就能识别进行执行了

其实这样还有一个额外的好处，那就是在Java虚拟机上，不仅仅只能支持Java语言，理论上只要是符合规范的字节码文件，它都能执行，至于这个字节码文件是Java语言编译过来的，还是其他语言（如kotlin, groovy）编译过来的并不重要，甚至我们都可以手写字节码来执行～

<!-- more -->

上面的概念说完了，下面我们来具体编写代码来感受一下字节码

```java
// 先来编写一个类，主要有一个 incr方法，对参数进行加一返回
package com.zavier.agent;
public class Test {
    public static void main(String[] args) {
        final Test test = new Test();
        final int incr = test.incr(5);
        // 很明显会输出 6
        System.out.println(incr);
    }

    public int incr(int i) {
        return i + 1;
    }
}
```

那么对应的字节码如何查看呢，就是看它编译后的文件以.class结尾的文件`Test.class`，这个文件怎么查看呢，一种就是直接以二进制的方式打开，当然，这个根据是无法进行阅读的，我贴出来一部分感受一下

```shell
➜  hexdump -C Test.class
00000000  ca fe ba be 00 00 00 34  00 28 0a 00 07 00 1a 07  |.......4.(......|
00000010  00 1b 0a 00 02 00 1a 0a  00 02 00 1c 09 00 1d 00  |................|
00000020  1e 0a 00 1f 00 20 07 00  21 01 00 06 3c 69 6e 69  |..... ..!...<ini|
00000030  74 3e 01 00 03 28 29 56  01 00 04 43 6f 64 65 01  |t>...()V...Code.|
00000040  00 0f 4c 69 6e 65 4e 75  6d 62 65 72 54 61 62 6c  |..LineNumberTabl|
00000050  65 01 00 12 4c 6f 63 61  6c 56 61 72 69 61 62 6c  |e...LocalVariabl|
00000060  65 54 61 62 6c 65 01 00  04 74 68 69 73 01 00 17  |eTable...this...|
00000070  4c 63 6f 6d 2f 7a 61 76  69 65 72 2f 61 67 65 6e  |Lcom/zavier/agen|
00000080  74 2f 54 65 73 74 3b 01  00 04 6d 61 69 6e 01 00  |t/Test;...main..|
```

幸运的是JDK提供了一个反编译字节码的工具 javap，具体内容比较多，这里我贴一下 incr 方法对应的字节码大家看一下

```shell
➜  javap -v Test         
# 忽略其他部分，大家有兴趣可以自己试一下
public int incr(int);
  descriptor: (I)I
  flags: ACC_PUBLIC
  # code部分是对应方法的内容
  Code:
    # 操作数栈有2个元素位，局部变量表有2个元素位，参数有2个（其中一个参数是 this ）
    stack=2, locals=2, args_size=2
       0: iload_1     # 将第一个int类型的本地变量推送到操作数栈顶
       1: iconst_1    # 将 int类型数字 1 推送到操作数栈顶
       2: iadd        # 弹出栈顶两个int类型的数值，相加后将结果压入栈顶
       3: ireturn     # 从当前方法返回 int
    LineNumberTable:
      line 13: 0
    LocalVariableTable:
      Start  Length  Slot  Name   Signature
          0       4     0  this   Lcom/zavier/agent/Test;
          0       4     1     i   I

SourceFile: "Test.java"

```

以上方法的字节码还是比较好理解的，这时候想一下，如果我们将 `iconst_1`改成`iconst_2`，那么在运行这个文件，是不是就会变成了加二的操作呢？我们可以来试一下

字节码文件是有它自己的规范的，我们随便改可能会导致加载异常，而且手动找到对应命令进行修改也确实是一个很麻烦的事情，这时候就需要使用一个工具类来完成了，可选的有很多，比如asm, cglib, javassist, bytebuddy等

这里使用asm9来实现一下功能

```java
public class Transformer {

    static class MyClassVisitor extends ClassVisitor {
        public MyClassVisitor(int i, ClassWriter cw) {
            super(i, cw);
        }

        @Override
        public MethodVisitor visitMethod(int access, String name, String desc, String signature, String[] exceptions) {
            MethodVisitor mv = super.visitMethod(access, name, desc, signature, exceptions);
            // 查找方法，名称为 incr， (I)I 表示参数类型为一个int,返回类型也为int
            if (name.equals("incr") && desc.equals("(I)I")) {
                return new MyMethodVisitor(Opcodes.ASM9, mv);
            } else {
                return mv;
            }
        }
    }

    static class MyMethodVisitor extends MethodVisitor {
        public MyMethodVisitor(int api, MethodVisitor methodVisitor) {
            super(api, methodVisitor);
        }

        @Override
        public void visitInsn(int opcode) {
            if (opcode == Opcodes.ICONST_1) {
                // 如果指定是ICONST_1，则改为 ICONST_2
                super.visitInsn(Opcodes.ICONST_2);
            } else {
                super.visitInsn(opcode);
            }
        }

    }
    
    
    public static void main(String[] args) throws IOException {
        ClassReader cr = new ClassReader(new FileInputStream("/path/Test.class"));
        ClassWriter cw = new ClassWriter(cr, 0);
        ClassVisitor cv = new MyClassVisitor(Opcodes.ASM9, cw);
        cr.accept(cv, 0);

        byte[] bytes = cw.toByteArray();  // 修改后的字节码

        final FileOutputStream fileOutputStream = new FileOutputStream("/path/Test.class");
        fileOutputStream.write(bytes);
        fileOutputStream.close();
    }
}
```

这时候我们再使用javap看一下替换后的字节码内容，可以发现已经替换成功了

```shell
public int incr(int);
  descriptor: (I)I
  flags: ACC_PUBLIC
  Code:
    stack=2, locals=2, args_size=2
       0: iload_1
       1: iconst_2  # 这里已经替换成了 iconst_2
       2: iadd
       3: ireturn
    LineNumberTable:
      line 13: 0
    LocalVariableTable:
      Start  Length  Slot  Name   Signature
          0       4     0  this   Lcom/zavier/agent/Test;
          0       4     1     i   I
```

这时候我们再运行一下代码

```shell
➜ java com.zavier.agent.Test
# 可以看到main方法运行的结果已经由6变成了7
7
```

到这里字节码部分就介绍完了，大家主要记住 字节码是JVM运行的关键就可以了，我们甚至可以通过修改字节码实现源代码中没有的功能

### JavaAgent

现在我们开始介绍一下java-agent技术，那么java-agent是做什么的呢？简单理解就是jvm提供的可以在运行时修改字节码的力，利用这种能力可以用来记录请求链路（如skywalking等）或者录制流量等

#### 方法声明

javaagent使用有两种方式，一种是在jvm启动的时候直接指定agent, 还有一种是在运行时动态挂载agent

先看一下启动时指定的写法，它需要声明实现如下的方法

```java
public static void premain(String args, Instrumentation instrumentation)
```

如果是动态挂载的方式，则需要声明实现另一个方法

```java
public static void agentmain(String agentArgs, Instrumentation inst)
```

#### 打包配置

同时，不管使用哪种方式，都需要增加一下如下打包的配置

1. 打包时需要将依赖一起打包
2. 打的包中的 META-INF目录下的MANIFEST.MF文件中增加如下配置：

```shell
# MANIFEST.MF文件
# 动态挂载时使用的agent的入口类方法，也就是实现agentmain方法的类
Agent-Class: com.zavier.agent.Agent
# 是否允许重新定义类
Can-Redefine-Classes: true
# 是否允许转换类
Can-Retransform-Classes: true
# 启动时使用的agent的入口类方法，也就是实现premain方法的类
Premain-Class: com.zavier.agent.Agent
```

这里我们使用maven的assembly插件来完成上述配置实现

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-assembly-plugin</artifactId>
    <configuration>
        <descriptorRefs>
            <!-- 生成包含依赖的jar包 -->
            <descriptorRef>jar-with-dependencies</descriptorRef>
        </descriptorRefs>
        <finalName>${project.artifactId}-${project.version}-full</finalName>
        <appendAssemblyId>false</appendAssemblyId>
        <archive>
            <manifestEntries>
                <!-- 这里的配置和上面的是一一对应的 -->
                <Premain-Class>com.zavier.agent.Agent</Premain-Class>
                <Agent-Class>com.zavier.agent.Agent</Agent-Class>
                <Can-Redefine-Classes>true</Can-Redefine-Classes>
                <Can-Retransform-Classes>true</Can-Retransform-Classes>
            </manifestEntries>
        </archive>
    </configuration>
    <executions>
        <execution>
            <id>assemble-all</id>
            <phase>package</phase>
            <goals>
                <goal>single</goal>
            </goals>
        </execution>
    </executions>
</plugin>
```

#### 方法实现

两种方式使用起来大同小异，我们看一下大致用法实现

```java
public class Agent {

    // 定义 premain 方法并实现
    public static void premain(String args, Instrumentation instrumentation) {
        // 调用 Instrumentation#addTransformer(java.lang.instrument.ClassFileTransformer)
        // 添加对应的字节码文件转换器，用来对字节码进行转换
        instrumentation.addTransformer(new LogClassFileTransformer());
    }

    // 定义 agentmain 方法并实现
    public static void agentmain(String agentArgs, Instrumentation instrumentation) {
        // 同 premain 方法实现
        instrumentation.addTransformer(new LogClassFileTransformer());
    }

    static class LogClassFileTransformer implements ClassFileTransformer {

        @Override
        public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined, ProtectionDomain protectionDomain, byte[] classfileBuffer) throws IllegalClassFormatException {
            // 字节码转换的实现逻辑，通过解析原始字节码，进行替换后返回更新后的字节码，达到修改实现的目的
        }
    }
}
```

#### 实现例子

这次我们用byte-buddy对java-agent的支持，来实现一个记录请求日志的功能

1. 首先我们新建一个spring boot的项目，随便写下controller, service，然后正常启动项目

```java
@RestController
public class DemoController {
    @GetMapping(value = "/sayHello")
    public User sayHello(String name) {
        final User user = demoService.sayHello(name);
        return user;
    }
}

@Service
public class DemoService {
    public User sayHello(String name) {
        final User user = new User();
        user.setName(name);
        return user;
    }
}
```

这时候在浏览器访问 `http://localhost:8080/sayHello?name=zhangsan`，可以看到系统无日志，同时会返回

```json
{"name": "zhangsan"}
```

2. 在新建一个agent项目，实现记录所有调用DemoService#sayHello方法的参数和返回值

```java
// 先创建一个记录日志的Advice
import net.bytebuddy.asm.Advice;
import net.bytebuddy.implementation.bytecode.assign.Assigner;

import java.lang.reflect.Method;
import java.lang.reflect.Parameter;
import java.util.HashMap;
import java.util.Map;

public class LoggingAdvice {

    // 方法进行时获取对应的参数信息
    @Advice.OnMethodEnter(suppress = Exception.class)
    public static String before(
            @Advice.AllArguments Object[] allArguments,
            @Advice.Origin Method method) {
        if (allArguments == null) {
            return null;
        }

        Map<String, Object> map = new HashMap<>();

        final Parameter[] parameters = method.getParameters();
        for (int i = 0; i < parameters.length; i++) {
            map.put(parameters[i].getName(), allArguments[i]);

        }
        return map.toString();
    }

    // 方法退出时获取结果信息，并打印最终结果
    @Advice.OnMethodExit
    public static void after(
            @Advice.Enter String params,
            @Advice.Origin Method method,
            @Advice.Return(typing = Assigner.Typing.DYNAMIC) Object returnValue) {
        // 打印结果日志
        System.out.println("method:" + method.getName() + ",param:" + params + ",result:" + returnValue);
    }
}

```

实现Agent类对应的agentmain方法

```java
// Agent.java
public static void agentmain(String agentArgs, Instrumentation inst) {
    new AgentBuilder.Default().disableClassFormatChanges()
            .with(AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
            // 匹配以 com.zavier.bootdemo.web 开头的类
            .type(ElementMatchers.nameStartsWith("com.zavier.bootdemo.web"))
            .transform(new AgentBuilder.Transformer() {
                @Override
                public DynamicType.Builder<?> transform(DynamicType.Builder<?> builder, TypeDescription typeDescription, ClassLoader classLoader, JavaModule module) {
                    // 将方法名称是 sayHello 交给 LoggingAdvice 处理
                    return builder.visit(Advice.to(LoggingAdvice.class).on(
                            namedOneOf("sayHello")));
                }

            }).installOn(inst);
}
```

补充好配置文件后，整体进行打成一个jar包

3. 动态挂载，实现打印日志功能

```shell
# 首先查找对当前spring boot项目对应的进程ID，可以看到对应的ID是 63932
➜ jps -l                    
66387 sun.tools.jps.Jps
63932 com.zavier.bootdemo.BootDemoApplication
```

实现attach的java代码

```java
public static void main(String[] args) throws Exception {
    VirtualMachine jvm = VirtualMachine.attach("63932"); // springboot项目进程ID
    jvm.loadAgent("/path/agent-study-1.0-SNAPSHOT-full.jar");
}
```

这时候再通过浏览器访问`http://localhost:8080/sayHello?name=zhangsan`就可以看到如下输出

```
method:sayHello,param:{arg0=zhangsan},result:User(name=zhangsan)
```

这样我们就实现了在不修改代码的情况下添加日志的功能，当然这只是一个小的例子，实际使用的时候要考虑很多场景，如类的隔离、修改类的卸载回退等等



以上就是这次的全部内容，很多地方没有使用精确的定义，基本是作者个人的理解表述，如有错误欢迎指正

