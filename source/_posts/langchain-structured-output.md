---
title: 如何让大模型返回结构化的数据
date: 2024-12-08 16:41:50
tags: [langchain]
---

大模型中一般可以用来进行对话等，但是有一些场景我们可能要基于大模型的返回结果进行一些后续代码的处理，比如进行一些判断，返回结果为是/否，或者生成一些数据我们直接使用，这种情况下我们就需要大模型返回的结构是固定的，这样代码才能够进行解析使用

本篇根据langchain官方文档，简单介绍一下如何使用langchain来让大模型返回结构化数据的几种方式

> 使用 langchain0.3，以及百度千帆模型

<!-- more -->

### 使用with_structured_output方法

使用pydantic来描述结构化的信息和字段，配置 with_structured_output 方法来让大模型返回结构化的数据

```python
from typing import Optional

from pydantic import BaseModel, Field

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





