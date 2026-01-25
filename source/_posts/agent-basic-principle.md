---
title: Agent并不神秘：基于大模型API的原理拆解
date: 2026-01-17 21:42:35
tags: [AI辅助]
---

如果你已经用过 Agent，可能会有一种很真实的感觉：

好像是会用了，但真让我讲清楚 Agent 是怎么跑起来的，又有点说不明白。

比如：

- Agent 为什么能一边“想”，一边“用工具”？
- Function Call 到底是谁在调用？模型？还是我们？
- LangChain / LangGraph 里那些节点、Memory，看起来很高级，本质在干嘛？

很多时候，我们是**跟着框架把 Agent 跑通了**。
 可一旦遇到下面这些情况，就会开始有点卡：

- 想自己手写一个简单 Agent
- 想排查 Agent 为什么卡住、不动了
- 或者想做点框架里没有的定制逻辑

这时候你大概率会觉得：Agent 有点像黑盒。

但其实，Agent 真没那么复杂。

如果你愿意把框架先放一边，只看最底层的 API，就会发现：
 Agent 本质上，就是几个很普通的东西，被我们拼在了一起。

这篇文章想做的事情也很简单：

**不用任何 Agent 框架，只用基础API + Java，一步一步把 Agent 是怎么工作的“摊开来看”。**

不追求花哨，只追求你看完之后能说一句：“哦，原来 Agent 是这么回事。”

那我们直接开始。

<!-- more -->

## 一、Agent 到底在干嘛？先别急着下定义

先别想什么“架构”“模式”。

换个更直观的角度想一件事。

如果你让一个人帮你做一件稍微复杂点的事情，过程通常是这样的：

1. 你先告诉他目标
2. 他想一想，决定下一步该干嘛
3. 如果需要查资料、算东西、调接口，就去用工具
4. 拿到结果之后，再想下一步
5. 直到他觉得：差不多搞定了

**Agent 做的事情，其实就跟这个过程非常像。**

只不过换成了程序世界：

- “想一想”的，是大模型
- “真的去干活”的，是你写的代码
- 两边不断来回沟通

所以你可以先这么理解 Agent：

> **Agent 就是一个：会反复「想 → 做 → 看结果 → 再想」的程序。**

### 再稍微往工程里收一收

如果把这个过程翻译成代码层面的东西，其实也不复杂：

- 有一份东西，记录“到目前为止发生了什么”
- 有一些工具，模型可以选择要不要用
- 有一个循环，让这个过程不断重复

后面你看到的所有代码，基本都在围绕这三点转。

------

## 二、先把最基础的事情做好：让模型能“正常聊天”

在聊 Agent 之前，有一个地基一定要先打好：**模型是怎么跟你“对话”的。**

### 1. 所谓上下文，其实就是你反复带着的聊天记录

在对话接口里，最核心的就是 `messages`，其中记录的是历史对话消息，role 表示的是角色（大模型/用户/工具等）

```json
[
  { "role": "system", "content": "你是一个助手" },
  { "role": "user", "content": "你好" }
]
```

这里有一个特别重要、但经常被忽略的事实：

**模型本身是没有记忆的。**

它之所以“记得你们之前聊过什么”，只是因为你每次都把这份完整的 messages 全部原封不动地再发给它。

换句话说：

- 你不发，它就不知道
- 你发什么，它就“记得什么”

这件事一旦想明白，后面 Agent 的很多行为都会变得很清楚。

### 2. 用 Java 调一次对话接口

下面是一个尽量简单的 Java 示例（用 OkHttp）：

```java
public class DeepSeekChatClient {

    private static final String API_KEY = "YOUR_API_KEY";
    private static final String API_URL = "https://api.deepseek.com/chat/completions";

    public static String chat(String messagesJson) throws IOException {
        OkHttpClient client = new OkHttpClient();

        RequestBody body = RequestBody.create(
            messagesJson,
            MediaType.parse("application/json")
        );

        Request request = new Request.Builder()
            .url(API_URL)
            .addHeader("Authorization", "Bearer " + API_KEY)
            .post(body)
            .build();

        try (Response response = client.newCall(request).execute()) {
            return response.body().string();
        }
    }
}
```

到这一步，你已经有了 Agent 的**最基础能力**：

你能维护一份“对话记录”，把它发给模型，拿到模型给你的“下一步回复”。

------

## 三、让模型“知道自己可以用工具”

前面我们已经能让模型正常聊天了。 但 Agent 之所以像“能干活”，关键并不是模型更聪明了，而是多了一件事：

模型可以在需要的时候，向你返回一个函数工具调用的请求

这个请求的意思不是：“我自己去调用函数”

而是：“我觉得下一步需要用某个工具，你能不能帮我执行一下？”

### 1. 先把角色分清楚

在工具这件事上，角色其实非常明确：

- **模型的职责**：
     判断要不要用工具、用哪个、参数是什么
- **程序的职责（如Java 这边）**：
     根据模型的请求，找到对应的方法， 执行它，再把结果告诉模型

模型始终只是在**“表达意图”**。

### 2. 怎么把“你可以请求我调用什么工具”告诉模型？

我们会在调用模型时，额外传一段工具描述。

比如一个最简单的天气查询能力：

```json
{
  "type": "function",
  "function": {
    "name": "getWeather",
    "description": "查询指定城市的天气",
    "parameters": {
      "type": "object",
      "properties": {
        "city": {
          "type": "string",
          "description": "城市名称"
        }
      },
      "required": ["city"]
    }
  }
}
```

