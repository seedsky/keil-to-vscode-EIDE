/**************************************************************************************
 * 串口回显测试主程序（自成体系：只依赖本文件夹的 uart.c/uart.h，无其他模块）
 *
 * 效果：
 *   复位后打印提示；电脑发什么字符，板子原样回显，
 *   并打印该字符的 ASCII 码和十六进制（验证收发双向都通）
 *
 * 测试步骤：
 *   1. 编译烧录（先关 Serial Monitor，提示上电时断电再上电）
 *   2. 打开 Serial Monitor → 选 COM 口 → 波特率 9600
 *   3. 输入框发字符（如 A）→ 看到 RX: 'A' (0x41) 和原样回显
 **************************************************************************************/
#include "uart.h"
#include <stdio.h>      // printf 用（重定向已由 uart.c 的 putchar 完成）

void main()
{
	uart_init();        // 初始化串口（9600）

	uart_send_string("=== UART Echo Test @9600 ===\r\n");
	uart_send_string("Send any character, the board will echo it.\r\n");

	while(1)
	{
		if(rx_flag)         // 收到新数据？
		{
			rx_flag = 0;    // 清标志（必须，否则重复处理）
			printf("RX: '%c' (0x%x)\r\n", rx_byte, rx_byte);  // 打印字符和十六进制
			uart_send_byte(rx_byte);    // 原样回显
		}
	}
}
