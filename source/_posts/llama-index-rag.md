---
title: 基于LlamaIndex的RAG简介
date: 2025-06-07 18:22:57
tags: [LlamaIndex, RAG]
---

[LLamaIndex](https://docs.llamaindex.ai/en/stable/)顾名思义，看起来是一个适合构建索引的框架，也就是 RAG(Retrieval-Augmented Generation)，所以我们本次主要看一下如何使用LlamaIndex 来实现一下RAG（当然，它也能用来实现智能体等功能）

RAG 的交互流程如下

<img src="/images/llama_index_rag.png" style="zoom:60%" />

主要涉及如下几个步骤节点

<img src="/images/rag_flow.png" style="zoom:60%" />



<!-- more -->

## 快速使用

先通过一个例子快速感受一下如何使用，因为默认的OpenAI 的接口很难访问，这里使用阿里的dashscope

注册API 的部分参考官方文档即可，这里不再赘述

1. 首先安装相关的依赖包

    ```shell
    pip install llama-index
    pip install llama-index-llms-dashscope
    pip install llama-index-embeddings-dashscope
    ```

2. 编写相关代码

    ```python
    from llama_index.core import Settings, VectorStoreIndex, SimpleDirectoryReader
    from llama_index.llms.dashscope import DashScope
    from llama_index.embeddings.dashscope import DashScopeEmbedding
    
    # 分别创建文本和向量两个模型
    dashscope_llm = DashScope(api_key="your-api-key")
    embedder = DashScopeEmbedding(api_key="your-api-key")
    
    # 将其设置为全局默认使用（否则会默认使用OpenAI相关模型）
    Settings.llm = dashscope_llm
    Settings.embed_model = embedder
    
    # 手动构造document
    documents = [Document(text="""
    1. 火卫一绕火星运行
    2. 火星是一种行星
    3. 卫星绕行星运行
    4. 火卫一(Phobos)以希腊恐惧与恐慌之神命名
    5. 卫星位于太空中
    6. 分类是一种科学过程
    """)]
    # 构建索引
    index = VectorStoreIndex.from_documents(documents)
    # 创建查询引擎
    query_engine = index.as_query_engine()
    # 提出问题，查询问题对应结棍
    response = query_engine.query("火卫一应该归类为什么类别?")
    ```

输出结果：`火卫一应该归类为卫星。`

## 概念介绍

下面根据[官网文档](https://docs.llamaindex.ai/en/stable/)，来对RAG流程中涉及到的一些概念进行介绍

### 数据加载

#### 文档和节点

**文档(Document)**：是一个数据源的容器，数据源可以包括一个PDF, 一个 API 输出，甚至是从数据库中获取的数据

可以手动构建 Document 也可以通过工具自动构建

一般除了基本文本内容外，也会记录其他属性信息，如元数据（文件名称等）以及和其他内容的关联关系

手动构建方式：

```python
from llama_index.core import Document
doc = Document(text="text", metadata={"filename": "<文件名称>"})
```

本地文件加载：

```python
from llama_index.core import SimpleDirectoryReader
# 读取当前目录下的data文件夹中的全部数据
documents = SimpleDirectoryReader("./data").load_data()
```

其他更多数据加载器(Reader)，可以通过[Llamahub](https://llamahub.ai/?tab=readers)查询获取



**节点(Node)**：是LlamaIndex 中的基本数据单元，用来表示Document 的一个块（chunk），如文本块、图片等等，同Document 一样会记录元数据以及和其他Node 的关联关系

可以直接指定内容和属性来构造Node，也可以通过解析器来将Documents 处理成Node，如`NodeParser`

解析Document为Node集合：

```python
from llama_index.core.node_parser import SentenceSplitter

# 将Document解析成Node集合
parser = SentenceSplitter()
nodes = parser.get_nodes_from_documents(documents)
```

手动构建Node：

```python
from llama_index.core.schema import TextNode, NodeRelationship, RelatedNodeInfo
# 创建Node
node1 = TextNode(text="<text_chunk>", id_="<node_id>")
node2 = TextNode(text="<text_chunk>", id_="<node_id>")
# 设置关系
node1.relationships[NodeRelationship.NEXT] = RelatedNodeInfo(
    node_id=node2.node_id
)
node2.relationships[NodeRelationship.PREVIOUS] = RelatedNodeInfo(
    node_id=node1.node_id
)
nodes = [node1, node2]
```



**元数据转换**：目前已经预置了如下几个元数据转换器，用于处理时提取对应的信息

- SummaryExtractor: 对每个节点内容进行总结，添加到metadata中
- QuestionsAnsweredExtractor：针对节点内容，提取出对应数量的问题添加到metadata中
- TitleExtractor：根据节点内容生成标题，添加到 metadata中

更多的转换器，可以参考[官方文档-extractors](https://docs.llamaindex.ai/en/stable/api_reference/extractors/)

```python
from llama_index.core.extractors import TitleExtractor
from llama_index.core.node_parser import TokenTextSplitter
from llama_index.core import Document
from llama_index.core.ingestion import IngestionPipeline

# token切分，将document转换成node
text_splitter = TokenTextSplitter(
    separator=" ", chunk_size=512, chunk_overlap=128
)
# 为每个node生成一个title
title_extractor = TitleExtractor(nodes=5)

# 转换器，接收输入数据，依次进行处理，返回结果节点
# 如果设置了向量数据库，也会直接进行存储
pipeline = IngestionPipeline(
    transformations=[text_splitter, title_extractor]
)

documents = [Document(text="文本内容")]
# 这里可以看到结果 node中的metadata中有一个document_title存储着标题内容
nodes = pipeline.run(
    documents=documents,
    in_place=True,
    show_progress=True,
)
```



### 索引

索引可以让我们快速的根据用户的问题查询到对应的相关内容

索引可以通过Document构建，后续用来创建Query Engines和Chat Engines来使用

#### 向量存储索引

通过document直接构建向量索引

```python
from llama_index.core import VectorStoreIndex
index = VectorStoreIndex.from_documents(documents)
```

通过nodes构建向量索引

```python
from llama_index.core.schema import TextNode

# 这里也可以通过其他方式创建node, 可以参考上面关于node的介绍
node1 = TextNode(text="<text_chunk>", id_="<node_id>")
node2 = TextNode(text="<text_chunk>", id_="<node_id>")
nodes = [node1, node2]
index = VectorStoreIndex(nodes)
```



在将文本转换成向量时，需要用到大模型的能力，默认会使用OpenAI的`text-embedding-ada-00`，如果我们要使用阿里的dashscope，则可以进行如下配置

1. 安装依赖 `pip install llama-index-embeddings-dashscope`

1. 构造`DashScopeEmbedding`并设置为全局默认

```python
from llama_index.embeddings.dashscope import DashScopeEmbedding

embedder = DashScopeEmbedding(api_key="<your-api-key>")
# 设置到全局默认使用
Settings.embed_model = embedder
```



在索引创建完成之后，我们也可以继续对其进行修改

```python
# 向索引中添加新Document
index.insert(Document(text="xx"))
# 删除文档(需要指定document_id)
index.delete_ref_doc("<doc_id>", delete_from_docstore=True)
# 更新已有文档
index.update_ref_doc(Document(doc_id="<doc_id>", text="<text>"))
# 批量刷新文档，存在则更新，不存在则插入
index.refresh_ref_docs([Document(doc_id="<doc_id>", text="<text>")])
```

更多其他类型索引文档，可以参考[官方文档-indexing](https://docs.llamaindex.ai/en/stable/module_guides/indexing/modules/)



### 存储

因为构造索引需要调用大模型的API，为了节省成本我们可以将索引进行持久化，在后续使用的时候重新加载即可

```python
from llama_index.core import StorageContext, load_index_from_storage
from llama_index.core.indices import VectorStoreIndex

# 构建索引
index = VectorStoreIndex.from_documents(documents)
# 持久化索引到磁盘
index.storage_context.persist("./storage")
# 加载持久化的索引
storage_context = StorageContext.from_defaults(persist_dir="./storage")
index = load_index_from_storage(storage_context)
```

这里也可以使用专门的向量数据库，具体使用方式可以参考[官方文档](https://docs.llamaindex.ai/en/stable/understanding/storing/storing/#using-vector-stores)



### 查询

#### 检索器

检索器负责根据用户的查询/对话，查询到最相关的内容

可以通过索引直接构建

```python
# 通过索引构建检索器
retriever = index.as_retriever()
# 设置问题，获取相关的内容
nodes = retriever.retrieve("Who is Paul Graham?")
```



#### 路由

在有多个检索器的情况下，可以使用路由来决定具体使用哪个检索器来进行相关内容的查询

```python
from llama_index.core.retrievers import RouterRetriever
from llama_index.core.selectors import PydanticSingleSelector
from llama_index.core.tools import RetrieverTool

# 构造检索器
vector_retriever = vector_index.as_retriever()
keyword_retriever = keyword_index.as_retriever()

# 初始化tools
vector_tool = RetrieverTool.from_defaults(
    retriever=vector_retriever,
    # 设置描述信息，辅助大模型判断
    description="Useful for retrieving specific context from Paul Graham essay on What I Worked On.",
)
keyword_tool = RetrieverTool.from_defaults(
    retriever=keyword_retriever,
    # 设置描述信息，辅助大模型判断
    description="Useful for retrieving specific context from Paul Graham essay on What I Worked On (using entities mentioned in query)",
)

# 定义路由retriever
retriever = RouterRetriever(
    selector=PydanticSingleSelector.from_defaults(llm=llm),
    retriever_tools=[
        list_tool,
        vector_tool,
    ],
)
```



#### 节点后处理器

在通过检索器获取到数据，到提交给大模型处理返回之前，可以添加一些节点来对数据结果进行一些处理，如转换、过滤或者重排序

```python
from llama_index.core.postprocessor import SimilarityPostprocessor
# 获取检索到的节点集合
nodes = index.as_retriever().retrieve("test query str")

# 过滤掉相似度小于0.75的数据
processor = SimilarityPostprocessor(similarity_cutoff=0.75)
filtered_nodes = processor.postprocess_nodes(nodes)
```

更多预置节点可以参考[官网文档-node_proessors](https://docs.llamaindex.ai/en/stable/module_guides/querying/node_postprocessors/node_postprocessors/)



#### 响应合成器

结果合成器，是负责将用户问题和检索到的一系列文本块提供给大模型，生成最终结果使用

```python
from llama_index.core.data_structs import Node
from llama_index.core.schema import NodeWithScore
from llama_index.core import get_response_synthesizer

# 构造合成器，设置响应模式: compact
response_synthesizer = get_response_synthesizer(response_mode="compact")
# 传递结果和数据节点给到合成器，生成最终结果
response = response_synthesizer.synthesize(
    "query text", nodes=[NodeWithScore(node=Node(text="text"), score=1.0), ...]
)
```

其中可选的 response mode 包括：refine、compact、tree_summarize、simple_summarize、no_text、context_only、accumulate、compact_accumulate、generation 等。每种模式的区别如下：

- refine：逐块精细生成和迭代答案，适合需要详细、分步推理的场景；
- compact：将多个块合并后生成答案，减少 LLM 调用次数，适合大文本但对细节要求不高的场景；
- tree_summarize：递归树状摘要，适合多块内容的总结；
- simple_summarize：截断所有块合并为单次 LLM 调用，适合快速摘要但可能丢失细节；
- no_text/context_only：仅返回检索到的节点或拼接文本，不生成最终答案，适合调试或需要原始上下文的场景；
- accumulate/compact_accumulate：分别对每个块单独问答并拼接，适合需要分别处理每个块的场景；
- generation：忽略上下文，直接用 LLM 生成答案，适合开放式生成任务。[官方文档](https://docs.llamaindex.ai/en/stable/module_guides/querying/response_synthesizers/#configuring-the-response-mode)有详细说明。





最后，可以将检索器和响应合成器合并成查询引擎，输入用户问题，获取最终加工后的结果，完整代码如下

```python
from llama_index.core import VectorStoreIndex, get_response_synthesizer
from llama_index.core.retrievers import VectorIndexRetriever
from llama_index.core.query_engine import RetrieverQueryEngine

# 构建索引
index = VectorStoreIndex.from_documents(documents)

# 配置检索器
retriever = VectorIndexRetriever(
    index=index,
    similarity_top_k=2,
)

# 配置响应合成器
response_synthesizer = get_response_synthesizer(
    response_mode="tree_summarize",
)

# 构造查询引擎
query_engine = RetrieverQueryEngine(
    retriever=retriever,
    response_synthesizer=response_synthesizer,
)

# 查询获取结果
response = query_engine.query("What did the author do growing up?")
print(response)
```

也可以通过更简化的方式，直接通过索引来构造查询引擎

```python
query_engine = index.as_query_engine(response_mode="tree_summarize")
```



