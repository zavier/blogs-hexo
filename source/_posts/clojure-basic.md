---
title: Clojure学习文档
date: 2022-01-21 21:40:25
tags: [clojure]
---



本文主要对Clojure官网中的基础教程部分进行一下整理，对应地址https://clojure.org/guides/learn/syntax

<!-- more -->

## 函数

### 创建函数

定义一个函数，名称为 greet, 参数为name

```clojure
(defn greet [name] (str "Hello, " name))

;; 或者使用如下方式
(def greet (fn [name] (str "Hello, " name)))
```

使用

```clojure
user=> (greet "students")
"Hello, students"
```

### 函数重载

```clojure
(defn messenger
  ([]) (messanger "Hello world!")
  ([msg] (println msg)))

;; 使用
user=> (messenger)
Hello world!

user => (messenger "Hello class!")
Hello class!
```

### 可变参数函数

```clojure
(defn hello [greeting & who]
  (println greeting who))
```

其中除第一个参数外，其余参数都会被放入 who 参数中，类型为list

```clojure
user=> (hello "Hello" "world" "class")
Hello (world class)
```

### 匿名函数

```clojure
;; 定义匿名函数
(fn [message] (println message))

;; 定义的同时调用
((fn [message] (println message)) "Hello world!")
;; Hello world!
```

匿名函数可以使用更加简洁的写法

```clojure
;; 相当于 (fn [x] (+ 6 x))
#(+ 6 %)

;; 相当于 (fn [x y] (+ x y))
#(+ %1 %2)

;; 相当于 (fn [x y & zs] (println x y zs))
#(println %1 %2 %&)
```

### 应用函数

apply函数可以使用0个或多个参数调用函数

```clojure
(apply f '(1 2 3 4))    ;; 等于 (f 1 2 3 4)
(apply f 1 '(2 3 4))    ;; 等于 (f 1 2 3 4)
(apply f 1 2 '(3 4))    ;; 等于 (f 1 2 3 4)
(apply f 1 2 3 '(4))    ;; 等于 (f 1 2 3 4)
```

当入参是一个集合的时候，但是函数参数需要为单个参数时，apply很有用，如

```clojure
;; 假定有一个求和函数，但是参数不定
;; 如果我们写成 (defn add [& z] (+ z)) ，因为z是list类型，这样会异常，可以写成
(defn add [& z] (apply + z))
```

### 局部量

```clojure
;; 定义局部量 x=1, y=2
(let [x 1
      y 2]
  (+ x y))
```

### 闭包

```clojure
;; 定义一个函数，其结果会返回一个函数
(defn messenger-builder [greeting]
  (fn [who] (println greeting who)))

;; 使用
(def hello-er (messenger-builder "Hello"))
(hello-er "world!")
;; Hello world
```



## 集合

### vector

vector是一个有序的集合序列，使用 `[]`格式，如`[1 2 3]`

```clojure
;; 根据索引获取元素,如果索引值无效时会返回nil
user=> (get ["abc" false 99] 0)
"abc"

;; 计数元素数量
user=> (count [1 2 3 "a"])
4

;; 构造集合
user=> (vector 1 2 3)
[1 2 3]

;; 添加元素，使用conj将元素添加到末尾
user=> (conj [1 2 3] 4 5 6)
[1 2 3 4 5 6]
```

### list

list类似一个链表，与vector的区别是其会使用括号，如`(1 2 3 4)`，在对list求值时，第一项会被解析成函数，后面的元素作为参数传递给它，如果不希望求值，可以在前面加上符号`'`

```clojure
user=> (+ 1 2 3)
6
user=> '(+ 1 2 3)
(+ 1 2 3)


;; 构造集合
(def cards '(10 :ace :jack 9))

;; 因为list没有索引，所以不能通过索引访问，遍历时需要使用 first, rest
user=> (first cards)
10
user=> (rest cards)
'(:ace :jack 9)

;; 添加元素，可以使用 conj, 但是会添加到集合头部
user=> (conj cards :queen)
(:queen 10 :ace :jack 9)

;; 当做栈使用
user=> (def stack '(:a :b))
user=> (peek stack)
:a
user=> (pop stack) ;; 仍然不会改变集合本身，即执行后 stack依然有两个元素
(:b)
```

### set

set是一个无序不重复的集合