你可以把这段话翻译成人话：

> “如果你觉得有必要，可以请求我调用一个叫 `getWeather` 的方法， 它需要一个 city 参数，我会把执行结果再告诉你。”

**仅此而已。**模型并不知道方法内部怎么实现，也不关心你是 Java、Python 还是远程 HTTP

### 3. 那模型“请求工具”时，会返回什么？

当模型判断“下一步需要用工具”时，它不会直接给你答案，而是会返回类似这样的内容：

```json
{
  "tool_calls": [
    {
      "name": "getWeather",
      "arguments": {
        "city": "ShangHai"
      }
    }
  ]
}
```

这一步非常关键，可以理解成模型在说：

“我现在不继续回答了，我需要你先帮我做一件事： 调用 `getWeather(city=ShangHai)`， 做完再告诉我结果。”

在模型返回 tool_calls 之后，系统到底要干嘛？

到这里，其实**模型这边已经“停住了”**。 接下来发生的事情，**全部在你的程序里(如java中)完成**。



#### 3.1 根据 tool name，找到对应的方法

在 Java 里，最常见的做法是：

- 用一个 `Map<String, Method>` 或 `Map<String, ToolHandler>`
- 或者通过反射，根据 name 找方法

例如（示意）：

```java
Method method = toolRegistry.get(toolCall.getName());
```

#### 3.2 把 arguments 转成方法参数

模型返回的参数，本质是 JSON：

```java
{
  "city": "ShangHai"
}
```

你需要做的事情包括：

- 反序列化 JSON
- 校验参数
- 转成 Java 方法需要的类型

```java
Object[] args = argumentResolver.resolve(method, toolCall.getArguments());
```

#### 3.3 执行方法，拿到结果

```java
Object result = method.invoke(toolInstance, args);
```

到这里，**工具调用才算真的发生**。

#### 3.4 把执行结果，重新包装成一条“消息”

非常重要的一点是：**工具执行结果不是直接返回给用户，而是要“喂回给模型”。**

通常会构造成一条类似这样的消息：

```json
{
  "role": "tool",
  "tool_name": "getWeather",
  "content": "上海当前气温 25℃，晴"
}
```

这条消息的意思是：“你刚才请求我调用的工具，我已经执行完了， 这是结果。”

**Agent 不是模型在调用工具，而是模型在“指挥你调用工具”。**

---

## 四、一个循环，Agent 就开始“动起来了”

有了上面这一步，Agent 的循环逻辑就非常自然了。你可以从“模型请求工具”这个角度，再看一次核心流程：

### 1. Agent 的核心逻辑，其实非常朴素

```
不断重复：
  把当前情况告诉模型
  看模型要不要你帮忙干点事
  如果要，就执行
  再把结果告诉模型
  直到模型觉得可以结束
```

换成伪代码，大概就是：

```java
while (true):
    response = 调模型(messages, tools)

    // 大模型没有返回工具调用，就可以结束了，返回给用户最终结果
    if 模型没有要用工具:
        break

    执行模型请求的工具
    把结果加回 messages
```

别被 Agent 这个词吓到。**其核心就是一个循环。**

### 2. 为什么非得是循环？

因为很多事情，本来就不是一步能做完的：

- 查完数据，可能还要继续分析
- 拿到结果，还要决定下一步

模型每一轮，其实都在回答一个问题：“现在这个阶段，我下一步该干嘛？”

### 3. Java 里的最小 Agent 主循环

```java
while (true) {
    LlmResponse response = llm.invoke(messages, tools);

    if (response.getToolCalls().isEmpty()) {
        messages.add(response.toAssistantMessage());
        break;
    }

    for (ToolCall call : response.getToolCalls()) {
        String result = toolExecutor.execute(call);
        messages.add(Message.toolResult(call.getName(), result));
    }
}
```

到这里，其实你已经**完整地跑起了一个 Agent**。没有框架，也没有什么隐藏逻辑。

------

## 五、真实工程里，一定要补的“防摔垫”

如果你真的跑过 Agent，很快就会发现： **能跑，和能用，是两回事。**

### 1. 一定要限制最大循环次数

模型有时候会想太久，甚至兜圈子。

```java
int maxSteps = 10;
int step = 0;

while (step++ < maxSteps) {
    ...
}
```

这是 Agent 的“安全带”。

### 2. messages 一定会越来越长

随着不断对话，messages 会一直涨：

- 成本会上升
- 迟早超上下文

常见做法很简单：

- 定期让模型总结前面的过程
- 用总结结果替换早期消息

很多框架里的 Memory，本质就在干这件事。

### 3. 模型说“我完事了”，但你知道它没完

这是一个**非常常见的情况**：

模型觉得自己已经完成任务了，但你看结果，明显还差一步。

工程里通常会：

- 再让模型自检一次
- 或者明确规定“什么才算完成”

一句话总结：

**模型的判断，需要被约束。**

------

## 六、最后简单收个尾

如果你一路看到这里，其实已经能发现：**Agent 并不是某个框架的专属能力。**

它只是：

- 一份不断更新的记录
- 一些模型可以选择使用的工具
- 一个不停运转的循环
- 再加上一点工程兜底

理解了这些，再回头看各种 Agent 框架，你会发现它们做的事情其实都很“接地气”。

这篇文章想做的，就是把 Agent 从 “看起来很高级”，拉回到一个**工程师可以完全理解、也完全能自己写出来的东西**。
