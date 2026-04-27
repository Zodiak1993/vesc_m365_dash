; G30 dashboard compability lisp script - untested !!!
; UART Wiring: red=5V black=GND yellow=COM-TX (UART-HDX) green=COM-RX (button)+3.3V with 1K Resistor
; Edited by Zodiak: Thanks to AKA13, 1zuna and sharkboy for original script!
; ==============================================================================================================================
; -> User parameters (change these to your needs)
; ==============================================================================================================================

(def software-adc 1)                      ; if set to "1" than software adc is enabled - if set to "0" hardware adc is enabled

(def min-adc-thr 0.1)                     ; no need to change this value
(def max-adc-thr 0.9)                     ; no need to change this value
(def min-adc-brake 0.1)                   ; no need to change this value
(def max-adc-brake 0.9)                   ; no need to change this value

(def vesc-high-temp 60.0)                 ; set limit for controller temperature warning (degree)
(def mot-high-temp 100.0)                 ; set limit for motor temperature warning (degree)

(def cruise-control 1)                    ; set this value to "1" to enable cruise control in secret mode; set it to 0 to disable it
(def cruise-seq-time 0.25)                ; maximum allowed time between sequence steps in seconds - lower value and it gets harder to activate cruise control!

(def use-mph 0)                           ; set this value to "1" for mph and "0" for km/h - this only affects the displayed speed on the dash!
(def show-bat-in-idle 1)                  ; set to "1" to show battery percentage in idle (only in secret mode)
(def min-speed 1.0)                       ; minimum speed in km/h to "activate" the motor, you can also set this to "0"
(def button-safety-speed 0.1)             ; disabling button above 0.1 km/h (due to safety reasons)
(def taillight-brightness 0.30)           ; taillight brightness 0.0 to 1.0 - 1.0 max brightness
(def brakelight-offset 0.00)              ; brakelight offset (taillight(0.30) + offset(0.70)) = brakelight (1.00)) /// set to 0.00 if you want to disable brakelight!

; Speed modes eco/drive/sport (always km/h and not mph!, current scale, watts, field weakening, overmodulation)

(def eco-speed 7.0)                       ; maximum speed in km/h - in this example 7 km/h
(def eco-current 0.3)                     ; scaled maximum current, 0.0 to 1.0 - in this example 30% of the defined "motor current max"
(def eco-watts 350)                       ; maximum wattage in W - in this example 350 W
(def eco-fw 0)                            ; maximum field weakening current - in this example 0 A 
(def eco-ovmfactor 1.00)                  ; overmodulation factor - max recommended 1.15  

(def drive-speed 16.0)
(def drive-current 0.5)
(def drive-watts 600)
(def drive-fw 0)
(def drive-ovmfactor 1.00)

(def sport-speed 22.5)
(def sport-current 0.7)
(def sport-watts 900)
(def sport-fw 0)
(def sport-ovmfactor 1.00)


; Secret speed modes. To enable press the button 2 times while holding brake (between 10%-90%) and throttle (between 10%-90%) at the same time.
; Press throttle and brake fully at standstill (< 1 km/h) to disable the secret mode!

(def secret-enabled 1)

(def secret-eco-speed 28.0)
(def secret-eco-current 0.7)
(def secret-eco-watts 5000)
(def secret-eco-fw 0)
(def secret-eco-ovmfactor 1.00)

(def secret-drive-speed 100.0)
(def secret-drive-current 1.0)
(def secret-drive-watts 5000)
(def secret-drive-fw 0)
(def secret-drive-ovmfactor 1.15)

(def secret-sport-speed 100.0)            ; 100 km/h easy
(def secret-sport-current 1.0)
(def secret-sport-watts 5000)
(def secret-sport-fw 30.0)
(def secret-sport-ovmfactor 1.15)

; ==============================================================================================================================
; -> Code starts here (DO NOT CHANGE ANYTHING BELOW THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING)
; ==============================================================================================================================

