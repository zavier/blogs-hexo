---
title: 如何让大模型返回结构化的数据
date: 2024-12-08 16:41:50
tags: [langchain]
---

大模型中一般可以用来进行对话等，但是有一些场景我们可能要基于大模型的返回结果进行一些后续代码的处理，比如进行一些判断，返回结果为是/否，或者生成一些数据我们直接使用，这种情况下我们就需要大模型返回的结构是固定的，这样代码才能够进行解析使用

本篇根据langchain官方文档，简单介绍一下如何使用langchain来让大模型返回结构化数据的几种方式

> 使用python 3.10.9    langchain0.3，以及百度千帆模型

<!-- more -->

### 环境准备

```shell
# 创建虚拟环境
$ python3 -m venv .venv
# 激活虚拟环境
$ source .venv/bin/activate
# 安装依赖
$ pip install langchain
$ pip install langchain-community
$ pip install qianfan
```



### 普通调用方式

先简单看一下普通的对话调用方式

```python
model = QianfanChatEndpoint(model="ERNIE-3.5-8K")
messages = [
    # 设置消息类型及内容, 其他的还有 AIMessage(历史会话可以通过这种方式传给大模型)
    SystemMessage(content="你是一名资深python flask专家"),
    HumanMessage(content="falsk是一个什么样的框架？"),
]
result = model.invoke(messages)
print(result)
```

输出结果

```
content='Flask是一个轻量级的Web应用框架，使用Python语言编写。它被设计为可扩展性强、灵活性和可定制性高的框架，适用于开发各种Web应用程序。Flask提供了基本的路由、模板渲染、错误处理等Web开发所需的功能，同时保持了核心的简单性，使得开发者可以快速上手并专注于业务逻辑的开发。\n\nFlask具有以下特点：\n\n1. 轻量级：Flask的核心功能较少，不包含许多大型框架的默认功能，因此更加轻量级，适合小型和大型项目的快速开发。\n2. 灵活性：Flask提供了很高的灵活性，允许开发者根据需求进行定制。开发者可以根据自己的需求选择安装和使用其他扩展包来增强Flask的功能。\n3. 可扩展性：Flask是可扩展的，可以与其他库和扩展包无缝集成。这使得开发者可以根据项目的需求轻松地添加新功能或扩展现有功能。\n4. 易于学习：Flask的API简单明了，易于学习。对于初学者来说，可以快速掌握Flask的基本用法，并开始开发Web应用程序。\n5. 社区支持：Flask拥有庞大的社区支持，有大量的文档、教程和示例可供参考。这有助于开发者解决遇到的问题并获取灵感。\n\n总之，Flask是一个功能强大、灵活且易于使用的Web应用框架，适用于各种规模的Web应用程序开发。' additional_kwargs={} response_metadata={'token_usage': {'input_tokens': 19, 'output_tokens': 286, 'total_tokens': 305}, 'model_name': 'ERNIE-Lite-8K', 'finish_reason': 'stop'} id='run-f355ce24-4899-4c54-8337-d975e06b72d6-0' usage_metadata={'input_tokens': 19, 'output_tokens': 286, 'total_tokens': 305}
```



### 使用with_structured_output方法

使用pydantic来描述结构化的信息和字段，配置 with_structured_output 方法来让大模型返回结构化的数据

```python
import os
from typing import Optional

from pydantic import BaseModel, Field

# 百度千帆的配置,可以自行去对应平台申请
os.environ["QIANFAN_AK"] = "your-ak"
os.environ["QIANFAN_SK"] = "your-sk"

# 通过 pydantic 构造预期返回的类型
class Joke(BaseModel):
    """Joke to tell user."""
    setup: str = Field(description="The setup of the joke")
    punchline: str = Field(description="The punchline of the joke")
    rating: Optional[int] = Field(
        default=None,
        description="How funny the joke is, from 1 to 10"
    )
# 这里使用 QianfanChatEndpoint，也可以替换成其他llm
llm = QianfanChatEndpoint(model="ERNIE-3.5-8K")
# 使用 with_structured_output 方法调用llm返回结构化数据
structured_llm = llm.with_structured_output(Joke)
structured_llm.invoke("Tell me a joke about cats")
```

返回结果

```
Joke(setup='A cat is sitting in front of a mirror and sees another cat. What does the cat think?', punchline='The cat thinks it is time for lunch!', rating=5)
```



### 使用PydanticOutputParser处理

如果模型不支持 `with_structured_output ` 方法，那么可以用`PydanticOutputParser`来生成对应提示词和处理解析返回结果

