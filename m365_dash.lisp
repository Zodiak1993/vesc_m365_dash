; M365 dashboard compability lisp script
; UART Wiring: red=5V black=GND yellow=COM-TX (UART-HDX) green=COM-RX (button)+3.3V with 1K Resistor
; Tested on VESC 6.05 using M365 BLE (version 1.3.6) with spintend ubox Lite 100 100
; Edited by Zodiak: Thanks to AKA13, 1zuna and sharkboy for original script!


; -> User parameters (change these to your needs)
(def software-adc 1)
(def debounce-time 0.025)

(def min-adc-thr 0.1)
(def max-adc-thr 0.9)

(def min-adc-brake 0.1)
(def max-adc-brake 0.9)

(def vesc-high-temp 85)
(def mot-high-temp 120)

(def show-batt-in-idle 1)
(def cruise-control 1)
(def min-speed 1)
(def button-safety-speed (/ 0.1 3.6)) ; disabling button above 0.1 km/h (due to safety reasons)

; Speed modes (km/h, watts, current scale)
(def eco-speed (/ 16 3.6))
(def eco-current 0.6)
(def eco-watts 350)
(def eco-fw 0)

(def drive-speed (/ 21 3.6))
(def drive-current 0.7)
(def drive-watts 600)
(def drive-fw 0)

(def sport-speed (/ 23 3.6))
(def sport-current 1.0)
(def sport-watts 800)
(def sport-fw 0)

; Secret speed modes. To enable press the button 2 times while holding break and throttle at the same time.
(def secret-enabled 1)

(def secret-eco-speed (/ 27 3.6))
(def secret-eco-current 0.8)
(def secret-eco-watts 1200)
(def secret-eco-fw 0)

(def secret-drive-speed (/ 47 3.6))
(def secret-drive-current 0.9)
(def secret-drive-watts 1500)
(def secret-drive-fw 0)

(def secret-sport-speed (/ 1000 3.6)) ; 1000 km/h easy
(def secret-sport-current 1.0)
(def secret-sport-watts 1500000)
(def secret-sport-fw 0)

; -> Code starts here (DO NOT CHANGE ANYTHING BELOW THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING)
;##################################################################################################

