# Reversing a PureBasic Crackme — and Why a FLIRT Signature Changes Everything

A walkthrough of reverse-engineering a small PureBasic console crackme in Hex-Rays IDA, showing the difference between analyzing it *without* and *with* a FLIRT signature for the PureBasic runtime.

> **Disclaimer.** The target is a crackme I wrote and compiled myself, so everything here operates on my own code. The disassembly fragments below are illustrative reconstructions meant to show the *technique*; addresses and exact register allocation will differ on your build. Replace them with your
> own IDA output when you publish.

---

## 1. The target

The crackme is a single-file PureBasic console program. Given a `NAME`, it derives a `SERIAL` of the form `AAAA-BBBB-CCCC-DDDD` and checks your input against it. Source (the part that matters):

```basic
Procedure.s ComputeSerial(name$)
  Protected i, c, len
  Protected.l a, b
  len = Len(name$)
  a = $1F3D                 ; lane A seed
  b = $7E21                 ; lane B seed
  For i = 1 To len
    c = Asc(Mid(name$, i, 1))
    a = (a + (c * (i + 3))) & $FFFF
    a = ((a << 5) | (a >> 11)) & $FFFF     ; rotate-left 5 in 16 bits
    b = (b ! c) & $FFFF
    b = (b * 1093) & $FFFF
    b = (b + 18257) & $FFFF
  Next
  w0 = a & $FFFF
  w1 = b & $FFFF
  w2 = (a ! b) & $FFFF
  w3 = (a + b) & $FFFF
  ProcedureReturn UCase(RSet(Hex(w0),4,"0") + "-" + ... )
EndProcedure
```

Two 16-bit "lanes" are folded character by character — lane A is an additive-rotate, lane B is an LCG-style multiply/xor/add — then four output words are formed and hex-formatted. Nothing cryptographic, but enough moving parts to be a realistic small target.

## 2. First contact: no signature

Load the compiled `.exe` into IDA, let auto-analysis finish, and open the Functions window. The problem is immediate: the list is dominated by anonymous routines.

```
sub_401000
sub_401120
sub_4012A0
sub_401410
sub_401560
sub_4016E0
... (dozens more)
start
```

Every PureBasic program is statically linked against the PureBasic runtime, so the binary is full of library code — string handling, console I/O, memory management — none of which is your logic. The string functions are the worst offenders, because the interesting routine (`ComputeSerial`) is *built out of* calls to them: `Len`, `Mid`, `Asc`, `Hex`, `RSet`, string concatenation,`UCase`. Without names, every one of those calls is a jump into the unknown.

A typical view of the serial routine before any cleanup:

```asm
; sub_401560
push    ebp
mov     ebp, esp
sub     esp, 2Ch
...
push    dword ptr [ebp+name]
call    sub_402110          ; ??? -> returns length
mov     [ebp+len], eax
...
mov     eax, [ebp+i]
push    1
push    eax
push    dword ptr [ebp+name]
call    sub_4021D0          ; ??? -> one char substring
push    eax
call    sub_402260          ; ??? -> char code?
mov     [ebp+c], eax
```

You can *guess* from context — "this one takes the string and returns a small int, probably length" — but you are guessing, and every guess is a place to be wrong. On a bigger binary this is where hours disappear.

## 3. The fix: a PureBasic FLIRT signature

FLIRT (Fast Library Identification and Recognition Technology) lets IDA match runtime functions against a precomputed signature and rename them automatically — the same mechanism that already names Visual C++, Delphi, and Go runtime functions for you. PureBasic has no public signature, so I built one with the
Hex-Rays FLAIR toolkit (the `sigmake` family of tools).

I'm deliberately keeping the generation process out of this write-up. PureBasic ships its runtime in a consolidated, non-standard library format rather than the plain static archives FLAIR expects, so getting from those files to a `.sig` is not the textbook `pcf`/`sigmake` one-liner — and documenting how to take that format apart strays into reverse-engineering Fantaisie Software's proprietary packaging, which their license is protective about. The PureBasic libraries are their copyrighted material. This article is about analyzing *my own* compiled binary and showing what a signature does once you have one; it is not a guide to extracting their libraries.

Once a signature exists, applying it is the standard flow: drop the `.sig` into `<IDA>\sig\pc\`, then in IDA open **View → Open subviews → Signatures**, press **Load Sig...**, and apply it.

## 4. Second contact: with the signature applied

IDA reprocesses the binary and the Functions window transforms:

```basic
PB_Len
PB_Mid2
PB_Asc
PB_Hex
PB_RSet2
PB_Console_Print
PB_Console_Input
...
```

The runtime is labeled, which means the *non*-labeled function is — by elimination — your code. The serial routine reads completely differently now:

```asm
; ComputeSerial
push    ebp
mov     ebp, esp
sub     esp, 2Ch
...
push    [ebp+name]
call    PB_Len
mov     [ebp+len], eax
...
push    1
push    [ebp+i]
push    [ebp+name]
call    PB_Mid2
push    eax
call    PB_Asc     ; c = Asc(Mid(name$, i, 1))
mov     [ebp+c], eax
```

That single `call PB_String_Mid` / `call PB_Ascii_Character` pair instantly maps to `Asc(Mid(name$, i, 1))` in the source. The scaffolding has become readable, and you can spend your attention on the part that matters — the lane math.

## 5. Recovering the algorithm

With the library noise gone, the loop body is easy to follow. Lane A:

```asm
mov     eax, [ebp+c]
mov     ecx, [ebp+i]
add     ecx, 3
imul    eax, ecx               ; c * (i + 3)
add     eax, [ebp+a]
and     eax, 0FFFFh            ; & $FFFF
mov     [ebp+a], eax
; rotate-left 5 within 16 bits
mov     eax, [ebp+a]
mov     ecx, eax
shl     eax, 5
shr     ecx, 0Bh               ; >> 11
or      eax, ecx
and     eax, 0FFFFh
mov     [ebp+a], eax
```

That is line-for-line the source: `a = (a + c*(i+3)) & 0xFFFF`, then a 16-bit rotate-left by 5. Lane B shows the tell-tale LCG constants in the immediates — the multiply by `1093` (`0x445`) and the add of `18257` (`0x4751`).

From here, writing a keygen is mechanical: reimplement the two lanes, fold them into the four output words, format as `AAAA-BBBB-CCCC-DDDD`. The reversing was the hard part, and the signature is what made it tractable.

## 6. Takeaway

A FLIRT signature does not "crack" anything — it removes the part of the work that is pure noise. On this toy the savings are minutes; on a real-world PureBasic binary with hundreds of runtime calls, separating the author's logic from the runtime is most of the battle, and a signature does it in one keypress.

### A note on the signature

The signature used here was generated locally from a PureBasic installation — nothing of  Fantaisie Software's is redistributed in this article. Whether a ready-made `.sig` can be shared publicly is a separate question I've put to Fantaisie directly, since the libraries it derives from are their copyrighted material. Until then, this write-up stands on its own: it shows the *effect* of a signature on a real PureBasic binary, which is the part worth seeing.
