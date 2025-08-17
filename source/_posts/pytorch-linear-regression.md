---
title: 使用PyTorch实现线性回归
date: 2025-08-17 08:59:48
tags: [pytorch, 小白学机器学习]
---

之前进行过[机器学习的数学笔记-回归](/2025/03/02/machine-learing-regression/)中，主要是人工计算导数以及更新计算

本次为对应[《动手学深度学习》](https://zh-v2.d2l.ai/)线性回归部分内容，使用PyTorch 来简化实现

## 构造测试数据

找到合适的数据比较麻烦，我们可以自己生成对应的测试用的数据，添加一定的噪声

线性模型：$\mathbf{y}=\mathbf{W}\mathbf{X}+b$，其中 $\mathbf{W}$ 和 $\mathbf{X}$ 都是矩阵

比如可以是$y=w_1x_1 + b$ 也可以是 $y=w_1x_1+w_2x_2+b$ 等等

我们可以根据输入的 $\mathbf{W}$ 和 $b$ ，根据$\mathbf{W}$的形状生成对应高斯分布的$\mathbf{X}$，执行 $\mathbf{y}=\mathbf{W}\mathbf{X}+b$ 获取对应的 $y$ 值

<!-- more -->

X 的值可以从高斯分布中采样，在pytorch中使用 `torch.normal(均值, 标准差, 数据形状)` 函数



对于$y=w_1x_1 + b$ 的形式，比如 w1=5.2, b = 3，那么可以用如下方法生成X

```python
# 均值为0，标准差为1，形状为 10行1列 的数据
torch.normal(0, 1, (10, 1))

# 输出结果, 每一行对应一个x变量的值
> tensor([[ 1.7538],
        [ 0.6664],
        [-0.4381],
        [ 2.4668],
        [ 0.4584],
        [-2.2409],
        [ 1.2411],
        [ 1.0235],
        [-0.6828],
        [ 1.3618]])
```



而对于 $y=w_1x_1+w_2x_2+b$ 的形式，比如 w1=2.3, w2= 4.5,  b = 3，那么可以用如下方法生成X

```python
# 均值为0，标准差为1，形状为 5行2列 的数据，每一行对应一个x变量的值
torch.normal(0, 1, (5, 2))

# 输出结果, 每一行对应x变量的值（x1, x2）
> tensor([[ 0.7917, -0.4366],
        [-1.8961,  1.1405],
        [-0.7060,  0.1232],
        [ 0.4644,  1.7307],
        [ 2.6247, -1.2155]])
```



矩阵乘法，可以使用`torch.matmul(input, other)` 函数

```python
import torch

# 示例：二维矩阵乘法
A = torch.tensor([[1, 2], [3, 4]])  # (2, 2)
B = torch.tensor([[5, 6], [7, 8]])  # (2, 2)
C = torch.matmul(A, B)
# C = [[1*5 + 2*7, 1*6 + 2*8],
#      [3*5 + 4*7, 3*6 + 4*8]]
#   = [[19, 22],
#      [43, 50]]
```



最终生成测试数据函数定义如下：

```python
# 测试数据集构造, 生成y=Xw+b+噪声
def synthetic_data(w, b, num_examples):
    # 生成均值为0，标准差为1，行数为需要的例子数量，列数与参数中w的长度相同
    X = torch.normal(0, 1, (num_examples, len(w)))
    # 根据X的值，执行Xw+b，计算对应的Y
    y = torch.matmul(X, w) + b
    # 增加噪声(噪声为均值为0，标准差为0.01, 形状与y相同)
    y += torch.normal(0, 0.01, y.shape)
    # 返回生成的X 和 y
    return X, y
```



构造测试数据

```python
# 真实的 w 和 b
true_w = torch.tensor([2, -3.4])
true_b = 4.2

# 本次生成的测试数据
features, labels = synthetic_data(true_w, true_b, 1000)
```



## 线性回归实现

### 定义模型

```python
# 线性回归模型: y=Xw+b
def linreg(X, w, b):
    return torch.matmul(X, w) + b
```



### 初始化模型参数

随机初始化，w的两个值也是从高斯分布中采样，b的值初始化为0，requires_grad=True表示会自动计算

```python
# 均值为0, 标准差为0.01，两行一列
w = torch.normal(0, 0.01, size=(2,1), requires_grad=True)
# tensor([[-0.0130],
#        [-0.0019]], requires_grad=True)

# 一个标量，值为0
b = torch.zeros(1, requires_grad=True)
# tensor([0.], requires_grad=True)
```



### 定义损失函数

损失值就是真实值与预测值的差异，所以可以定义：真实值与预测值的差的平方和，再除以2（为了方便求导）

即：$l^{(i)}(w,b)=\frac 1 2 (\hat{y}^{(i)}-y^{(i)})^2$

```python
def squared_loss(y_hat, y):
    return (y_hat - y.reshape(y_hat.shape)) ** 2 / 2
```

我们的目标就是使损失函数最小



### 定义优化算法

根据学习率与对应的梯度，更新参数 w 和 b

```python
def sgd(params, lr, batch_size):
    # 更新参数时，需要关闭梯度计算
    with torch.no_grad():
        for param in params:
            # 这里因为梯度使用了sum 函数，所以需要除以总的数量
            param -= lr * param.grad / batch_size
            param.grad.zero_()
```



### 训练

```python
# 学习率
lr = 0.03
# 学习轮次
num_epochs = 500

for epoch in range(num_epochs):
    # 根据预测的参数，计算y预计值
    y_hat = linreg(features, w, b)
    # 计算损失函数的值
    l = squared_loss(y_hat, labels)
    # 计算梯度(backward的调用对象必须是标量，一般是求和或者计算均方误差等标量函数，这里使用求和函数)
    l.sum().backward()
    # 根据梯度更新参数，w、b
    sgd([w, b], lr, 1000)

    if epoch % 100 == 0:
        with torch.no_grad():
            train_l = squared_loss(linreg(features, w, b), labels)
            print(f'epoch {epoch + 1}, loss {float(train_l.mean()):f}')
            
# 结果：
# epoch 1, loss 13.843614
# epoch 101, loss 0.029915
# epoch 201, loss 0.000111
# epoch 301, loss 0.000047
# epoch 401, loss 0.000046
```



这时候我们可以看下计算出的参数和实际的参数值的区别

```python
w, b

# (tensor([[ 1.9998],
#         [-3.4000]], requires_grad=True),
# tensor([4.1994], requires_grad=True))
```

实际值是 w=[2, -3.4] 和 b=4.2， 已经非常接近





## PyTorch高级API实现

对于常用的线性回归等，PyTorch中已经提供了一些高级组件可以直接使用

### 数据分批读取

```python
from torch.utils import data

# 方法定义
def load_array(data_arrays, batch_size, is_train=True):
    dataset = data.TensorDataset(*data_arrays)
    return data.DataLoader(dataset, batch_size, shuffle=is_train)

# 使用
batch_size = 10
data_iter = load_array((features, labels), batch_size)
```



### 初始化模型及参数

```python
from torch import nn

net = nn.Sequential(nn.Linear(2, 1))

net[0].weight.data.normal_(0, 0.01)
net[0].bias.data.fill_(0)
```



### 定义损失函数及优化算法

```python
# 损失函数：均方误差
loss = nn.MSELoss()

# 优化算法
trainer = torch.optim.SGD(net.parameters(), lr=0.03)
```



### 训练

```python
num_epochs = 3
for epoch in range(num_epochs):
    for X, y in data_iter:
        l = loss(net(X), y)
        trainer.zero_grad()
        l.backward()
        trainer.step()
    l = loss(net(features), labels)
    print(f'epoch {epoch + 1}, loss {l:f}')
    

# epoch 1, loss 0.000225
# epoch 2, loss 0.000094
# epoch 3, loss 0.000093
```

结果

```python
w = net[0].weight.data
b = net[0].bias.data
w, b

# (tensor([[ 1.9996, -3.4005]]), tensor([4.2001]))
```