; Load VESC CAN code serer
(import "pkg@://vesc_packages/lib_code_server/code_server.vescpkg" 'code-server)
(read-eval-program code-server)

; Packet handling
(uart-start 115200 'half-duplex)
(gpio-configure 'pin-rx 'pin-mode-in-pu)
(def tx-frame (array-create 14))
(bufset-u16 tx-frame 0 0x55AA)
(bufset-u16 tx-frame 2 0x0821)
(bufset-u16 tx-frame 4 0x6400)
(def uart-buf (array-create 64))

; Button handling
(def presstime (systime))
(def presses 0)

; Mode states
(def off 0)
(def lock 0)
(def speedmode 4)
(def light 0)
(def unlock 0)


; timeout
;(define last-action-time (systime))

;cruise
(def last-throttle-updated-at-time (systime))
(def last-throttle-dead-min 0)
(def last-throttle-dead-max 0)
(def cruise-after-sec 5)
(def cruise-dead-zone 0.1)
(def cruise-enabled 0)
;(def thr 0)

;adc faults
(def unplausible-adc-throttle 0)
(def unplausible-adc-brake 0)

; Sound feedback
(def feedback 0)
(def beep-time 1)

(if (= software-adc 1)
    (app-adc-detach 3 1)
    (app-adc-detach 3 0)
)

(defun beep(time count)
    {
        (set 'beep-time time)
        (set 'feedback count)
    }
)

(defun disable-cruise()
    (if (= cruise-enabled 1)
        {
            (setvar 'cruise-enabled 0)
            (app-adc-override 3 0)
        }
    )
)

(defun enable-cruise(thr)
    (if (> (get-speed) min-speed)
        {
            (setvar 'cruise-enabled 1)
            (app-adc-override 3 thr)
            (beep 2 2)
        }
    )
)


(defun turn-on-ble()
    {
        (app-adc-override 3 0) ; disable cruise button
        (set 'off 0) ; turn on
        (beep 1 1)
        (set 'unlock 0) ; Disable unlock on turn off
        (apply-mode) ; Apply mode on start-up
        (stats-reset) ; reset stats when turning on
    }
)


(defun shut-down-ble()
    {
        (if (= (+ lock off) 0) ; it is locked and off?
            {
                (app-adc-override 3 0) ; disable cruise button
                (set 'unlock 0) ; Disable unlock on turn off
                (apply-mode)
                (set 'off 1) ; turn off
                (set 'light 0) ; turn off light
                (beep 2 1) ; beep feedback
            }
        )
    }
)



(defun adc-input (buffer)
  {
          (var current-spd (* (get-speed) 3.6))  
          (var throttle (/ (bufget-u8 uart-buf 4) 77.2))
          (var brake (/ (bufget-u8 uart-buf 5) 77.2))

      ;plausibility for throttle and brake
      (if (or (< throttle 0.4) (> throttle 2.8))
          {
            (set 'unplausible-adc-throttle 1)
          })

      (if (or (< brake 0.4) (> brake 2.8))
          {
            (set 'unplausible-adc-brake 1)
          })

      ;overflow handling throttle and brake
      (if (or (< throttle 0) (> throttle 3.3))
          {
            (set 'throttle 0)
          })

      (if (or (< brake 0) (> brake 3.3))
          {
            (set 'brake 0)
          })

      ;set throttle to zero if brake is pressed
      (if (and (> (get-adc-decoded 1) min-adc-brake)
               (> current-spd min-speed))
          {
            (app-adc-override 0 0)
            (app-adc-override 1 brake)
          }
          {
            (app-adc-override 0 throttle)
            (app-adc-override 1 brake)
          })
  }
)



(defun handle-features()
    {
         (if (or (= off 1) (= lock 1) (< (* (get-speed) 3.6) min-speed))
            (if (not (app-is-output-disabled)) ; Disable output when scooter is turned off
                {
                    (app-adc-override 0 0)
                    (app-adc-override 1 0)
                    (app-disable-output -1)
                    (set-current 0)
                }

            )
            (if (app-is-output-disabled) ; Enable output when scooter is turned on
                (app-disable-output 0)
            )
        )

        (if (= lock 1)
            {
                (set-current-rel 0) ; No current input when locked
                (if (> (abs (* (get-speed) 3.6)) min-speed)
                    (set-brake-rel 1) ; Full power brake
                    (set-brake-rel 0) ; No brake
                )
            }
        )
    }
)


(defun update-dash(buffer) ; Frame 0x64
    {
        (var current-speed (* (l-speed) 3.6))
        (var battery (*(get-batt) 100))

        ; mode field (1=drive, 2=eco, 4=sport, 8=charge, 16=off, 32=lock)
        (if (= off 1)
            (bufset-u8 tx-frame 6 16)
            (if (= lock 1)
                (bufset-u8 tx-frame 6 32) ; lock display
                (if (or (> (get-temp-fet) vesc-high-temp) (> (get-temp-mot) mot-high-temp)) ; temp icon
                    (bufset-u8 tx-frame 6 (+ 128 speedmode))
                    (bufset-u8 tx-frame 6 speedmode)
                )
            )
        )
        
        ; batt field
        (bufset-u8 tx-frame 7 battery)

        ; light field
        (if (= off 0)
            (bufset-u8 tx-frame 8 light)
            (bufset-u8 tx-frame 8 0)
        )
        
        ; beep field
        (if (= lock 1)
            (if (> (abs current-speed) min-speed)
                (bufset-u8 tx-frame 9 1) ; beep lock
                (bufset-u8 tx-frame 9 0))
            (if (> feedback 0)
                {
                    (bufset-u8 tx-frame 9 1)
                    (set 'feedback (- feedback 1))
                }
                (bufset-u8 tx-frame 9 0)
            )
        )

        ; speed field
        (if (= (+ show-batt-in-idle unlock) 2)
            (if (> current-speed 1)
                (bufset-u8 tx-frame 10 current-speed)
                (bufset-u8 tx-frame 10 battery))
            (bufset-u8 tx-frame 10 current-speed)
        )
        
        ; error field
        
        (bufset-u8 tx-frame 11 (get-fault))
                
        
        (if (= unplausible-adc-throttle 1)
            {
                (bufset-u8 tx-frame 11 14)
                (set 'unplausible-adc-throttle 0)
             })
            
        (if (= unplausible-adc-brake 1)
            {
                (bufset-u8 tx-frame 11 15)
                (set 'unplausible-adc-brake 0)
             })         
        

        ; calc crc
        (var crc 0)
        (looprange i 2 12
            (set 'crc (+ crc (bufget-u8 tx-frame i))))
        (var c-out (bitwise-xor crc 0xFFFF)) 
        (bufset-u8 tx-frame 12 c-out)
        (bufset-u8 tx-frame 13 (shr c-out 8))
        
        ; write
        (uart-write tx-frame)
    }
)


(defun read-frames()
    (loopwhile t
        {
            (uart-read-bytes uart-buf 3 0)
            (if (= (bufget-u16 uart-buf 0) 0x55aa)
                {
                    (var len (bufget-u8 uart-buf 2))
                    (var crc len)
                    (if (and (> len 0) (< len 60)) ; max 64 bytes
                        {
                            (uart-read-bytes uart-buf (+ len 4) 0)
                            (looprange i 0 len
                                (set 'crc (+ crc (bufget-u8 uart-buf i))))
                            (if (=(+(shl(bufget-u8 uart-buf (+ len 2))8) (bufget-u8 uart-buf (+ len 1))) (bitwise-xor crc 0xFFFF))
                                (handle-frame (bufget-u8 uart-buf 1))
                            )
                        }
                    )
                }
            )
        }
    )
)


(defun handle-frame(code)
    {
        (if (and (= code 0x65) (= software-adc 1))
            (adc-input uart-buf)
        )
        
        (update-dash uart-buf)
    }
)


(defun handle-button()
    (if (= presses 1) ; single press
        (if (= off 1) ; is it off? turn on scooter again
            {
                (turn-on-ble)
            }
            {
                (if (= lock 0)
                    (set 'light (bitwise-xor light 1)) ; toggle light
                )
            }
        )
        (if (>= presses 2) ; double press
            {
                (if (> (get-adc-decoded 1) min-adc-brake) ; if brake is pressed
                    (if (and (= secret-enabled 1) (> (get-adc-decoded 0) min-adc-thr))
                        {
                            (set 'unlock (bitwise-xor unlock 1))
                            (beep 1 2) ; beep 2x
                            (apply-mode)
                        }
                        {
                            (set 'unlock 0)
                            (apply-mode)
                            (set 'lock (bitwise-xor lock 1)) ; lock on or off
                            (beep 1 1) ; beep feedback
                        }
                    )
                    {
                        (if (= lock 0)
                            {
                                (cond
                                    ((= speedmode 1) (set 'speedmode 4))
                                    ((= speedmode 2) (set 'speedmode 1))
                                    ((= speedmode 4) (set 'speedmode 2))
                                )
                                (apply-mode)
                            }
                        )
                    }
                )
            }
        )
    )
)


(defun shut-down-ble()
    {
        (if (= (+ lock off) 0) ; it is locked and off?
            {
                (app-adc-override 3 0) ; disable cruise button
                (set 'unlock 0) ; Disable unlock on turn off
                (apply-mode)
                (set 'off 1) ; turn off
                (set 'light 0) ; turn off light
                (beep 2 1) ; beep feedback
            }
        )
    }
)


(defun reset-button()
    {
        (set 'presstime (systime)) ; reset press time again
        (set 'presses 0)
    }
)

; Speed mode implementation


(defun apply-mode()
    (if (= unlock 0)
        (if (= speedmode 1)
            (configure-speed drive-speed drive-watts drive-current drive-fw)
            (if (= speedmode 2)
                (configure-speed eco-speed eco-watts eco-current eco-fw)
                (if (= speedmode 4)
                    (configure-speed sport-speed sport-watts sport-current sport-fw)
                )
            )
        )
        (if (= speedmode 1)
            (configure-speed secret-drive-speed secret-drive-watts secret-drive-current secret-drive-fw)
            (if (= speedmode 2)
                (configure-speed secret-eco-speed secret-eco-watts secret-eco-current secret-eco-fw)
                (if (= speedmode 4)
                    (configure-speed secret-sport-speed secret-sport-watts secret-sport-current secret-sport-fw)
                )
            )
        )
    )
)


(defun configure-speed(speed watts current fw)
    {
        (set-param 'max-speed speed)
        (set-param 'l-watt-max watts)
        (set-param 'l-current-max-scale current)
        (set-param 'foc-fw-current-max fw)
    }
)


(defun set-param (param value)
    {
        (conf-set param value)
        (loopforeach id (can-list-devs)
            (looprange i 0 5 {
                (if (eq (rcode-run id 0.1 `(conf-set (quote ,param) ,value)) t) (break t))
                false
            })
        )
    }
)


(defun l-speed()
    {
        (var l-speed (get-speed))
        (loopforeach i (can-list-devs)
            {
                (var l-can-speed (canget-speed i))
                (if (< l-can-speed l-speed)
                    (set 'l-speed l-can-speed)
                )
            }
        )

        l-speed
    }
)


(defun button-logic()
    {
        ; Assume button is not pressed by default
        (var buttonold 0)
        (loopwhile t
            {
                (var button (gpio-read 'pin-rx))
                (sleep debounce-time) ; wait to debounce
                (var buttonconfirm (gpio-read 'pin-rx))
                (if (not (= button buttonconfirm))
                    (set 'button 0)
                )
                
                (if (> buttonold button)
                    {
                        (set 'presses (+ presses 1))
                        (set 'presstime (systime))
                    }
                    (button-apply button)
                )
                
                (set 'buttonold button)
                (handle-features)
            }
        )
    }
)


(defun button-apply(button)
    {
        (var time-passed (- (systime) presstime))
        (var is-active (or (= off 1) (<= (get-speed) button-safety-speed)))

        (if (> time-passed 2500) ; after 2500 ms
            (if (= button 0) ; check button is still pressed
                (if (> time-passed 6000) ; long press after 6000 ms
                    {
                        (if is-active
                             (shut-down-ble)
                        )
                        (reset-button) ; reset button
                    }
                )
                (if (> presses 0) ; if presses > 0
                    {
                        (if is-active
                            (handle-button) ; handle button presses
                        )
                        (reset-button) ; reset button
                    }
                )
            )
        )
    }
)


; Apply mode on start-up
(apply-mode)
;(turn-on-ble)

; Spawn UART reading frames thread
(spawn 150 read-frames)
(button-logic) ; Start button logic in main thread - this will block the main thread
