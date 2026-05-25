;=====================================================
;  CRACKME #2  -  PureBasic
;  Goal: Given your NAME, find the correct SERIAL.
;  Compile with PureBasic: https://www.purebasic.com
;=====================================================

Procedure.s ComputeSerial(name$)
  Protected i, c, len
  Protected.q h          ; 64-bit accumulator (we'll fold it)
  Protected.l a, b       ; two 16-bit lanes
  Protected result$

  len = Len(name$)
  a = $1F3D              ; lane A seed
  b = $7E21              ; lane B seed

  For i = 1 To len
    c = Asc(Mid(name$, i, 1))

    ; ----- lane A: additive-rotate -----
    a = (a + (c * (i + 3))) & $FFFF
    a = ((a << 5) | (a >> 11)) & $FFFF     ; rotate left 5 within 16 bits

    ; ----- lane B: multiply-xor -----
    b = (b ! c) & $FFFF
    b = (b * 1093) & $FFFF                 ; LCG-ish multiplier
    b = (b + 18257) & $FFFF
  Next

  ; mix the two lanes into the final value
  h = (a << 16) | b
  h = h ! (h >> 7)
  h = h & $FFFFFFFF

  ; Format as GROUPS:  AAAA-BBBB-CCCC-DDDD  (each 4 hex digits)
  Protected w0, w1, w2, w3
  w0 = (a) & $FFFF
  w1 = (b) & $FFFF
  w2 = (a ! b) & $FFFF
  w3 = ((a + b) & $FFFF)

  result$ = RSet(Hex(w0), 4, "0") + "-" +
            RSet(Hex(w1), 4, "0") + "-" +
            RSet(Hex(w2), 4, "0") + "-" +
            RSet(Hex(w3), 4, "0")

  ProcedureReturn UCase(result$)
EndProcedure

;----------------------- main -----------------------
OpenConsole()

PrintN("===============================================")
PrintN("        PureBasic CRACKME  -  v1.0")
PrintN("===============================================")
PrintN("")

Print("Enter your name  : ")
Define name$ = Input()

Print("Enter your serial: ")
Define serial$ = Input()

If Len(name$) < 4
  PrintN("")
  PrintN("[!] Name must be at least 4 characters.")
  Print("Press ENTER to exit..."): Input()
  CloseConsole()
  End
EndIf

Define good$ = ComputeSerial(name$)

PrintN("")
If UCase(serial$) = good$
  PrintN("############################################")
  PrintN("#   ACCESS GRANTED - Nicely reversed!      #")
  PrintN("############################################")
Else
  PrintN("[X] WRONG SERIAL - Keep digging.")
EndIf

PrintN("")
Print("Press ENTER to exit..."): Input()
CloseConsole()
; IDE Options = PureBasic 6.40 (Windows - x64)
; CursorPosition = 84
; FirstLine = 45
; Folding = -
; EnableXP
; DPIAware
; Executable = crackme.exe