/**************************************************************************************
 * UART Echo Test - main program
 * (Self-contained: depends only on uart.c/uart.h in this project)
 *
 * Behavior:
 *   On reset prints a banner; every character received on UART is echoed back
 *   and printed as ASCII + hex (verifies RX and TX both work).
 *
 * Test steps:
 *   1. Build & flash (close Serial Monitor first)
 *   2. Open Serial Monitor -> COM port -> 9600 baud
 *   3. Send a character (e.g. 'A') -> see "RX: 'A' (0x41)" and the echo
 **************************************************************************************/
#include "uart.h"
#include <stdio.h>      /* printf (redirected to UART by uart.c's putchar) */

void main()
{
	uart_init();        /* init UART: 9600 */

	uart_send_string("=== UART Echo Test @9600 ===\r\n");
	uart_send_string("Send any character, the board will echo it.\r\n");

	while(1)
	{
		if(rx_flag)         /* new data received? */
		{
			rx_flag = 0;    /* clear flag (required, otherwise re-processed) */
			printf("RX: '%c' (0x%x)\r\n", rx_byte, rx_byte);
			uart_send_byte(rx_byte);    /* echo back */
		}
	}
}