```clojure
;; 定义，其中逗号可以省略
(def players #{"Alice", "Bob", "kelly"})

;; 添加元素
user=> (conj players "Fred")
#{"Alice" "Fred" "Bob" "Kelly"}

;; 删除元素，使用 disj
user=> (disj players "Bob" "Sal")
#{"Alice" "Kelly"}

;; 检查元素是否存在
user=> (contains? players "Kelly")
true

;; 排序set
user=> (conj (sorted-set) "Bravo" "Charlie" "Sigma" "Alpha")
#{"Alpha" "Bravo" "Charlie" "Sigma"}

;; 集合合并- into
user=> (def players #{"Alice" "Bob" "kelly"})
user=> (def new-players ["Tim" "Sue" "Grey"])
user=> (into player new-players)
#{"Alice" "Greg" "Sue" "Bob" "Tim" "Kelly"}
```

### map

```clojure
;; 构造数据
(def scores {"Fred" 1400
             "Bob" 1240
             "Angela" 1024})

;; 添加元素，使用assoc，如果key已经存在，会覆盖对应的值
user=> (assoc scores "Sally" 0)
{"Angela" 1024, "Bob" 1240, "Fred" 1400, "Sally" 0}

;; 删除元素，使用dissoc
user=> (dissoc scores "Bob")
{"Angela" 1024, "Fred" 1400}

;; 根据key查找元素，也可以把map当作函数，如(scores "Angela")
user=> (get scores "Angela")  ;; (scores "Angela")
1024

;; 使用有默认值的查找
user=> (get scores "Sam" 0)
0

;; 检查元素是否存在
user=> (contains? scores "Fred")
true
user=> (find scores "Fred")
["Fred" 1400]

;; 获取Keys或values
user=> (keys scores)
("Fred" "Bob" "Angela")
user=> (vals scores)
(1400 1240 1024)

;; 创建map，zipmap可以合并两个序列一个作为key，一个作为vals
user=> (def players #{"Alice" "Bob" "Kelly"})
user=> (zipmap players (repeat 0))
{"Kelly" 0, "Bob" 0, "Alice" 0}

;; 合并map
user=> (def new-scores {"Angela" 300 "Jeff" 900})
user=> (merge scores new-scores)
{"Fred" 1400, "Bob" 1240, "Jeff" 900, "Angela" 300}

;; 如果存在重复key时，可以使用merge-with 提供个函数进行冲突解决
user=> (def new-scores {"Fred" 500 "Angela" 900 "Sam" 1000})
user=> (merge-with + scores new-scores)
{"Sam" 1000, "Fred" 1950, "Bob" 1240, "Angela" 1924}

;; 排序map，使用sorted-map会根据key进行排序
user=> (def sm (sorted-map
                 "Bravo" 204
                 "Alfa" 35
                 "Sigma" 99
                 "Charlie" 100))
user=> (keys sm)
("Afla" "Bravo" "Chalie" "Sigma")
```



## 应用对象

```clojure
(def person
  {:first-name "Kelly"
   :last-name "Keen"
   :age 32
   :occupation "Programmer"})
```

获取属性

```clojure
user=> (get person :occupation)
"Programmer"
user=> (person :occupation)
"Programmer"
user=> (:occupation person)
"Programmer"
;; 使用关键字进行获取时，可以指定默认值
user=> (:favorite-color person "beige")
"beige"
```

更新属性

```clojure
;; 向person添加或更新属性信息
user=> (assoc person :occupation "Baker")
```

删除属性

```clojure
user=> (dissoc person :age)
```

实体嵌套

```clojure
(def company
  {:name "WidgetCo"
   :address {:street "123 Main St"
             :city "Springfield"
             :state "IL"}})

;; 可以使用 get-in 获取属性，使用assoc-in 或modify更新嵌套属性
user=> (get-in company [:address :city])
"Springfield"
user=> (assoc-in company [:address :street] "303 Broadway")
```

使用Records替换map实现的对象

```clojure
;; 定义一个对象结构
(defrecord Person [first-name last-name age occupation])

;; 根据位置创建对象
(def kelly (->Person "Kelly" "Keen" 32 "Programmer"))
;; 使用map创建对象
(def kelly (map->Person
             {:first-name "Kelly"
              :last-name "Keen"
              :age 32
              :occupation "Programmer"}))

;; 其他使用方式同map
user=> (:occupation kelly)
"Programmer"
```



## 流程控制