```python
from langchain_core.output_parsers import PydanticOutputParser
from langchain_core.prompts import ChatPromptTemplate
from pydantic import BaseModel, Field

# 还是使用Joke来描述结构
class Joke(BaseModel):
    """Joke to tell user."""
    setup: str = Field(description="The setup of the joke")
    punchline: str = Field(description="The punchline of the joke")
    rating: Optional[int] = Field(
        default=None,
        description="How funny the joke is, from 1 to 10"
    )


# 构造解析器
parser = PydanticOutputParser(pydantic_object=Joke)

# 构造提示词模版
prompt = PromptTemplate(
    # 模版中填充使用PydanticOutputParser生成的结构化输出提示词
    template="Answer the user query.\n{format_instructions}\n{query}\n",
    # 用户输入的变量
    input_variables=["query"],
    # PydanticOutputParser生成的结构化输出提示词, 变量名使用 format_instructions
    partial_variables={"format_instructions": parser.get_format_instructions()},
)

query = "Tell me a joke about cats"

# 这里可以打印提示词看一下
print(prompt.invoke({"query": query}).to_string())

llm = QianfanChatEndpoint(model="ERNIE-3.5-8K")

# 将提示此、llm、结果解析器构造成链
chain = prompt | llm | parser
# 使用参数实际调用获取结果
chain.invoke({"query": query})
```

输出的提示词信息：

````
Answer the user query.
The output should be formatted as a JSON instance that conforms to the JSON schema below.

As an example, for the schema {"properties": {"foo": {"title": "Foo", "description": "a list of strings", "type": "array", "items": {"type": "string"}}}, "required": ["foo"]}
the object {"foo": ["bar", "baz"]} is a well-formatted instance of the schema. The object {"properties": {"foo": ["bar", "baz"]}} is not well-formatted.

Here is the output schema:
```
{"description": "Joke to tell user.", "properties": {"setup": {"description": "The setup of the joke", "title": "Setup", "type": "string"}, "punchline": {"description": "The punchline of the joke", "title": "Punchline", "type": "string"}, "rating": {"anyOf": [{"type": "integer"}, {"type": "null"}], "default": null, "description": "How funny the joke is, from 1 to 10", "title": "Rating"}}, "required": ["setup", "punchline"]}
```
Tell me a joke about cats
````

最终结果：

```
Joke(setup='Why did the cat sit on the computer?', punchline='It wanted to keep an eye on the mouse!', rating=7)
```



类似的，我们也可以使用`JsonOutputParser`、`XMLOutputParser`来让大模型输出对应格式的结果

```python
from langchain_core.output_parsers import JsonOutputParser
from pydantic import BaseModel, Field
from typing import Optional

class Joke(BaseModel):
    """Joke to tell user."""
    setup: str = Field(description="The setup of the joke")
    punchline: str = Field(description="The punchline of the joke")
    rating: Optional[int] = Field(
        default=None,
        description="How funny the joke is, from 1 to 10"
    )

# 构造解析器, 这里使用 JsonOutputParser
parser = JsonOutputParser(pydantic_object=Joke)

# 使用提示此模版
prompt = PromptTemplate(
    template="Answer the user query.\n{format_instructions}\n{query}\n",
    input_variables=["query"],
    partial_variables={"format_instructions": parser.get_format_instructions()},
)
llm = QianfanChatEndpoint(model="ERNIE-3.5-8K")

chain = prompt | llm | parser
chain.invoke({"query": "Tell me a joke about cats"})
```

结果：

```json
{'setup': 'Why did the cat sit on the computer?',
 'punchline': 'Because it wanted to keep an eye on the mouse!',
 'rating': 7}
```



### 自定义解析

当然，我们也可以仿照之前的例子，自己来编写提示词和配套的解析器

提示词中结构描述，还可以继续借助 pydantic 来生成对应的schema

```python
class Joke(BaseModel):
    """Joke to tell user."""
    setup: str = Field(description="The setup of the joke")
    punchline: str = Field(description="The punchline of the joke")
    rating: Optional[int] = Field(
        default=None,
        description="How funny the joke is, from 1 to 10"
    )
Joke.model_json_schema()
```

结果：

```json
{'description': 'Joke to tell user.',
 'properties': {'setup': {'description': 'The setup of the joke',
   'title': 'Setup',
   'type': 'string'},
  'punchline': {'description': 'The punchline of the joke',
   'title': 'Punchline',
   'type': 'string'},
  'rating': {'anyOf': [{'type': 'integer'}, {'type': 'null'}],
   'default': None,
   'description': 'How funny the joke is, from 1 to 10',
   'title': 'Rating'}},
 'required': ['setup', 'punchline'],
 'title': 'Joke',
 'type': 'object'}
```

结果解析可以自己编写对应的规则进行处理，如使用正则表达式等，如

```python
# 入参为 AIMessage，返回类型可以自己定义
def extract_json(message: AIMessage) -> List[dict]:
    # 获取消息内容
    text = message.content
    # 定义匹配的正则表达式
    pattern = r"\`\`\`json(.*?)\`\`\`"
    # 获取匹配内容
    matches = re.findall(pattern, text, re.DOTALL)
    try:
        # 转换成对应的json数据
        return [json.loads(match.strip()) for match in matches]
    except Exception:
        raise ValueError(f"Failed to parse: {message}")
```

使用方式也基本一样，大致如下

```python
# 最后解析部分，指定自定义的函数即可
chain = prompt | llm | extract_json
chain.invoke({"query": query})
```



### 格式修复

由于大模型的不确定性，有时候它返回的合适不一定符合我们的要求，如果只是有一点小小的格式问题，我们可以让大模型来帮助我们修复一下

