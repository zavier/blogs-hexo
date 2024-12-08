---
title: 使用大模型调用工具
date: 2024-12-08 19:27:22
tags: [langchain]
---

大模型很强大，但还是有很多功能是它无法实现的，比如搜索当时最新的信息，或者执行精确的数据计算、或者查询数据库、调用其他服务API等等，这时候就需要一些外部的对应工具来进行支持，langchain中帮我们进行了相应的集成支持

<!-- more -->

### 工具创建

提供给大模型的工具至少要有如下几个部分来说明它自己，以及让大模型判断如何使用，包含：名称、描述、参数的schema、以及是否在调用结束后直接返回给用户

langchain中支持如下三种方式创建工具：函数、Runnable (langchain_core.runnables) 以及 BaseTools(langchain_core.tools)子类

使用函数创建工具基本可以满足我们大部分的场景了，下面看一个具体的例子

```python
from langchain_core.tools import tool

# 通过添加@tool注解，就可以自动将函数包装成Runnable或者BaseTools子类，非常简单方便
@tool
def add(a: int, b: int) -> int:
    """Add tow integers.

    Args:
        a: First integer
        b: Second integer
    """
    return a + b

@tool
def multiple(a: int, b: int) -> int:
    """Multiple tow integers.
    
    Args:
        a: First integer
        b: Second integer
    """
    return a * b

# 可以打印一下工具的关键信息看一下
print(add.name)  # add
print(add.description)
# Add tow integers.
#    Args:
#        a: First integer
#        b: Second integer
print(add.args)
# {'a': {'title': 'A', 'type': 'integer'}, 'b': {'title': 'B', 'type': 'integer'}}
print(add.return_direct)
# false
```



### 将工具绑定到模型

```python
# 定义llm与工具集合
llm = QianfanChatEndpoint(model="ERNIE-3.5-8K")
tools = [add, multiple]

# 通过bind_tools将工具集绑定到大模型
llm_with_tools = llm.bind_tools(tools)
```



### 模型判断调用工具

大模型会根据问题来判断是否使用工具，以及使用何种工具

```python
llm_with_tools.invoke("你好")
# 返回: 您好！我是文心一言，很高兴与您交流。请问有什么我可以帮助您的吗？

# 计算问题，大模型会判断需要调用工具，返回的 tool_calls 中会包含判断使用的工具名称及参数信息
response = llm_with_tools.invoke("3*15等于多少?")
print(response.tool_calls)
# 返回: [{'name': 'multiple', 'args': {'a': 3, 'b': 15}, 'id': '38bc867d-5f05-49f6-af13-f918f8e5c655', 'type': 'tool_call'}]
# 大模型判断需要使用 multiple 工具，参数分别为 3 和 15

response = llm_with_tools.invoke("5+9等于多少?")
print(response.tool_calls)
# 返回: [{'name': 'add', 'args': {'a': 5, 'b': 9}, 'id': 'd79334da-c2f3-4d3a-bceb-6e7207d86805', 'type': 'tool_call'}]
# 大模型判断需要使用 add 工具，参数分别为 5 和 9
```



### 工具执行

有了如上信息后，我们就可以调用对应的工具进行最终的执行了

```python
# 定义好工具的名称和对应的函数映射
method_map = {"add": add, "multiple": multiple}
# 调用获取结果
response = llm_with_tools.invoke("5+9等于多少?")
for call in response.tool_calls:
    # 获取大模型选择的工具
    selected_tool = method_map[call["name"]]
    # 使用大模型返回的参数等信息，执行工具方法
    tool_res = selected_tool.invoke(call)
    # 最终结果: content='14' name='add' tool_call_id='309f53d5-a542-4c18-904d-646d1d4f1b71'
```



以上我们就完成了一个最简单的工具定义以及使用的流程，可以基于此完成更多更复杂，更有趣的功能～