(import "pkg@://vesc_packages/lib_code_server/code_server.vescpkg" 'code-server)           ; load VESC CAN code server
(read-eval-program code-server)

(uart-start 115200 'half-duplex)
(gpio-configure 'pin-rx 'pin-mode-in-pu)
(define tx-frame (array-create 15))
(bufset-u16 tx-frame 0 0x5AA5) ;Ninebot protocol
(bufset-u8 tx-frame 2 0x06) ;Payload length is 5 bytes
(bufset-u16 tx-frame 3 0x2021) ; Packet is from ESC to BLE
(bufset-u16 tx-frame 5 0x6400) ; Packet is from ESC to BLE
(def uart-buf (array-create 64))

(def presstime (systime))                                                                  ; button handling
(def presses 0)

(def off 0)                                                                                ; mode states
(def lock 0)
(def speedmode 4)
(def light 0)
(def secret 0)
(def prev-bat 0)
(def bms-active 0)

(def cruise-enabled 0)                                                                     ; 1 = cruise is currently active, 0 = inactive
(def cruise-seq-state 0)                                                                   ; state of the cruise activation sequence (0..3)
(def cruise-seq-timer 0)                                                                   ; timestamp of the last sequence step (systime)                                                    
(def last-cruise-activated-at (systime))                                                   ; timestamp of last cruise activation (for 5s lock)
(def cruise-beep-done 0)

(def unplausible-adc-throttle 0)                                                           ; adc fault throttle
(def unplausible-adc-brake 0)                                                              ; adc fault brake                                                            

(def feedback 0)                                                                           ; sound feedback
(def beep-time 0)                                                                          

(pwm-start 200 0)                                                                          ; taillight start pwm (200Hz / 0% duty)

(if (= cruise-control 1)
    (app-adc-detach 2 1))                                                                  ; detach buttons
    
(if (= software-adc 1)                                                                     ; detach buttons and ADC                                                                    
    (app-adc-detach 3 1))                                                                                                                                          ; detach ADC 
;==================================================================================================================================================

(defun beep (time count)                                                                   ; beep routine
      (progn                                                                  
      (set 'beep-time time)                                                                ; set beep duration
      (set 'feedback count)))                                                              ; set beep count

;==================================================================================================================================================

(defun turn-on-ble ()                                                                      ; turn-on BLE routine
      (progn
      (set 'speedmode 4)                                                                   ; set mode to sport
      (apply-mode)                                                                         ; apply mode on start-up
      (set 'off 0)                                                                         ; turn on
      (beep 1 1)                                                                           ; beep feedback (duration & count)
      (stats-reset)))                                                                      ; reset stats (VESC - RT DATA) when turning on

;==================================================================================================================================================

(defun shut-down-ble ()                                                                    ; shut-down BLE routine
  (if (and (= lock 0) (= off 0))                                                           ; it is unlocked and on?
        (progn
        (set 'secret 0)                                                                    ; disable secretmode on turn off
        (set 'off 1)                                                                       ; turn off
        (set 'light 0)                                                                     ; turn off light
        (pwm-set-duty 0.0)                                                                 ; turn off taillight
        (apply-mode)                                                                       ; apply mode
        (beep 2 1))))                                                                      ; beep feedback (duration & count)  

;==================================================================================================================================================

(defun adc-input (buffer)                                                                  ; Frame 0x65
    (let ((throttle (/ (bufget-u8 uart-buf 5) 77.3))                                       ; 255/3.3 = 77.3 ???? auf buffer umschreiben?
          (brake    (/ (bufget-u8 uart-buf 6) 77.3)))                                      ; 255/3.3 = 77.3 ???? auf buffer umschreiben
    (progn
      (set 'unplausible-adc-throttle (if (or (< throttle 0.4) (> throttle 2.8)) 1 0))
      (set 'unplausible-adc-brake (if (or (< brake 0.4) (> brake 2.8)) 1 0))
      (if (< throttle 0)   (setf throttle 0))                                              ; clamp low
      (if (> throttle 3.3) (setf throttle 0))                                              ; clamp high
      (if (< brake 0)      (setf brake 0))                                                 ; clamp low
      (if (> brake 3.3)    (setf brake 3.3))                                               ; clamp high
      (app-adc-override 0 throttle)                                                        ; override throttle
      (app-adc-override 1 brake))))                                                        ; override brake

;==================================================================================================================================================

(defun cruise-control-logic (thr brake speed-kmh now)
  (progn
    (if (and (> cruise-seq-state 0) (> (secs-since cruise-seq-timer) cruise-seq-time))    ; Timer expired ? reset sequence
        (set 'cruise-seq-state 0))

    (if (and (= cruise-enabled 0) (= secret 1) (> speed-kmh 3) (> (secs-since last-cruise-activated-at) 5))    ; requires at least 5s since the last activation to prevent rapid re-triggers
        (progn
          (if (= cruise-seq-state 0)
              (if (< thr min-adc-thr)
                  (progn
                    (set 'cruise-seq-state 1)
                    (set 'cruise-seq-timer now))))
          (if (= cruise-seq-state 1)
              (if (> thr max-adc-thr)
                  (if (< (secs-since cruise-seq-timer) cruise-seq-time)
                      (progn
                        (set 'cruise-seq-state 2)
                        (set 'cruise-seq-timer now)))))
          (if (= cruise-seq-state 2)
              (if (< thr min-adc-thr)
                  (if (< (secs-since cruise-seq-timer) cruise-seq-time)
                      (progn
                        (set 'cruise-seq-state 3)
                        (set 'cruise-seq-timer now)))))
          (if (= cruise-seq-state 3)
              (if (> thr max-adc-thr)
                  (if (< (secs-since cruise-seq-timer) cruise-seq-time)
                      (set 'cruise-seq-state 4))))
          (if (= cruise-seq-state 4)
              (if (< thr min-adc-thr)
                  (progn
                    (set 'cruise-enabled 1)
                    (app-adc-override 3 1)
                    (set 'last-cruise-activated-at now)
                    (set 'cruise-seq-state 0))))))

    (if (or (> thr min-adc-thr) (> brake min-adc-brake))     ; Disable cruise if throttle or brake is pressed
        (progn
          (set 'cruise-enabled 0)
          (app-adc-override 3 0)))

    ;; Beep logic
    (if (and (= cruise-enabled 1) (= cruise-beep-done 0) (> (secs-since last-cruise-activated-at) 0.2))
        (progn
          (beep 2 3)                                         ; beep 0.2s after cruise control activation, if you play around with throttle you are fine now ...
          (set 'cruise-beep-done 1)))

    (if (and (= cruise-enabled 0)(= cruise-beep-done 1))     ; abort any pending cruise beep immediately when cruise control is disabled
        (progn
          (beep 0 0)
          (set 'cruise-beep-done 0)))))

;==================================================================================================================================================

  (defun handle-features()
  (progn
    (var speed-kmh (* (get-speed) 3.6))
    (var thr (get-adc-decoded 0))
    (var brake (get-adc-decoded 1))
    (var now (systime))
    
    (if (= cruise-control 1)
        (cruise-control-logic thr brake speed-kmh now))
   
    (if (= software-adc 0)
        (progn
        (set 'unplausible-adc-throttle (if (let ((v (get-adc 0))) (or (< v 0.4) (> v 2.8))) 1 0))
        (set 'unplausible-adc-brake    (if (let ((v (get-adc 1))) (or (< v 0.4) (> v 2.8))) 1 0))))    ; plausibility check for brake    (Adc voltage 1 outside the valid range of 0.4V and 2.8V)       
          
    (if (and (> brake min-adc-brake) (> brakelight-offset 0) (= lock 0) (= off 0))                     ; taillight & brakelight logic
        (pwm-set-duty (if (> (+ taillight-brightness brakelight-offset) 1.0)
                          1.0
                          (+ taillight-brightness brakelight-offset)))
        (if (= light 1)
            (pwm-set-duty taillight-brightness)
            (pwm-set-duty 0.0)))
        
    (if (and (= secret 1) (> thr max-adc-thr) (> brake max-adc-brake) (< speed-kmh 1))                 ; secret mode reset
        (progn
            (set 'secret 0)
            (set 'speedmode 4)
            (apply-mode)))

    (if (or (= off 1) (= lock 1) (<= (+ 0.0001 speed-kmh) min-speed))                                  ; Off/Lock/Min-speed --> disable output
        (if (not (app-is-output-disabled))
            (progn
                (app-adc-override 0 0)
                (app-disable-output -1)
                (set-current 0)))                
        (if (app-is-output-disabled)
            (app-disable-output 0)))))
            
;==================================================================================================================================================

(defun update-dash(buffer) ; Frame 0x64
     (progn
        (var current-speed (* (l-speed) 3.6))
        (var battery 0)
        (var adc-num (get-bms-val 'bms-temp-adc-num))
        (var bat_temp1 0)
        (var bat_temp2 0)
        (var bat_temp_warning 0)

        (if (> adc-num 1)
            (set 'bat_temp1 (get-bms-val 'bms-temps-adc 1)))
        (if (> adc-num 2)
            (set 'bat_temp2 (get-bms-val 'bms-temps-adc 2)))
            
        (if (or (< bat_temp1 0) (> bat_temp1 50) (< bat_temp2 0) (> bat_temp2 50))                                         ; check if both temp sensors of the battery are between 0 and 50 degree
            (set 'bat_temp_warning 1)                                                                                      ; set warning
            (set 'bat_temp_warning 0))                                                                                     ; disable warning
 
        (if (> (get-bms-val 'bms-soc) 0) (set 'bms-active 1))                                                              ; if a bms returns a value -> bms active
        (set 'battery (round (* (if (= bms-active 1) (get-bms-val 'bms-soc) (get-batt)) 100)))                             ; use internal SoC (State of Charge) or use BMS-SoC
        (if (and (= bms-active 1) (= battery 0) (> prev-bat 1)) (set 'battery prev-bat) (set 'prev-bat battery))           ; prevents sudden drops to 0% if the previous value was above 1%; 

        (if (= off 1)
            (bufset-u8 tx-frame 7 16)                                                                                      ; mode field (1=drive, 2=eco, 4=sport, 8=charge, 16=off, 32=lock)
            (if (= lock 1)
                (bufset-u8 tx-frame 7 32)                                                                                  ; lock display
                (if (or (>= (get-temp-fet) vesc-high-temp) (>= (get-temp-mot) mot-high-temp) (= bat_temp_warning 1))       ; temp icon
                    (bufset-u8 tx-frame 7 (+ 128 speedmode))
                    (bufset-u8 tx-frame 7 speedmode))))
        
        (if (= use-mph 1)
            (bufset-u8 tx-frame 7 (+ (bufget-u8 tx-frame 7) 64)))    
        
        (bufset-u8 tx-frame 8 battery)                                                                                     ; batt field

        (if (= off 0)                                                                                                      ; light field
            (bufset-u8 tx-frame 9 light)
            (bufset-u8 tx-frame 9 0))
        
        (if (= lock 1)                                                                                                     ; beep field
            (if (> (abs current-speed) 0.1)
                (bufset-u8 tx-frame 10 1)                                                                                   ; beep lock
                (bufset-u8 tx-frame 10 0))
            (if (> feedback 0)
                (progn
                    (bufset-u8 tx-frame 10 beep-time)
                    (set 'feedback (- feedback 1)))
                    (bufset-u8 tx-frame 10 0)))
                                        
        (if (and (= show-bat-in-idle 1) (= secret 1))                                                                     ; speed field                                       
            (if (> current-speed 1)
                (bufset-u8 tx-frame 11 (round (* current-speed (if (= use-mph 1) 0.62 1))))
                (bufset-u8 tx-frame 11 battery))
            (bufset-u8 tx-frame 11 (round (* current-speed (if (= use-mph 1) 0.62 1)))))

        (bufset-u8 tx-frame 12 (get-fault))
        (if (= unplausible-adc-throttle 1) (bufset-u8 tx-frame 12 14))
        (if (= unplausible-adc-brake 1) (bufset-u8 tx-frame 12 15))
        
        (if (and (= (get-fault) 0) (= unplausible-adc-throttle 0) (= unplausible-adc-brake 0) (= cruise-beep-done 1) (< (secs-since last-cruise-activated-at) 4) )
            (bufset-u8 tx-frame 12 (round (* current-speed (if (= use-mph 1) 0.62 1)))))
                             
        (var crc 0)                                                                                                        ; calc crc
        (looprange i 2 13
            (set 'crc (+ crc (bufget-u8 tx-frame i))))
        (var c-out (bitwise-xor crc 0xFFFF)) 
        (bufset-u8 tx-frame 13 c-out)
        (bufset-u8 tx-frame 14 (shr c-out 8))
        (uart-write tx-frame)))                                                                                            ; write

;==================================================================================================================================================

(defun read-frames()
    (loopwhile t
        {
            (uart-read-bytes uart-buf 3 0)
            (if (= (bufget-u16 uart-buf 0) 0x5aa5)
                {
                    (var len (bufget-u8 uart-buf 2))
                    (var crc len)
                    (if (and (> len 0) (< len 60)) ; max 64 bytes
                        {
                            (uart-read-bytes uart-buf (+ len 6) 0) ;read remaining 6 bytes + payload, overwrite buffer

                            (let ((code (bufget-u8 uart-buf 2)) (checksum (bufget-u16 uart-buf (+ len 4))))
                                {
                                    (looprange i 0 (+ len 4) (set 'crc (+ crc (bufget-u8 uart-buf i))))    
                                
                                    (if (= checksum (bitwise-and (+ (shr (bitwise-xor crc 0xFFFF) 8) (shl (bitwise-xor crc 0xFFFF) 8)) 65535)) ;If the calculated checksum matches with sent checksum, forward comman
                                        (handle-frame code)
                                    )
                                }
                            )
                        }
                    )
                }
            )
        }
    )
)

;==================================================================================================================================================

(defun handle-frame(code)
    {
        (if (and (= code 0x65) (= software-adc 1))
            (adc-input uart-buf)
        )
        
        (if(= code 0x64)
            (update-dash uart-buf)
        )
    }
)

;==================================================================================================================================================

(defun apply-mode ()
  (cond
        ((= speedmode 1) (if (= secret 0) (configure-speed drive-speed drive-watts drive-current drive-fw drive-ovmfactor)
                                          (configure-speed secret-drive-speed secret-drive-watts secret-drive-current secret-drive-fw secret-drive-ovmfactor)))
                                      
        ((= speedmode 2) (if (= secret 0) (configure-speed eco-speed eco-watts eco-current eco-fw eco-ovmfactor)
                                          (configure-speed secret-eco-speed secret-eco-watts secret-eco-current secret-eco-fw secret-eco-ovmfactor)))
                                      
        ((= speedmode 4) (if (= secret 0) (configure-speed sport-speed sport-watts sport-current sport-fw sport-ovmfactor)
                                          (configure-speed secret-sport-speed secret-sport-watts secret-sport-current secret-sport-fw secret-sport-ovmfactor)))))
                                          
;==================================================================================================================================================

(defun configure-speed (speed watts current fw ovm)
  (progn
    (set-param 'max-speed (/ speed 3.6))
    (set-param 'l-watt-max watts)
    (set-param 'l-current-max-scale current)
    (set-param 'foc-fw-current-max fw)
    (set-param 'foc-overmod-factor ovm)))

;==================================================================================================================================================

(defun set-param (param value)
  (progn
    (conf-set param value)
    (loopforeach id (can-list-devs)
      (progn
        (looprange i 0 5
          (progn
            (if (eq (rcode-run id 0.1 `(conf-set (quote ,param) ,value)) t)
                (break t))
            false))))))

;==================================================================================================================================================

(defun l-speed ()
  (progn
    (var l-speed (get-speed))
    (loopforeach i (can-list-devs)
      (progn
        (var l-can-speed (canget-speed i))
        (if (< l-can-speed l-speed)
            (set 'l-speed l-can-speed))))
    l-speed))

;==================================================================================================================================================

(defun handle-button ()
        (if (= presses 1)
            (if (= lock 0)
                (set 'light (bitwise-xor light 1)))
        
        (if (>= presses 2)
            (if (and (> (get-adc-decoded 1) min-adc-brake) (< (get-adc-decoded 1) max-adc-brake))                          ; if brake is pressed
                (if (and (= secret-enabled 1) (= secret 0) (> (get-adc-decoded 0) min-adc-thr) (< (get-adc-decoded 0) max-adc-thr))
                    (progn
                        (beep 1 2)                                                                                         ; beep 2x
                        (set 'secret 1)
                        (apply-mode))
                    (progn
                        (set 'lock (bitwise-xor lock 1))                                                                   ; lock on or off
                        (beep 1 1))                                                                                        ; beep feedback
                )
                (if (= lock 0)
                    (progn
                        (cond
                            ((= speedmode 1) (set 'speedmode 4))
                            ((= speedmode 2) (set 'speedmode 1))
                            ((= speedmode 4) (set 'speedmode 2)))
                        (apply-mode)))))))

;==================================================================================================================================================

(defun button-logic ()
 (progn
  (var stable-button 0)
  (var counter 0)
  (var threshold 4)

  (loopwhile t
   (progn
    (var button (bitwise-xor (gpio-read 'pin-rx) 1))            ; button active-low -> invert
    (if (= button 1)                                            ; integrator debounce
        (if (< counter threshold)
            (set 'counter (+ counter 1)))
        (if (> counter 0)
            (set 'counter (- counter 1))))

    (if (and (= counter threshold) (= stable-button 0))
        (progn
        (set 'stable-button 1)
            (if (= off 1)
            (progn
                (turn-on-ble)
                (reset-button))
            (progn
                (set 'presses (+ presses 1))
                (set 'presstime (systime))))))

    (if (and (= counter 0) (= stable-button 1))                 ; falling edge (button release)
        (set 'stable-button 0))

    (button-apply stable-button)
    (handle-features)
    (sleep 0.01)))))
    
;==================================================================================================================================================

(defun button-apply(button)
    (progn       
        (var time-passed (- (systime) presstime))
        (var is-inactive (or (= off 1) (<= (* 3.6 (get-speed)) button-safety-speed)))

        (if (> time-passed 2500)                                ; after 250 ms
            (if (= button 1)                                    ; check button is still pressed
                (if (and (> time-passed 10000) (> presses 0))   ; long press after 1000 ms
                    (progn
                        (if is-inactive (shut-down-ble))                                               
                        (reset-button)))                        ; reset button                    
                (if (> presses 0)                               ; if presses > 0
                    (progn
                        (if is-inactive (handle-button))        ; handle button presses
                        (reset-button)))))))                    ; reset button
                    
;==================================================================================================================================================

(defun reset-button ()
  (progn
    (set 'presstime (systime))
    (set 'presses 0)))

;==================================================================================================================================================

(apply-mode)                                                    ; Apply mode on start-up
(spawn 150 read-frames)                                         ; Spawn UART reading frames thread
(button-logic)                                                  ; Start button logic in main thread - this will block the main threadmaybe :)