```python
from langchain_core.exceptions import OutputParserException
from langchain.output_parsers import OutputFixingParser

class Joke(BaseModel):
    """Joke to tell user."""
    setup: str = Field(description="The setup of the joke")
    punchline: str = Field(description="The punchline of the joke")
    rating: Optional[int] = Field(
        default=None,
        description="How funny the joke is, from 1 to 10"
    )

parser = PydanticOutputParser(pydantic_object=Joke)

# 这个是错误的格式
misformatted = "{'setup': 'Why did the cat sit on the computer?', 'punchline': 'Because it wanted to keep an eye on the mouse!', 'rating': 7}"

# 使用 PydanticOutputParser 解析时会异常
try:
    parser.parse(misformatted)
except OutputParserException as e:
    print(e)

# 使用解析器和llm构造一个 OutputFixingParser，对异常的格式进行处理，可以解析成功
new_parser = OutputFixingParser.from_llm(parser=parser, llm=QianfanChatEndpoint(model="ERNIE-3.5-8K"))
new_parser.parse(misformatted)
```

输出结果：

```
# 这里是开始的错误信息输出
Invalid json output: {'setup': 'Why did the cat sit on the computer?', 'punchline': 'Because it wanted to keep an eye on the mouse!', 'rating': 7}
For troubleshooting, visit: https://python.langchain.com/docs/troubleshooting/errors/OUTPUT_PARSING_FAILURE 

# 这里是使用 OutputFixingParser 处理后，解析成功的结果
Joke(setup='Why did the cat sit on the computer?', punchline='Because it wanted to keep an eye on the mouse!', rating=7)
```



### 异常重试

上述方式在格式有小问题时修复可以，但是如果数据缺失等有较大问题时可能就无法修复了，这时候只能进行重试，此时可以使用`RetryOutputParser`

```python
from langchain_core.output_parsers import PydanticOutputParser
from langchain.output_parsers import RetryOutputParser
from pydantic import BaseModel, Field
from typing import Optional

class Joke(BaseModel):
    """Joke to tell user."""
    setup: str = Field(description="The setup of the joke")
    punchline: str = Field(description="The punchline of the joke")
    rating: Optional[int] = Field(
        default=None,
        description="How funny the joke is, from 1 to 10"
    )
# 构造解析器
parser = PydanticOutputParser(pydantic_object=Joke)
# 使用提示此模版
prompt = PromptTemplate(
    template="Answer the user query.\n{format_instructions}\n{query}\n",
    input_variables=["query"],
    partial_variables={"format_instructions": parser.get_format_instructions()},
)

# 这里我们模拟一个有问题的响应，它缺失 punchline、rating属性
bad_response = "{'setup': 'Why did the cat sit on the computer?'}"

# 这里设置使用的大模型，temperature可以设置的尽量低一点，这样可以最大程度的让它不改变内容，只是补全
llm = QianfanChatEndpoint(model="ERNIE-3.5-8K", temperature=0.01)
# 使用解析器、llm构造 RetryOutputParser
retry_parser = RetryOutputParser.from_llm(parser=parser, llm=llm)
# 将之前的提示词模版与当时的问题重新生成一个完成的提示词
prompt_value = prompt.format_prompt(query="Tell me a joke about cats")
# 使用当时的提示词与错误的相应，传递给retry_parser进行重新生成
retry_parser.parse_with_prompt(bad_response, prompt_value)
```

响应如下，可以看到大模型帮我们补全了剩余的内容，并且没有改变原始已有的值

```
Joke(setup='Why did the cat sit on the computer?', punchline='It wanted to keep an eye on the mouse!', rating=7)
```



### 文本分类

使用结构化输出的能力，还可以对内容进行分类打标等操作，下面看一下[官方文档](https://python.langchain.com/docs/tutorials/classification/)中的例子

```python
from langchain_core.prompts import ChatPromptTemplate
from langchain_community.chat_models import QianfanChatEndpoint
from pydantic import BaseModel, Field

# 通过编写提示词，让大模型提取输出中的特定信息
tagging_prompt = ChatPromptTemplate.from_template(
"""
Extract the desired information from the following passage.

Only extract the properties mentioned in the 'Classification' function.

Passage:
{input}
"""
)

# 定义需要提取的字段和对应的枚举值
class Classification(BaseModel):
    """Classification"""
    sentiment: str = Field(..., enum=["happy", "neutral", "sad"])
    aggressiveness: int = Field(
        ...,
        description="describes how aggressive the statement is, the higher the number the more aggressive",
        enum=[1,2,3,4,5]
    )
    language: str = Field(..., enum=["Spanish", "english", "french", "german", "italian"])


# 这里使用百度的Qianfan, temperature设置低一点，同时使用with_structured_output进行结构化输出
llm=QianfanChatEndpoint(model="ERNIE-3.5-8K", temperature=0.01).with_structured_output(Classification)
```

进行判断

```python
inp = "Estoy increiblemente contento de haberte conocido! Creo que seremos muy buenos amigos!"
prompt = tagging_prompt.invoke({"input": inp})
llm.invoke(prompt)
```

结果如下

```
Classification(sentiment='happy', aggressiveness=1, language='Spanish')
```