### 语句和表达式

在Java中，表达值返回值，语句没有返回值，但是在Clojure中一切都是表达式，都会返回值，多个表达式的情况下会返回最后一个值

### 流程控制表达式

#### if

```clojure
;; if then else
user=> (str "2 is " (if (even? 2) "even" "odd"))
"2 is even"

;; else是可选的
user=> (if (true? false) "impossible!")
nil
```

#### Truth

在Clojure中，所有的值都可以用来判断true或false, 只有值时false或者nil时结果时false,其余所有值进行逻辑判断时都是true

```clojure
user=> (if true :truthy :falsey)
:truthy
user=> (if (Object.) :truthy :falsey)
:truthy
user=> (if [] :truthy :falsey)
:truthy
user=> (if 0 :truthy :falsey)
:truthy
user=> (if false :truthy :falsey)
:falsey
user=> (if nil :truthy :falsey)
:falsey
```

#### if and do

if语句中的then和else部分只能用来执行单个表达式，可以使用`do`来创建执行多个语句

```clojure
(if (even? 5)
  (do (println "even")
    true)
  (do (println "odd")
    false))
```

#### when

when相当于简化版的`if`, 但是它支持多个语句而不用使用`do`

```clojure
(when (neg? x)
  (throw (RuntimeException. (str "x must be positive: " x))))
```

#### cond

```clojure
(let [x 5]
  (cond
    (< x 2) "x is less than 2"
    (< x 10) "x is less than 10"))
```

#### cond and else

```clojure
(let [x 11]
  (cond
    (< x 2)  "x is less than 2"
    (< x 10) "x is less than 10"
    :else  "x is greater than or equal to 10"))
```

#### case

相比`if` 和`cond`，使用其没有匹配到值时会抛出异常

```clojure
user=> (defn foo [x]
         (case x
           5 "x is 5"
           10 "x is 10"))
user=> (foo 10)
x is 10
```

#### case and else

```clojure
user=> (defn foo [x]
         (case x
           5 "x is 5"
           10 "x is 10"
           "x isn't 5 or 10"))

user=> (foo 11)
x isn't 5 or 10
```



## 迭代

### dotimes

执行n次表达值，返回nil

```clojure
user=> (dotimes [i 3]
         (println i))
0
1
2
```

### doseq

遍历序列

```clojure
user=> (doseq [n (range 3)]
         (println n))
0
1
2
```

### doseq与多个绑定值

```clojure
user=> (doseq [letter [:a :b]
               number (range 3)]
         (prn [letter number]))
[:a 0]
[:a 1]
[:a 2]
[:b 0]
[:b 1]
[:b 2]
```

### for

生成序列，绑定方式同doseq

```clojure
user=> (for [letter [:a :b]
             number (range 3)] ; list of 0, 1, 2
         [letter number])
([:a 0] [:a 1] [:a 2] [:b 0] [:b 1] [:b 2])
```



## 递归

### loop 和 recur

```clojure
(loop [i 0]
  (if (< i 10)
    (recur (inc i))  ;; 重新执行loop绑定运行
    i))
```

### defn 与 recur

```clojure
(defn increase [i]  ;; 隐士loop绑定
  (if (< i 10)
    (recur (inc i))
    i))
```



## 异常

### 异常处理

```clojure
(try
  (/ 2 1)
  (catch ArithmeticException e
    "divide by zero")
  (finally
    (println "cleanup")))
```

### 抛出异常

```clojure
(try
  (throw (Exception. "something went wrong"))
  (catch Exception e (.getMessage e)))
```

### 异常与Clojure数据

```clojure
(try
  (throw (ex-info "There was a problem" {:detail 42}))  ;; 使用ex-info设置信息和map
  (catch Exception e
    (prn (:detail (ex-data e)))))   ;; 使用ex-data从异常中获取map数据，不存在时返回nil
```



## 命名空间

命名空间可以类似理解成Java中的包名

```clojure
(ns com.some-example.my-app  ;; 命名空间
  "My app example"  ;; 文档字符串
  (:require          
    [clojure.set :as set]  ;; 使用:require表示加载clojure.set，并创建了一个别名
    [clojure.string :as str]))
```

加载java类时，使:import

```clojure
;; 引入了 Date, UUID, File 三个类
(ns com.some-example.my-app2
  (:import
    [java.util Date UUID]
	[java.io File]))
```







