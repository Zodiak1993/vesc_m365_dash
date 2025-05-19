# VESC M365 Dash
Allows you to connect your XIAOMI display to VESC controller. Code is working for 3 months and 1000km without problems - still use at your own risk!

# My Changes

- [x] Debounce Time (30ms) as a variable, because double key presses were almost not detected with my original m365 dashboard.
- [x] Motor Temp and Mosfet Temp warning limits as variables, making them easy to change.
- [x] The light can no longer be turned on or off in the Lock Mode.
- [x] Lock Mode: The scooter now also brakes and beeps when pushed backward.
- [x] When the brake & gas are applied simultaneously, the gas is set to 0. Previously, 100% gas & 50% brake would result in 50% gas.
- [x] Plausibility check for gas and brake (detecting disconnection of the brake or gas must be detected; Errors 14 & 15 on the dashboard).
- [x] Start Secret Mode when the brake is between 10% and 90% AND the gas is between 10% and 90% AND a double-click on the button!
- [x] Exit Secret Mode when the brake and gas are fully "pressed" simultaneously while standing still.
- [x] mph Mode (speed-factor) - this affects only the displayed speed on the dashboard!
- [x] After turning off the dashboard, the last mode is not used, but the Sport Mode is set when turning on (logic like the original).
- [x] Added a few comments to the code.
- [x] Round speed value on display (before 22.9 km/h was 22 km/h - now 22.9 km/h is 23 km/h)
- [x] If you use the lock mode, the secret mode will NOT be reset! When the Lock Mode is exited, the last used mode (sport, drive, walk) is restored.   
- [x] Control the taillight with a MOSFET via the servo pin (Small Sketch of a Circuit-Diagram follows...time is limited :) )

  
# Upcoming Tasks

- [ ]Implement cruise control.


## How
Do you want to use your Xiaomi or NineBot BLE with a VESC controller? This is the right place for you! \
Read one of the guides below to get started.

- [DE Guide](/guide/DE.md)
- [German Rollerplausch Guide](https://rollerplausch.com/threads/vesc-controller-einbau-1s-pro2-g30.6032/)

## Which version should I use?

If you are running **VESC 6.05**, use these:
- **M365**: https://github.com/m365fw/vesc_m365_dash/blob/main/m365_dash.lisp
- **How-To** Video: https://www.youtube.com/watch?v=kX8PsaxfoXQ

## How do I wire it?
<span style="color:rgb(184, 49, 47);">Red </span>to 5V \
<span style="color:rgb(209, 213, 216);">Black </span>to GND \
<span style="color:rgb(250, 197, 28);">Yellow </span>to TX (UART-HDX) \
<span style="color:rgb(97, 189, 109);">Green </span>to RX (Button) \
1k Ohm Resistor from <span style="color:rgb(251, 160, 38);">3.3V</span> to <span style="color:rgb(97, 189, 109);">RX (Button)</span>

![image](guide/imgs/23999.png)

## Features
- [x] Multiple speed modes (Press twice)
- [x] Secret speed modes (Hold throttle between 10% & 90% and brake between 10% & 90% and press button twice)
- [x] Lock mode with beeping and braking (Press twice while holding break)
- [x] Motor start speed feature (More secure)
- [x] Shutdown feature (Long press to turn off)
- [x] Battery Idle % on Secret Sport Mode

## Fixed to be done
- [x] ~~Figure out why 0x64 packets are not being read. (on my setup)~~ (Can be ignored due to the fact that we do not have to receive any 0x64 packets to sent our own 0x64 back)
- [x] ~~Figure out why button reading is randomly~~ (can be fixed with 470R resistor between 3.3v and RX and capacitor on 3.3v+GND)

## Tested on
### BLEs
- Clone M365 PRO Dashboard ([AliExpress](https://s.click.aliexpress.com/e/_9JHFDN))
- Original DE-Edition PRO 2 Dashboard

### VESCs
- Ubox (Best choice):
    - Single Ubox 80v 100A Alu PCB ([Spintend](https://spintend.com/collections/diy-electric-skateboard-parts/products/single-ubox-aluminum-controller-80v-100a-based-on-vesc?ref=1zuna))
- 75100 Box:
    - Makerbase 75100 VESC ([AliExpress](https://s.click.aliexpress.com/e/_DmJxqxr) - 75€)
    - Flipsky 75100 VESC ([Banggood](https://banggood.onelink.me/zMT7/zmenvmm2) - with Honey Add-On about 87€)

- 75100 Alu PCB:
    - Makerbase 75100 Alu PCB ([AliExpress](https://s.click.aliexpress.com/e/_DE9TKAl) - 95€)
    - Flipsky 75100 Alu PCB ([AliExpress](https://s.click.aliexpress.com/e/_DEXNhX3) - 151€)

- 75200 Alu PCB (Top Performance):
    - Makerbase 75200 Alu PCB ([AliExpress](https://s.click.aliexpress.com/e/_Dk3ucKd) - 143€)
    - Flipsky 75200 Alu PCB ([AliExpress](https://s.click.aliexpress.com/e/_DkxlJbj) - 266€)

- More recommended VESCs:
    - MP2 300A 100V/150V VESC ([GitHub](https://github.com/badgineer/MP2-ESC) - DIY)
    - and many more... use whatever you like.

#### Requirements on VESC
Requires 6.05 VESC firmware. \
Can be found here: https://vesc-project.com/

## Worth to check out!
https://github.com/Koxx3/SmartESC_STM32_v2 (VESC firmware for Xiaomi ESCs)
