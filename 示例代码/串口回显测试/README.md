# 串口回显测试（自成体系示例包）

> 用途：验证 51 串口通信（发送 + 接收回显），可直接拷进任意 EIDE 工程使用。
> 本文件夹**零外部依赖**：只有这 5 个文件，不依赖任何公共模块（public.h 等）。

## 硬件要求

| 项目 | 要求 |
|---|---|
| 芯片 | STC89C52RC（或其他 51，改波特率公式即可） |
| 晶振 | 11.0592MHz（12T 模式） |
| 连接 | 板载 USB 转 TTL（CH340）→ USB 线连电脑 → COM 口 |

## 文件清单

| 文件 | 作用 |
|---|---|
| `uart.h` | 串口模块头文件（含每个函数的完整说明） |
| `uart.c` | 串口实现：初始化 / 发送 / 接收中断 / printf 重定向 |
| `main.c` | 回显测试主程序（发什么回什么 + 打印 ASCII/hex） |
| `.clangd` | 让 clangd 能独立分析本文件夹（VSCode 打开即零报错） |

## 使用步骤

1. **拷入工程**：把 `uart.c`、`uart.h` 复制到工程目录（如 `App/uart/`），
   EIDE 面板右键 → 添加文件，选中 `uart.c`；`main.c` 替换或参考
2. **调用**：`main()` 开头调用一次 `uart_init()`，之后：
   - 发字符串：`uart_send_string("Hello\r\n");`
   - 发字节：`uart_send_byte('A');`
   - 发格式化：`#include <stdio.h>` 后直接 `printf("x=%d\r\n", x);`
   - 收数据：主循环轮询 `if (rx_flag) { rx_flag = 0; ...用 rx_byte... }`
3. **烧录测试**：关掉串口监视器 → EIDE 烧录（断电上电）→ 打开 Serial Monitor
   → COM 口 / **9600** → 在输入框发字符，板子回显并打印 `RX: 'A' (0x41)`

> 手动命令行编译时注意：Keil 的 `INCDIR(...)` 相对路径按**当前工作目录**解析
> （不是编译器目录），所以命令行编译请用绝对路径，如
> `INCDIR(D:\Keil5\C51\C51\INC\Atmel;D:\Keil5\C51\C51\INC)`。
> EIDE 内编译不受影响（它自动管理 include 路径）。

## 函数说明（详细）

### uart_init —— 初始化串口
- 功能：配置串口方式1（8 位 UART）、9600 波特率、开启接收中断
- 参数：无
- 返回：无
- 调用时机：`main()` 开头一次
- 示例：`uart_init();`

### uart_send_byte —— 发送一个字节
- 功能：向串口发送 1 个字节（中断驱动，自动等待上一次发完，不丢数据）
- 参数：`dat` = 要发送的字节（0~255）
- 返回：无
- 示例：`uart_send_byte(0x41);`（发送大写 A）

### uart_send_string —— 发送字符串
- 功能：连续发送字符串直到 `'\0'` 结束
- 参数：`str` = 字符串首地址（指向字符数组或字符串常量）
- 返回：无
- 示例：`uart_send_string("UART OK!\r\n");`（`\r\n` 是回车换行，串口显示换行必需）

### printf —— 格式化发送（重定向后）
- 功能：Keil C51 的 `printf()` 最终调用 `putchar()`，本模块已实现 `putchar` 走串口
- 用法：`#include <stdio.h>` 后直接使用
- 示例：`printf("count: %d\r\n", counter);` `printf("RX: '%c' (0x%x)\r\n", rx_byte, rx_byte);`
- 注意：`%d` 整数、`%c` 字符、`%x` 十六进制；字符串结尾要带 `\r\n` 才换行

### 接收：rx_byte 与 rx_flag（自动工作，无需调用函数）
- 收到一个字节后，**串口中断自动**把数据存入 `rx_byte`，并置 `rx_flag = 1`
- 主循环轮询 `rx_flag`，处理完**必须手动清零** `rx_flag = 0`，否则会重复处理
- 示例：
  ```c
  if (rx_flag) {
      rx_flag = 0;                     // 先清零
      printf("收到: %c\r\n", rx_byte); // 再使用
  }
  ```

## 波特率怎么改

公式（12T）：`波特率 = 11059200 / 12 / 32 / (256 - TH1)`

| 波特率 | TH1 值 |
|---|---|
| 9600 | 0xFD（默认） |
| 4800 | 0xFA |
| 115200 | 0xFF（误差大，不推荐 12T 用） |

改法：`uart.c` 里 `TH1 = TL1 = 0xFD;` 换成对应值；Serial Monitor 波特率必须一致，否则乱码。

## 排错

| 现象 | 原因与解决 |
|---|---|
| 完全没有输出 | 没烧录成功 / 没复位 / Serial Monitor 端口选错 |
| 乱码 | 波特率不一致（代码 vs 监视器） |
| 烧录报 PermissionError | Serial Monitor 占着 COM 口，先关再烧 |
| 只能发不能收 | `ES=1; EA=1;` 被其他代码关掉；或检查中断被占用 |
