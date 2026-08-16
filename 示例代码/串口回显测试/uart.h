#ifndef _UART_H
#define _UART_H

/**************************************************************
 * 串口模块（STC89C52RC · 11.0592MHz · 9600bps · 12T）
 *
 * 使用三步：
 *   1. 把 uart.c / uart.h 复制进工程（EIDE 右键添加文件）
 *   2. main() 开头调用一次 uart_init()
 *   3. 发送用 uart_send_byte / uart_send_string / printf
 *      接收自动存入 rx_byte 并置 rx_flag（轮询使用，用完清零）
 **************************************************************/

// 初始化串口：9600bps，方式1，开启接收中断
// 参数：无        返回：无
// 示例：uart_init();
void uart_init(void);

// 发送一个字节（中断驱动，自动等上一次发完，不丢数据）
// 参数：dat = 要发送的字节（0~255）   返回：无
// 示例：uart_send_byte('A');
void uart_send_byte(unsigned char dat);

// 发送字符串（遇到 '\0' 结束）
// 参数：str = 字符串首地址            返回：无
// 示例：uart_send_string("Hello\r\n");
void uart_send_string(unsigned char *str);

// printf 重定向：包含 <stdio.h> 后可直接 printf("...")，输出走串口
// 示例：printf("count: %d\r\n", counter);

// 接收结果（由串口中断自动填写，无需调用函数）：
//   rx_byte = 最新收到的字节
//   rx_flag = 1 表示有新数据；主循环处理完后必须手动清零
// 示例：if (rx_flag) { rx_flag = 0; ...使用 rx_byte... }
extern unsigned char rx_byte;
extern bit rx_flag;

#endif
