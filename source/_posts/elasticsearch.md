---
title: 10分钟入门 Elasticsearch
date: 2024-01-21 20:48:25
tags: [elasticsearch]
---

在当今信息爆炸的时代，对于大规模数据的搜索、分析和可视化变得至关重要。Elasticsearch（ES）作为一款开源搜索和分析引擎，为开发者和企业提供了一种强大而灵活的工具，能够轻松处理海量数据，并提供高效的搜索和分析能力

本文围绕 Elasticsearch 来讲解一下如何创建索引、进行数据写入和查询，快速入门ES使用

<!-- more -->

### 创建索引

```json
PUT <index>
{
	"settings": {
        // 主分片数量
        "number_of_shards": "3",
        // 每个主分片拥有的副本分片数量
        "number_of_replicas": "1"
    },
    "mappings": {
        "properties": {
            "address": {
                // text: 默认会被分词的字符串
                "type": "text"
            },
            "userName": {
                // keyword 不会分词，精准匹配的字符串(有最大长度限制)
                "type": "keyword"
            },
            "name": {
                // 可以使用fields同时有分词和不分词的效果
                // name 是会被分词的
                // name.keyword 不会被分词，但是超过256长度后的字符会被忽略
                "type": "text",
                "fields": {
                    "keyword": {
                        "type": "keyword",
                        "ignore_above": 256
                    }
                }
            },
            "fullName": {
                // 对象类型，实际是 fullName.firstName , fullName.lastName
                "properties": {
                    "firstName": {
                        "type": "text"
                    },
                    "lastName": {
                        "type": "text"
                    }
                }
            }
        }
    }
}
```



### 索引操作

#### 基本CRUD

```json
// 新增：url中ID可选，不传会默认生成，id如果已存在会覆盖原数据
POST <index>/_doc/<id>
{
    "id": "1",
    "name": "zhangsan"
}

// 根据ID查询
GET <index>/_doc/<id>

// 修改数据(只有传的数据会修改，没传还是原值)
POST <index>/_update/<id>
{
    "doc": {
    	"id": "1",
    	"name": "zhangsan"
    }
}

// 删除
DELETE <index>/_doc/<id>
```

#### 乐观锁修改数据

在修改请求url后拼接参数?if_seq_no=xx&if_primary_term=yy, 具体的值为之前查询出的数据值

```json
PUT <index>/_doc/1?if_seq_no=xx&if_primary_term=yy
{
// data
}

POST <index>/_update/<id>?if_seq_no=xx&if_primary_term=yy
{
    "doc": {
    	"id": "1",
    	"name": "zhangsan"
    }
}
```

#### 批量写入数据

````json
POST <index>/_bulk
{
    // 使用index ID存在时会覆盖，使用create ID存在时会抛出异常
    {"index":{"_id":1}}
	{"id":1, "name":"name1"}
    {"create":{"_id":2}}
	{"id":2, "name":"name2"}

	{"update":{"_id":3}}
	{"doc":{"name":"name3"}}

    {"delete": {"_id": 4}}
}
````



#### 搜索数据

**精确查询**

```json
// term
POST <index>/_search
{
    "query": {
        "term": {
            "<property>": {
                "value": "<value>"
            }
        }
    }
}

// terms（同时查询多个值，or的关系）
POST <index>/_search
{
    "query": {
        "terms": {
            "<property>": [
                "value1",
                "value2"
            ]
        }
    }
}

// 主键查询：ids
GET <index>/_search
{
  "query": {
    "ids": {
      "values": [<id1>, <id2>]
    }
  }
}

// 范围查询：range
GET <index>/_search
{
  "query": {
    "range": {
      "<field>": {
        "gte": "1998-09-01 00:00:00",
        "lte": "1998-11-01 00:00:00"
      }
    }
  }
}

// 存在查询, 是否存在某个属性：exists
GET <index>/_search
{
  "query": {
    "exists": {
      "field": "<field>"
    }
  }
}


```

**全文检索**

```json
// 单字段匹配查询
POST <index>/_search
{
    "query": {
        "match": {
            "<field>": {
                "query": "<value1> <value2>"
            }
        }
    }
}

// 多字段查询
POST <index>/_search
{
  "query": {
    "multi_match": {
      "query": "<value1> <value2>",
      "fields": ["<field1>", "<field2>"],
      "operator": "and"
    }
  }
}

// 查询字符串搜索
POST <index>/_search
{
  "query": {
    "query_string": {
      // 这里写查询表达式
      "query": "\"content\"=\"XXX\" AND \"content\"=\"YYY\""
    }
  }
}
```

**复合查询**

```json
POST <index>/_search
{
  "query": {
    "bool": {
      // must中进行全文检索
      "must": [
        {
          "match": {
            "<field>": "<value>"
          }
        }
      ],
      // filter中进行精确匹配
      "filter": [
        {
          "term": {
            "<field>": "<value>"
          },
          "range": {
            "<field>": {
              "gte": 10,
              "lte": 20
            }
          }
        }
      ]
    }
  }
}
```

**只获取需要字段**

```json
GET <index>/_search
{
  "query": {
    "match_all": {}
  },
  // 指定需要的字段信息
  "_source": ["<field>"]
}
```

#### 分页查询

```json
// 普通分页
GET <index>/_search
{
  "query": {
    "match_all": {}
  },
  "size": 2,
  "from": 0,
  "track_total_hits": true,
  "sort": [
    {
      "<field>": {
        "order": "desc"
      }
    }
  ]
}

// 滚动分页
POST <index>/_search?scroll=1m  // 1m=1分钟
{
  "query": {
    "match_all": {}
  },
  "size": 10,
  "track_total_hits": true
}
// 之后（1分钟内）可以通过返回的_scroll_id进行查询，每次使用上传查询返回结果
POST /_search/scroll
{
    "scroll": "1m",
    "scroll_id":"<_scroll_id>"
}
// 手动释放scroll
DELETE /_search/scroll
{
    "scroll_id":"<_scroll_id>"
}

// search after分页
GET books/_search
{
  "query": {
    "match_all": {}
  },
  "size": 2,
  "from": 0,
  "track_total_hits": true,
  "sort": [
    {
      // 排序字段
      "<field>": {
        "order": "desc"
      }
    }
  ],
  // 指定上次分页查询结果的最后一条数据对应的排序字段值
  "search_after": [311]
}
```



#### 对象嵌套结构

**构造有嵌套结构的索引**

```json
PUT <index>
{
  "mappings": {
    "properties": {
      "<field1>": {
        // 设置成 nested 类型
        "type": "nested",
        "properties": {
          "<nested field1>": {
            "type": "integer"
          }
        }
      }
    }
  }
}
```

**嵌套结构查询**

```json
POST <index>/_search
{
  "query": {
    "nested": {
      "path": "<嵌套对象路径>",
      "query": {
        "bool": {
          "must": [
            {
              "match": {
                "<field>": "<value>"
              }
            }
          ]
        }
      },
      // 需要设置 inner_hits
      "inner_hits": {}
    }
  }
}
```
