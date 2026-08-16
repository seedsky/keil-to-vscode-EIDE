/**************************************************************************************
C51 检测工程（配合 scripts/4-verify.ps1 使用）
本文件故意覆盖 C51 的"疑难语法"，用于检测 clangd 配置是否正常：
  - #include <REGX52.H>          头文件路径（-I）是否生效
  - sbit LED = P2^0;             sbit 映射
  - unsigned char buf _at_ 0x30;  _at_ 无括号写法（抑制清单）
  - interrupt 1 using 1          中断无括号写法（抑制清单）
  - #include <stdio.h>           Keil stdio.h 的 size_t 冲突（抑制清单）
正常结果：clangd 0 诊断 + Keil 编译 0 错误
***************************************************************************************/
#include <REGX52.H>
#include <stdio.h>

sbit LED = P2^0;                // P2^0 引脚
unsigned char buf _at_ 0x30;    // 变量定位到 0x30

void timer0_isr() interrupt 1 using 1
{
    LED = !LED;
    buf++;
}

void main(void)
{
    TMOD = 0x01;    // T0 方式1（16位定时）
    TH0  = 0xFC;    // 定时初值
    TL0  = 0x18;
    ET0  = 1;       // 开 T0 中断
    EA   = 1;       // 开总中断
    TR0  = 1;       // 启动 T0
    printf("C51 clangd check OK\r\n");
    while(1)
    {
    }
}
