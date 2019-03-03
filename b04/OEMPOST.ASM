        page    57, 132
        title   OEM Specific Routines
        subttl  OEM.ASM - Copyright (C) 1990-1998 Elpin Systems, Inc.
;
;       OEMPOST.ASM - OEM POST specific routines
;
;       Routines in this file:
;       OEMInitBIOS             Initialize and determine if the BIOS should be "setup"
;       OEMInitWakeUp           Called at the beginning of the boot process
;       OEMNoMonitor            Handle the situation when no monitor is attached
;       OEMSignOn               Display an OEM specific sign on message
;       InitIOBase              Return the I/O base for the 3Dfx extended I/O
;       InitRegisters           Initialize the 3Dfx register set
; Patch32KROM                   Patch the ROM size for a 32K BIOS.

;       Written by:     Kaymann L. Woo
;       Date:           5/11/99
;       $Revision$
;       $Date$
;       $Log$
;       $Log$
;;
;; 11    9/04/99 5:53p Kaymann
;; In Patch32KROM, added code to recalculate the BIOS checksum.
;;
;; 10    9/02/99 5:39p Kaymann
;; Renamed the refereces to FLD_CRT to FLD_CRT_ACTIVE.
;;
;; 9     7/28/99 2:54p Kaymann
;; Created the following routines for reading the panel size:
;; DeterminePanelSize and CheckIfSupportedPanelSize.
;;
;; Moved the following routines from OEM.ASM into OEMPOST.ASM:
;; CheckFPSideScaling and CheckForPanel.
;;
;; Created the routine CalcNVRAMchecksum which calcaultes and writes the
;; Checksum of the NVRAM to byte offset 127.  This routine is called
;; after writing the NVRAM.
;;
;; In OemNoMonitor, changed thecode to set TV active to use the
;; FLD_TV_ACTIVE equate instead of the 020h value.
;;
;; 8     7/23/99 4:28p Kaymann
;; Removed the PUSH and POP BX call from the TV code in InitRegisters.
;; This fixes the system hang bug when not doing TV autodetection.
;;
;; 7     7/22/99 4:43p Kaymann
;; In InitRegisters, changed the default for no CRT, TV, nor LCD attached
;; to CRT only.
;;
;; 6     7/19/99 1:44p Kaymann
;; In InitRegisters, added code to verify that EEPROM byte 0 has valid
;; TV data.  If not valid, EEPROM byte 0 is written with valid TV data.
;;
;; Created the routine I2CWriteAuxEEPROM, for writing data to the EEPROM.
;;
;; 5     7/16/99 3:19p Kaymann
;; Extern defined the I2C routines to fix problem with not being able to
;; compile a Napalm TV BIOS.
;;
;; In InitRegisters, removed the code which set Scratch Register 2 to the
;; TV mode.
;;
;; Modified routines which checked if composite TV is active to use
;; the equate FLD_COMPOSITE instead of a hard coded value.
;;
;; 4     6/16/99 1:33p Kaymann
;; Created the routine Patch32KROM to patch the ROM size when compiling
;; a 32K ROM BIOS.
;;
;; 3     5/28/99 12:12p Kaymann
;; In OEMInitRegisters, added code to read the NVRAM to determine if we
;; want to autodetect the TV or force the TV setting.
;;
;; 2     5/24/99 5:46p Kaymann
;; In OEMNoMonitor, added code to check if a panel is connected.
;;
;; 1     5/11/99 3:00p Kaymann
;; Initial Version
;;
;; Moved all VGA POST routines into this files.  These POST routines are:
;; OEMInitBIOS
;; OEMInitWakeUp
;; OEMNoMonitor
;; OEMSignOn
;; InitIOBase
;; InitRegisters


        include BIOSEQU.INC
        include BIOSVARS.INC
        include OEM.INC
;       include VESA.INC

;
        %out    !       Assembling: OEMPOST.ASM - 3Dfx Interactive
;
.MODEL TINY
.CODE
.386
;

        extrn   byOEMSignOnColor:byte
        extrn   szOEMCopyright:byte
        extrn   LENGTH_MEMORYSIZE:abs
        extrn   LENGTH_SDRAM_MEMORY:abs
        extrn   szSDRAM_Memory:byte
        extrn   LENGTH_SGRAM_MEMORY:abs
        extrn   szSGRAM_Memory:byte
        extrn   LENGTH_DDR_MEMORY:abs
        extrn   szDDR_Memory:byte
        extrn   LENGTH_SDR_MEMORY:abs
        extrn   szSDR_Memory:byte
        extrn   szMemorySize:byte
        extrn   tblMemSizeStrs:byte


        extrn   regPCIInit0:dword
        extrn   regDRAMInit0:dword
        extrn   regDRAMInit1:dword
        extrn   regTMUGBEINIT:DWORD
        extrn   regMiscInit0:dword
        extrn   regMiscInit1:dword
        extrn   regPLLCtrl1:dword
        extrn   regSGRAMMode:dword
        extrn   regAGPInit0:dword

        extrn   OEMGetMemSize:near
        extrn   OEMEnableExtensions:near
        extrn   Find3DFXCard:near

        extrn   CheckIfSGRAM:near

IF (DDR_BIOS OR SDR_BIOS)
        extrn   CheckIfSDR:near
        extrn   CheckIfDDR:near
ENDIF

        extrn   GetIOBase:near
        extrn   GetCRTCAddr:near
        extrn   GetIndexRegister:near

IF TVOUT_BIOS
        extrn   I2CInit:near
        extrn   I2CReadAuxEEPROM:near
        extrn   I2CWriteRegister:near
        extrn   I2CStart:near
        extrn   I2CStop:near
        extrn   I2CSendByte:near
        extrn   I2CReadBus1Byte:near

  extrn regTVMode:byte
ENDIF

IF      DVI_BIOS
        extrn DFPReadByte:near
;;      extrn I2CWriteRegister_Panel:near

        extrn   DDCEnableDFP:near
ENDIF

;**********************************************************************
;
;       OEMInitBIOS - Initialize and determine if the BIOS should be "setup"
;
;       Entry:  DS = Seg0
;       Exit:   Carry flag set as follows:
;                       CF - Skip BIOS initialization
;                       NC - Continue
;
        public  OEMInitBIOS
OEMInitBIOS     proc
        assume  ds:Seg0, es:nothing
        pushad

        call    Find3DFXCard
        jc              OEMInitBIOS_error

        push    bx

IF      ((NumberOfChips eq 4) or (NumberOfChips eq 2))
;---------------------------------------------------------------
;Disable syncs on slave chips
        inc     bl

        mov     ax,0B10Ah                       ; Read config DWORD
        mov     di,080h                         ;
        int     1Ah

        mov     ax,0B10Dh                       ; Write config DWORD
        mov     di,080h                         ;
        or              ecx,003000000h
        int     1Ah

;---------------------------------------------------------------
ENDIF

IF      (NumberOfChips eq 4)
;Disable syncs on slave chips
        inc     bl

        mov     ax,0B10Ah                       ; Read config DWORD
        mov     di,080h                         ;
        int     1Ah

        mov     ax,0B10Dh                       ; Write config DWORD
        mov     di,080h                         ;
        or              ecx,003000000h
        int     1Ah

;---------------------------------------------------------------
        inc     bl

        mov     ax,0B10Ah                       ; Read config DWORD
        mov     di,080h                         ;
        int     1Ah

        mov     ax,0B10Dh                       ; Write config DWORD
        mov     di,080h                         ;
        or              ecx,003000000h
        int     1Ah

;---------------------------------------------------------------
ENDIF

        pop     bx

;
; Get the I/O Base address
;
        mov     ax,0B10Ah               ; Read config DWORD
        mov     di,018h                 ; I/O Base Address
        int     1Ah
        test    ah,ah                   ; Function passed?
        jnz     short OEMInitBIOS_error ;  N: Exit with error
        and     cx,0FFFEh               ; Mask off low order bit (I/O flag)
        mov     dx,cx                   ; Assume I/O address returned (DX = 0, if not)
;
; Set PCIINIT0
;
;       AGP boards need an extra read and write wait state.
;       This may change for future HW.
;
        add     dx,REG_STRAPINFO
        in      eax,dx
        xor     edi,edi
        test    al,008h                 ; Is this an AGP board ?
        jz      short OEMInitBIOS_10    ;  N: No extra wait states
        or      di,00300h               ;  Y: Use extra R/W wait states
OEMInitBIOS_10:
        mov     dx,cx
        add     dx,REG_PCIINIT0
        mov     eax,cs:[regPCIInit0]
        or      eax,edi
        out     dx,eax

;
; Set VGAINIT0 for AGP -- enable motherboard style VGA
;
        mov     dx,cx
        add     dx,REG_VGAINIT0
        mov     eax,0140h               ; Enable extensions / MB VGA
        out     dx,eax

;IFE     XLCD_BIOS
;
; Avenger specific (but compatible):  VIDINFORMAT initializes to 0x8000,
; not what we want!     SMB
;

;Moved this code to OEMNoMonitor
        mov     dx,cx
        add     dx,REG_VIDINFORMAT
        sub     eax,eax
        out     dx,eax
;ENDIF

;
; Get MISCINIT1. If bit 31 is a "1", then it is not the main device
; and the BIOS should not be initialized.
;
        mov     dx,cx
        add     dx,REG_MISCINIT1
        in      eax,dx
        test    eax,10000000h           ; Is this a multimedia device?
        jnz     short OEMInitBIOS_error ;  Y: Don't load the BIOS
        clc                             ;  N: It's the video device, load it
OEMInitBIOS_exit:
        popad
        ret
;
OEMInitBIOS_error:
;
; We are a multimedia device.  Disable VGA legacy decode in VGAINIT0.
;
        mov     dx,cx
        add     dx,REG_VGAINIT0
        mov     eax,0340h               ; Enable extensions / MB VGA
        out     dx,eax
        stc
        jmp     short OEMInitBIOS_exit
OEMInitBIOS     endp

;**********************************************************************
;
;       OEMInitWakeUp - Called at the beginning of the boot process
;
;       Entry:  DS = Seg0
;       Exit:   None
;
        public  OEMInitWakeUp
OEMInitWakeUp   proc
        assume  ds:Seg0, es:nothing
        pusha
;
        mov     dx,SUBSYS_ENABLE
        mov     al,001h
        out     dx,al                   ; Wake up chip

;;      mov     dx,high ADVFUNC_CNTL
;;      sub     ax,ax
;;      out     dx,ax                   ; Necessary for 8514/A compatibility
;
; Make sure I/O access and memory access is available (assuming color
; is better since co-res CGA's are so rare).
;
        mov     dx,MISC_OUTPUT
        mov     al,067h                 ; Enable ram, I/O = color
        out     dx,al
        mov     dl,low GDC_INDEX        ; Set addressing to A0000 for 64K so
        mov     ax,0506h                ; as not to conflict with [possible]
        out     dx,ax                   ; memory at B0000h or B8000h
;
        call    InitIOBase
        call    OEMEnableExtensions
        call    InitRegisters
;
        popa
        ret
OEMInitWakeUp   endp

;**********************************************************************
;
;       InitIOBase - Return the I/O base for the 3Dfx extended I/O
;
;       Entry:  None
;       Exit:   DX = I/O base (0 = Error)
;
;       All other registers are preserved.
;
        public  InitIOBase
InitIOBase      proc
        assume ds:nothing, es:nothing
        push    ax
        push    bx
        push    ecx
        push    di
        push    si
;
        call    Find3DFXCard
        jc              InitIOBase_error

        mov     ax,0B10Ah               ; Read config DWORD
        mov     di,018h                 ; I/O Base Address
        int     1Ah
        test    ah,ah                   ; Function passed?
        jnz     short InitIOBase_error  ;  N: Exit with error
        and     cx,0FFFEh               ; Mask off low order bit (I/O flag)
        mov     dx,cx                   ; Assume I/O address returned (DX = 0, if not)
;
; Save the HIBYTE value of IOBase (LOBYTE is 0) into the first scratch register
;
        push    dx
        mov     bl,dh                   ; BL = IOBase
        add     dx,REG_VGAINIT0
        in      eax,dx
        and     al,07Fh
        or      al,040h
        out     dx,eax                  ; Enable VGA extensions
;
        mov     dx,CRTC_CINDEX          ; Assume color CRTC (write to 3C2h in
        mov     al,SCRATCH_REG0         ;  "OEMInitWakeUp" guarentees this)
        mov     ah,bl
        out     dx,ax
        mov     ax,SCRATCH_REG1         ; While here, initialize the other
        out     dx,ax                   ;  flags to 0
        mov     ax,SCRATCH_REG2
        out     dx,ax
        pop     dx
;
InitIOBase_exit:
        pop     si
        pop     di
        pop     ecx
        pop     bx
        pop     ax
        ret
;
InitIOBase_error:
        sub     dx,dx
        jmp     short InitIOBase_exit
InitIOBase      endp

;**********************************************************************
;
;       InitRegisters - Initialize the 3Dfx register set
;
;       Entry:  DS = Seg0
;       Exit:   None
;
        public  InitRegisters
InitRegisters   proc
        assume  ds:Seg0, es:nothing
        push    eax
        push    dx
        push    si

IF      TVOUT_BIOS
;Moved this code to OEMNoMonitor
;Save original VidInformat setting
        call    GetIOBase
        add     dx,REG_VIDINFORMAT
        push    eax
        sub     eax,eax
        out     dx,eax

        call    I2CInit         ;Sets DX to IOBase + 78

;++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
;Checks if the NVRAM byte 0 has valid data.  If not, force to NTSC.
        mov     ah,00                           ;AH is the offset to read
        call    I2CReadAuxEEPROM

        mov     bl,al
        and     bl,CFG_TV_MASK                          ;Mask off TV data

        cmp     bl,CFG_PAL_Nc                           ; PAL-Nc
        je              NVRAMValid
        cmp     bl,CFG_PAL_N                            ; PAL-N
        je              NVRAMValid
        cmp     bl,CFG_PAL_M                            ; PAL-M
        je              NVRAMValid
        cmp     bl,CFG_PAL_BGDHI                        ; PAL-BDGHI
        je              NVRAMValid
        cmp     bl,CFG_NTSC                                     ; NTSC
        je              NVRAMValid

InvalidNVRAM:
;We must an invalid configuration.  Forse to NTSC.

        and     al,not CFG_TV_MASK              ;Mask off old TV data
        or              al,cs:regTVMode                         ;OR in NTSC Tv data


        mov     ah,00                                                   ;AH is the offset to read
        call    I2CWriteAuxEEPROM

;Now I need to recalculate the checksum since I've modified the NVRAM data.
;Checksum is calculated by added up all the bytes in the NVRAM, except for
;the last byte, subtracting the sum of the bytes from 100h, and finally
;storing the resulting byte at the last byte.

        call    CalcNVRAMChecksum

NVRAMValid:
;++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

;A value in byte 1 of the NVRAM will hold the "forced"
;boot output type and will be:
; (00000000b=Auto) (00000001b=SVideo) (00000010b=Composite)
; (00000011b=Both - for 5Flags)
        mov     ah,01                           ;AH is the offset to read
        call    I2CReadAuxEEPROM

        xor     bl,bl
        and     al,03   ;Mask whatever else off
        cmp     al,02
        je      SetForComposite
        cmp     al,01
        je      SetForSVideo

DoAutoDetect:

; Test to see if a TV is attached.
; If not, then set for VGA. If yes, Read EEPROM.
; BT869 has a detection for the DACs
;       METHOD:
;               Write Register C4 with 01xxxxxx {ESTATUS 1:0}
;               Write Register BA with x1xxxxxx {CHECK_STAT}
;               Write 0x89 to setup the readback
;               Read the byte, bit 7 DAC-A (not used)
;                              bit 6 DAC-B
;                              bit 5 DAC-C
;                       if any are 1 a TV is detected
;
        mov     ax,040C4h                       ; ESTATUS D7:D6 = 01
        call    I2CWriteRegister
        mov     ax,061BAh                       ; CHECK_STAT D6 = 1
        call    I2CWriteRegister

        call    I2CStart          ; Send a start on the I2C
        mov     al,089h                         ; Let BT869 know it must send
        call    I2CSendByte                     ; a byte back
;;      jc              NoTVFound
        call    I2CReadBus1Byte         ; Read it off SDA1
        call    I2CStop

;;      mov     bl,020h                         ; Set for success
;;      and     al,060h                         ; Mask for only DAC-B and DAC-C
;;      jnz     TVFound                         ; If zero, no TV attached, set for VGA
;;NoTVFound:
;;      xor     bl,bl
;;TVFound:

        xor     bl,bl
        and     al,060h                         ; Mask for only DAC-B and DAC-C

;;      jz              SetForComposite
        jz              NoTVFound                       ; If zero, no TV attached, set for VGA


        cmp     al,020h
        je              SetForComposite
        jmp     SetForSVideo

;;      cmp     al,060h
;;      je              SetForSVideo            ; Equal: Svideo; !Equal: Composite
;;      cmp     al,040h
;;      je              SetForSVideo            ; Equal: Svideo; !Equal: Composite

SetForComposite:
        or              bl,FLD_COMPOSITE        ; Bit 6 of Scratch_Reg2 (High=Composite)
        jmp     NoTVFound
SetForSVideo:
;       or      bl,020h
NoTVFound:

        call    GetCRTCAddr
        mov     al,SCRATCH_REG2
        call    GetIndexRegister
        or              ah,bl
        out     dx,ax

;Restore original VidInformat setting
        call    GetIOBase
        add     dx,REG_VIDINFORMAT
        pop     eax
        out     dx,eax

ENDIF

;
        call    GetIOBase
        mov     si,dx                           ; SI = I/O Base

;
; Set DRAMINIT1
;
        add     dx,REG_DRAMINIT1
        in      eax,dx
IF              (Napalm2_BIOS)
        and     eax,0C3000000h
ELSE
        and     eax,0C2000000h
ENDIF
        or      eax,cs:[regDRAMInit1]

;Slam dunk card to always act like an SDRAM card
        or      eax,FLD_SDRAMBOARD

        out     dx,eax

;
;       Set VidProcCfg
;
        mov     dx,si
        add     dx,REG_VIDPROCCFG
        in              eax,dx
;IF     Build_V5P896
;%out Clearing VidProcCfg[29:28]=00
;  and   eax,not 030000000h
;ELSE
%out Setting VidProcCfg[29:28]=11
        or              eax,030000000h
;ENDIF
        out     dx,eax

;
; Set tmuGbeInit
;
        mov     dx,si
        add     dx,REG_TMUGBEINIT
IF              (Napalm2_BIOS)
        and     eax,00E000000h                                  ;Preserve bits [27:25]
        or      eax,cs:[regTMUGBEINIT]          ;OR in new pattern
ELSE
        mov     eax,cs:[regTMUGBEINIT]
ENDIF
;       mov     eax,DEFAULT_TMUGBEINIT
        out     dx,eax

;
; Set DRAMINIT0
;
        lea     dx,[si + REG_DRAMINIT0]
        in      eax,dx


;       call    CheckIfSGRAM
;       jz              DRAMInit0SGRAM
;
;       and     eax,0F8000000h          ; Bit 26 should be 0 for SDRAM
;       jmp     short   EndDRAMInit0SGRAM
;
;DRAMInit0SGRAM:
IF              (Napalm2_BIOS)
        and     eax,07C000000h          ;Preserve bits [30:26]
ELSE
        and     eax,0FC000000h          ;Preserve bits [31:26]
ENDIF

EndDRAMInit0SGRAM:
        or      eax,cs:[regDRAMInit0]
        out     dx,eax
;
; Set MISCINIT0
;
        lea     dx,[si + REG_MISCINIT0]
        mov     eax,cs:[regMiscInit0]
        out     dx,eax
;
; Set Mode register
;
IF              (Napalm2_BIOS)

;----------------------------------------------------------------------
        lea     dx,[si + REG_DRAMSMODE]
        mov     eax,cs:[regSGRAMMode]
        out     dx,eax


        lea     dx,[si + REG_DRAMMODE]
        mov     eax,00000010Dh
        out     dx,eax

;----------------------------------------------------------------------

if      (DDR_BIOS)
        call    CheckIfDDR
        jne     SkipMaskSGRAM

;We must be DDR memory. Reset DLL from mode register

        lea     dx,[si + REG_DRAMSMODE]
        mov     eax,0131h
        out     dx,eax

        lea     dx,[si + REG_DRAMMODE]
        mov     eax,00000010Dh
        out     dx,eax

        lea     dx,[si + REG_DRAMSMODE]
        mov     eax,0031h
        out     dx,eax

        lea     dx,[si + REG_DRAMMODE]
        mov     eax,00000010Dh
        out     dx,eax
endif

;----------------------------------------------------------------------
ELSE

        lea     dx,[si + REG_DRAMSMODE]
        mov     eax,cs:[regSGRAMMode]
        out     dx,eax
        lea     dx,[si + REG_DRAMMODE]
        mov     eax,00000010Dh
        out     dx,eax

        call    CheckIfSGRAM
        jnz     SkipMaskSGRAM

;
; Set Mask register
;
        lea     dx,[si + REG_DRAMSMODE]
        mov     eax,0FFFFFFFFh
        out     dx,eax
        lea     dx,[si + REG_DRAMMODE]
        mov     eax,00000010Eh
        out     dx,eax

;----------------------------------------------------------------------

ENDIF

SkipMaskSGRAM:

;
; Set MISCINIT1
;
        lea     dx,[si + REG_MISCINIT1]
        in      eax,dx
        and     eax,01FF40000h
        or      eax,cs:[regMiscInit1]

        call    CheckIfSGRAM
        jz              SetMiscInit1

        or              eax,000008000h                                  ;Disable block writes on SDRAMs

SetMiscInit1:
        out     dx,eax
;
; Set AGPINIT0
;
        lea     dx,[si + REG_AGPINIT0]
        mov     eax,cs:[regAGPInit0]
        out     dx,eax
;
; Set PLLCTRL1
;
        lea     dx,[si + REG_PLLCTRL1]
        mov     eax,cs:[regPLLCtrl1]
        out     dx,eax

;----------------------------------------------------------------------
IF              (Napalm2_BIOS)

        call    CheckIfDDR
        jne     SkipDLLReset

;We must be DDR memory. Reset DLL from mode register

        lea     dx,[si + REG_DRAMSMODE]
        mov     eax,0131h
        out     dx,eax

        lea     dx,[si + REG_DRAMMODE]
        mov     eax,00000010Dh
        out     dx,eax

        lea     dx,[si + REG_DRAMSMODE]
        mov     eax,0031h
        out     dx,eax

        lea     dx,[si + REG_DRAMMODE]
        mov     eax,00000010Dh
        out     dx,eax

SkipDLLReset:

ENDIF
;----------------------------------------------------------------------

;
; Set REG_LFBMEMORYCONFIG
;
        lea     dx,[si + REG_LFBMEMORYCONFIG]
        in      eax,dx
        or      ax,01FFFh                       ; Set tile start page at end
        out     dx,eax
;
;Assume a CRT is attached.  Set CR1E[7]=1.
        call    GetCRTCAddr
        mov     al,SCRATCH_REG2
        call    GetIndexRegister
        or              ah,FLD_CRT_ACTIVE
        out     dx,ax

; !!!rainbow
;        call    GetCRTCAddr
;        mov     al,SCRATCH_REG3
;        call    GetIndexRegister
;        or              ah,FLD_DVI
;        out     dx,ax

        pop     si
        pop     dx
        pop     eax
        ret
InitRegisters   endp

;**********************************************************************

IF (VARIATION_001 eq 0)
;
;       OEMNoMonitor - Handle the situation when no monitor is attached
;
;       Entry:  DS = Seg0
;       Exit:   None
;
;       Note:   No monitor was found attached to the VGA, so default
;               to TV out.
;
        public  OEMNoMonitor
OEMNoMonitor    proc
        assume  ds:Seg0, es:nothing
;Clear the CRT field, CR1E[7] since no CRT was detected during POST.
        push    dx
        push    ax
        call    GetCRTCAddr
        mov     al,SCRATCH_REG2
        call    GetIndexRegister
        and     ah,not FLD_CRT_ACTIVE
;        or     ah,FLD_CRT_ACTIVE
        out     dx,ax

;        call    GetCRTCAddr
;        mov     al,SCRATCH_REG3
;        call    GetIndexRegister
;        or     ah,FLD_DVI
;        out     dx,ax

; !!!rainbow

        pop     ax
        pop     dx


IF      DVI_BIOS
        %out    !                               DVI BIOS

;Moved this code to OEMNoMonitor
        push    dx
        push    ax
        call    GetIOBase
        add     dx,REG_VIDINFORMAT
        mov     ax,8000h
        out     dx,eax
        pop     ax
        pop     dx

  call  CheckForPanel
  jc            OEMNoMonitorEnd
ENDIF

  IF TVOUT_BIOS
        push    ax
        push    dx
;
; Avenger specific (but compatible):  VIDINFORMAT initializes to 0x8000,
; not what we want!     SMB
;

;Moved this code to OEMNoMonitor
        call    GetIOBase
        add     dx,REG_VIDINFORMAT
        sub     eax,eax
        out     dx,eax

        call    I2CInit         ;Sets DX to IOBase + 78

; Test to see if a TV is attached.
; If not, then set for VGA. If yes, Read EEPROM.
; BT869 has a detection for the DACs
;       METHOD:
;               Write Register C4 with 01xxxxxx {ESTATUS 1:0}
;               Write Register BA with x1xxxxxx {CHECK_STAT}
;               Write 0x89 to setup the readback
;               Read the byte, bit 7 DAC-A (not used)
;                              bit 6 DAC-B
;                              bit 5 DAC-C
;                       if any are 1 a TV is detected
;
        push    bx
        mov     ax,040C4h                       ; ESTATUS D7:D6 = 01
        call    I2CWriteRegister
        mov     ax,061BAh                       ; CHECK_STAT D6 = 1
        call    I2CWriteRegister

        call    I2CStart          ; Send a start on the I2C
        mov     al,089h                         ; Let BT869 know it must send
        call    I2CSendByte                     ; a byte back
        jc              NoTVFound
        call    I2CReadBus1Byte         ; Read it off SDA1
        call    I2CStop

        mov     bl,FLD_TV_ACTIVE        ; Set for success
        and     al,060h                         ; Mask for only DAC-B and DAC-C
        jnz     TVFound                         ; If zero, no TV attached, set for VGA
NoTVFound:
        xor     bl,bl
TVFound:
        call    GetCRTCAddr
        mov     al,SCRATCH_REG2
        call    GetIndexRegister
        or              ah,bl
        out     dx,ax
        pop     bx

        jmp     short ReferenceOEMNoMonitorEnd

ReferenceOEMNoMonitor:

        call    GetCRTCAddr
        mov     al,SCRATCH_REG2
        call    GetIndexRegister

;  or    ah,cs:regTVMode
  or    ah,020h           ;Turn on the TV
        out     dx,ax

ReferenceOEMNoMonitorEnd:

        pop     dx
        pop     ax
  ENDIF
OEMNoMonitorEnd:
        ret
OEMNoMonitor    endp
;
ENDIF

;**********************************************************************
;
;       OEMSignOn - Display an OEM specific sign on message
;
;       Entry:  DS = Seg0
;               ES = ROM segment
;       Exit:   None
;
        public  OEMSignOn
OEMSignOn       proc
        assume  ds:Seg0, es:_TEXT
        pusha

;----------------------------------------------------------------------

        sub     bh,bh
        mov     bl,es:[byOEMSignOnColor]        ; Use signon color for all messages
;
        mov     ax,01301h
        mov     dx,[wCursorPosition]
        mov     bp,offset szOEMCopyright + 2    ; Get pointer to string
        mov     cx,es:[bp-2]                    ; Get size of string
;        int     10h
;----------------------------------------------------------------------
;

        mov     dx,[wCursorPosition]
        mov     ax,01301h

IF (DDR_BIOS OR SDR_BIOS)

        mov     cx,LENGTH_DDR_MEMORY
        mov     bp,offset szDDR_Memory

        call    CheckIfDDR
        je              PrintMemoryTypeMessage

        mov     cx,LENGTH_SDR_MEMORY
        mov     bp,offset szSDR_Memory

ELSE
        mov     cx,LENGTH_SGRAM_MEMORY
        mov     bp,offset szSGRAM_Memory

        call    CheckIfSGRAM
        jz              PrintMemoryTypeMessage

        mov     cx,LENGTH_SDRAM_MEMORY
        mov     bp,offset szSDRAM_Memory
ENDIF

PrintMemoryTypeMessage:
;        int     10h
;----------------------------------------------------------------------

;
        mov     dx,[wCursorPosition]
        mov     ax,01301h
        mov     cx,LENGTH_MEMORYSIZE
        mov     bp,offset szMemorySize
;        int     10h
;----------------------------------------------------------------------
;
        call    OEMGetMemSize                   ; AX = # of 256K blocks

IF      (NumberOfChips eq 4)
%out COMPILING 4 WAY SLI
        shl     ax,2
ELSEIF (NumberOfChips eq 2)
%out COMPILING 2 WAY SLI
        shl     ax,1
ENDIF

        mov     bp,offset tblMemSizeStrs


OEMSignOn_10:
        cmp     word ptr es:[bp],0
        je      short OEMSignOn_exit
        cmp     es:[bp],ax
        je      short OEMSignOn_20
        add     bp,4
        jmp     short OEMSignOn_10
OEMSignOn_20:
        inc     bp
        inc     bp
        mov     bp,es:[bp]
        mov     ah,03h
;        int     10h                     ; DX returns with current cursor position

;----------------------------------------------------------------------

        mov     ax,01301h
        mov     cl,es:[bp]              ; Get string length
        sub     ch,ch
        inc     bp                      ; Point at string
;        int     10h

;----------------------------------------------------------------------

;
OEMSignOn_exit:
        mov     ax,0E0Dh        ; Carriage return
        int     10h
        mov     ax,0E0Ah        ; Line feed
        int     10h
        mov     ax,0E0Ah        ; Line feed
        int     10h
;
        popa
        ret
OEMSignOn       endp

;**********************************************************************

;This routine patches the ROM size at C000:2 and in the PCI configuration
;space
;       Entry   : NONE
;       Exit    : NONE

        public  Patch32KROM
Patch32KROM     proc    near

;Only execute this when building a ROM binary or your RAM BIOS is going
;  to hang in a horrible manner. :)


%out Patching 32K ROM

;Check if we're installed in a Compaq 5420 series machine.  If so, DO NOT
;execute patch.  For some stupid reason, Compaq machines don't like my
;discardable POST.
        cmp     byte ptr cs:[02],80h                                                            ;Are we a Compaq 5240??
        je              EndROMSizePatch                                                                 ;Jump if we are.
        mov     byte ptr cs:[02],40h                                                            ;Reset ROM size to 32K

;Figure out where the ROM size in the PCI block is
        mov     di,word ptr cs:[18h]                                                            ;C000:18h pointer to PCI block
        add     di,10h                                                                                          ;16th byte is the ROM size
        movzx   eax,word ptr cs:[di]                                                            ;Load ROM size
        mov     ebx,512                                                                                         ;Figure out the ROM size.
        mul     ebx
        xchg    eax,ebx
        dec     ebx
        mov     eax,dword ptr cs:[ebx-07h]                                              ;Get a copy of the SSID data

        mov     dword ptr cs:[7FF8h],eax                                                ;Mirror it into C000:7FF8


        mov     word ptr cs:[di],40h                                                            ;Set PCI BLOCK ROM size to 32K.

IF              (Napalm2_BIOS)
;--------------------------------------------------------------------------------------------------------------
;Now copy the Strapping option bytes into the 32K range

        mov     eax,dword ptr cs:[ebx-0Fh]                                              ;
        mov     dword ptr cs:[7FF0h],eax                                                ;Mirror it into C000:7FF0

        mov     eax,dword ptr cs:[ebx-0Bh]                                              ;
        mov     dword ptr cs:[7FF4h],eax                                                ;Mirror it into C000:7FF0

;--------------------------------------------------------------------------------------------------------------
        xor     bx,bx                                           ;Clear checksum accumulator

        push    si
        push    ds

        push    cs
        pop     ds


        mov     cx,7FFFh                                        ;Read 127 bytes
ReadNextByte:
        mov     si,cx                                           ;Set ROM read address
        dec     si

        lodsb

        add     bl,al                                           ;Added byte into BL
        loop    ReadNextByte

        mov     ax,100h
        sub     ax,bx                                           ;Calculate checksum.

;AL = Checksum to write.

        mov     di,7FFFh                                        ;Write checksum to ROM address 7FFFh
        mov     byte ptr cs:[di],al

        pop     ds
        pop     si
;--------------------------------------------------------------------------------------------------------------
EndROMSizePatch:

ELSE

EndROMSizePatch:
;--------------------------------------------------------------------------------------------------------------
        xor     bx,bx                                           ;Clear checksum accumulator

        push    si
        push    ds

        push    cs
        pop     ds


        mov     cx,7FFFh                                        ;Read 127 bytes
        xor     si,si                                           ;Set ROM address to 0000h

ReadNextByte:

        lodsb

        add     bl,al                                           ;Added byte into BL
        loop    ReadNextByte

        mov     ax,100h
        sub     ax,bx                                           ;Calculate checksum.

;AL = Checksum to write.

        mov     di,7FFFh                                        ;Write checksum to ROM address 7FFFh
        mov     byte ptr cs:[di],al

        pop     ds
        pop     si
;--------------------------------------------------------------------------------------------------------------
ENDIF

        ret


public szLogo
szLogo DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,68,68,196,68,68,0,0,0,0,0,0,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,68,76,204,204,204,204,204,204,196,64,0,0,0,0,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,68,68,64,0,0,0,4,76,204,204,196,0,0,0,0,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,0,0,4,68,0,0,0,0,0,0,0,0,76,204,204,196,0,0,0,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,0,4,64,0,0,0,0,0,0,0,0,0,0,76,204,204,64,0,0,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,4,64,0,0,0,0,0,0,0,0,0,0,0,4,204,204,196,0,0,0,0
DB 0,0,0,0,0,0,0,0,0,0,4,64,0,0,0,0,0,0,0,0,0,0,0,0,0,76,204,204,0,0,0,0
DB 0,0,0,0,0,0,0,0,0,4,64,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,204,204,64,0,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,204,204,192,0,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,76,204,196,0,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,12,204,204,0,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,12,204,204,0,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,8,128,0,0,0,0,0,4,204,204,64,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,0,135,119,119,0,0,0,119,255,255,112,0,0,0,0,4,204,204,64,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,0,143,255,255,128,0,7,255,255,255,112,0,0,0,0,4,204,204,64,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,0,143,255,255,0,0,127,255,255,255,112,0,0,0,0,4,204,204,64,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,0,143,255,255,0,0,127,255,255,255,112,0,0,0,0,0,204,204,64,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,0,143,255,255,0,0,127,255,255,120,128,0,0,0,0,0,204,204,64,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,0,143,255,255,128,0,127,255,247,0,0,0,0,0,0,4,204,204,64,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,0,143,255,255,0,0,127,255,247,0,0,0,0,0,0,4,204,204,64,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,0,143,255,255,0,0,127,255,247,0,0,0,0,0,0,4,204,204,64,0,0
DB 0,0,0,0,0,0,0,0,0,0,0,0,143,255,255,0,0,127,255,247,0,0,0,0,0,0,4,204,204,0,0,0
DB 0,0,8,135,128,0,0,0,0,0,135,128,143,255,255,128,0,127,255,247,0,0,0,0,0,0,4,204,204,0,0,0
DB 0,0,127,255,255,112,0,0,0,127,255,247,127,255,255,7,247,255,255,255,127,112,127,127,120,0,12,204,196,0,0,0
DB 0,7,255,255,255,247,0,0,8,255,255,255,255,255,255,7,255,255,255,255,255,112,127,255,247,0,76,204,196,0,0,0
DB 0,127,255,255,255,255,112,0,15,255,255,255,255,255,255,7,255,255,255,255,255,112,127,255,255,0,76,204,192,0,0,0
DB 8,255,255,119,255,255,248,0,127,255,255,120,127,255,255,135,255,255,255,255,255,112,15,255,255,112,204,204,192,0,0,0
DB 7,255,247,0,127,255,247,0,127,255,247,0,143,255,255,0,136,255,255,247,136,128,7,255,255,112,204,204,64,0,0,0
DB 7,119,248,0,127,255,247,0,127,255,247,0,143,255,255,0,0,127,255,247,0,0,8,255,255,244,204,204,64,0,0,0
DB 0,0,0,0,143,255,247,8,255,255,248,0,143,255,255,0,0,127,255,247,0,0,0,127,255,252,204,204,0,0,0,0
DB 0,0,0,0,127,255,247,8,255,255,248,0,143,255,255,128,0,127,255,247,0,0,0,127,255,124,204,196,0,0,0,0
DB 0,0,0,0,127,255,248,7,255,255,248,0,143,255,255,0,0,127,255,247,0,0,0,143,255,204,204,192,0,0,0,0
DB 0,0,8,119,255,255,112,7,255,255,248,0,143,255,255,0,0,127,255,247,0,0,0,7,247,204,204,64,0,0,0,0
DB 0,0,143,255,255,247,0,7,255,255,248,0,143,255,255,0,0,127,255,247,0,0,0,7,252,204,204,0,0,0,0,0
DB 0,0,143,255,255,247,0,7,255,255,248,0,143,255,255,128,0,127,255,247,0,0,0,0,124,204,196,0,0,0,0,0
DB 0,0,143,255,255,255,112,7,255,255,248,0,143,255,255,0,0,127,255,247,0,0,0,0,76,204,199,0,0,0,0,0
DB 0,0,7,119,255,255,247,7,255,255,248,0,143,255,255,0,0,127,255,247,0,0,0,0,204,204,207,128,0,0,0,0
DB 0,0,0,0,127,255,247,7,255,255,248,0,143,255,255,0,0,127,255,247,0,0,0,4,204,204,127,112,0,0,0,0
DB 0,0,0,0,127,255,255,7,255,255,248,0,143,255,255,128,0,127,255,247,0,0,0,76,204,204,255,240,0,0,0,0
DB 0,0,0,0,143,255,255,8,255,255,248,0,143,255,255,0,0,127,255,247,0,0,0,204,204,199,255,248,0,0,0,0
DB 7,119,120,0,143,255,255,8,255,255,247,0,143,255,255,0,0,127,255,247,0,0,4,204,204,207,255,247,0,0,0,0
DB 15,255,247,0,127,255,247,0,127,255,247,0,143,255,255,0,0,127,255,247,0,0,12,204,196,127,255,255,0,0,0,0
DB 7,255,247,0,127,255,247,0,127,255,255,136,127,255,255,128,0,127,255,247,0,0,76,204,196,7,255,255,112,0,0,0
DB 8,255,255,255,255,255,248,0,127,255,255,255,255,255,255,0,0,127,255,247,0,4,204,204,64,7,255,255,112,0,0,0
DB 0,127,255,255,255,255,112,0,7,255,255,255,127,255,255,0,0,127,255,247,0,12,204,204,0,8,255,255,248,8,120,0
DB 0,7,255,255,255,247,0,0,8,255,255,247,143,255,255,128,0,255,255,247,0,204,204,196,0,0,127,255,247,7,119,0
DB 0,0,119,127,119,128,0,0,0,135,119,112,7,119,119,0,0,119,119,120,0,68,68,64,0,0,135,119,119,0,128,0

PutData         proc    near
; write CMOS/EEPROM ;
; input:  al = address, ah = output data
                cli
                out     70h,al
                in      al,21h   ; IO delay
                mov     al,ah
                out     71h,al
                sti
                ret
PutData         endp

GetData         proc    near
; read CMOS
; input: al = address
; output: al = output data
                cli
                out     70h,al
                in      al,71h
                sti
                retn
GetData         endp

putvclock proc
         mov ax,1301h
         mov bx,7
         mov cx,szstr2-szstr1
         mov dx,9
         mov bp,offset szstr1
         int 10h
         mov cx,szstr3-szstr2
         inc dh
         mov bp,offset szstr2
         int 10h
         mov cx,text0-szstr3
         inc dh
         mov bp,offset szstr3
         int 10h
         mov cx,text1-text0
         inc dh
         mov bp,offset text0
         int 10h
         ret
putvclock endp

mclock proc
; si = смещение n
;выход: ax - clock
      ; разборка pll
      mov di,word ptr cs:[regPLLCtrl1]
      mov cx,di
      and cx,11b       ; cx - k
      mov bx,di
      and di,11111100b
      shr di,2         ; di - m
      mov bl,bh
      and bl,11111110b ; бит для dvi
      xor bh,bh        ; bx - n
      add bx,si        ; учет смещения
      ;вычисление частоты
      add di,2         ; m+2
      add bx,2         ; n+2
      shl bx,2         ; (n+2)*4
      mov ax,57        ; 14.31818*4
      mul bx
      shr ax,4         ; (n+2)*14.31818
      xchg ax,di
      mov dx,1
      shl dx,cl        ; dx - 2^k
      mul dx           ; (m+2)*2^k
      xchg ax,di
      div di           ; ((n+2)*14.31818)/((m+2)*2^k)
      inc ax           ; коррекция на точность
      ret
mclock endp

viewcursor proc
; cx - длина
; bl - цвет
      push bx
      xor dx,dx
      movzx ax,byte ptr [ypos]
      mov bx,80*2
      mul bx
      mov di,(7*80+53)*2
      add di,ax
      pop bx

      push es
      mov ax,0b800H
      mov es,ax
lz:   mov es:[di+1],bl
      add di,2
      loop lz
      pop es
      ret
viewcursor endp

; di - куда
; bp - откуда
view3 proc
        mov cx,12
        push es
        mov ax,0b800H
        mov es,ax
d3:     mov al,[bp]
        mov es:[di],al
        inc bp
        add di,2
        dec cx
        jnz d3
        pop es
        ret
view3 endp

tostring proc

; сформировать десятичное число в памяти
; input:  di = адрес, КУДА печатать
;         ax = data
;         cl = число позиций
; output: di = new pos.
;                movzx   cx,cl           ; CH признак обнаружения не_0
                xor ah,ah
                mov cx,3
                add     di,cx           ; выводить с конца
                push    di
                mov     bx,10

PrintNextDecChar:
; --------------------------------------
                xor     dx,dx
                div     bx
                or      ax,ax           ; есть значащие цифры?
                jnz     PrintALLtoMem   ; YES
; значащих цифр небыло - это не 0??
                inc     ch
                or      dx,dx
                jnz     PrintALLtoMem   ; там не 0
; это 0 - подавить его!
                mov     dl,' '-'0'
                dec     ch
PrintALLtoMem:  add     dl,'0'
                dec     di              ; вывод от конца к началу
                mov     byte ptr [di],dl
; --------------------------------------
                dec     cl
                jnz     PrintNextDecChar
                pop     di
; если было нулевое число - вывести 0
                or      ch,ch
                jnz     PrintZeroChar
                mov     byte ptr [di-1],'0'
PrintZeroChar:
                ret

tostring endp

hrefresh4  proc
                call hrefresh
                call hrefresh
                call hrefresh
hrefresh:       MOV     dx,3DAH
HALT1:          IN      AL,DX
                AND     AL,8
                JZ      HALT1
HALT2:          IN      AL,DX
                AND     AL,8
                JNZ     HALT2
                ret
hrefresh4 endp

create5 proc
        mov si,[cpos]
        sub si,3
        mov di,offset clock5-4
        mov cx,5
a1:
        push cx
        inc si
        push di
        call mclock
        pop di
        add di,4
        push di
        call tostring
        pop di
        pop cx
        dec cx
        jnz a1
        ret
create5 endp

viewt proc
        mov [ypos],1
        mov di,(8*80+50)*2
d6:     push di
        call create5m
        pop di
        push di
        mov bp,offset clock5+4
        call view3
        pop di
        add di,80*2
        inc [ypos]
        cmp byte ptr [ypos],6
        jbe d6
        ret
viewt   endp

; view dvi options
; dl - x position
DVItext db " auto  on "
viewdvi proc
        mov ax,1300h
        mov bx,17h
        mov cx,10
        mov dh,0eh
        mov bp,offset DVItext
        int 10h
        ret
viewdvi endp
chp db 0
create5m proc
        mov di,offset clock5
        mov si,offset tRRD
        movzx bx,byte ptr [ypos]
        mov al,[si+bx-1]
        sub al,2
        mov si,offset tRRDmx
        mov ah,cs:[si+bx-1]
        mov cs:[chp],ah
        mov cx,5
ff0:
        push cx
        push ax
        push di
        cmp al,cs:[chp]
        jbe f1
        mov eax,20202020h
        mov [di],eax
        jmp f2
f1:     call tostring
f2:     pop di
        add di,4
        pop ax
        inc al
        pop cx
        dec cx
        jnz ff0
        ret

create5m endp

ViewSetUpBios proc
        ; 80x25x4 bit - text mode
        mov ax,0003h
        int 10h

        mov ax,0100h
        mov cx,1000h
        int 10h

        xor bx,bx
        mov ax,10H*256+3
        int 10h

        push es
        mov ax,0b800H
        mov es,ax

        mov di,(3*80+8)*2
        mov word ptr es:[di],017c9h
        add di,2
        mov cx,61
        mov ax,017cdh
        rep stosw
        mov word ptr es:[di],017BBH
IF DVI_BIOS
        mov dx,14
ELSE
        mov dx,13
ENDIF
a3:
        add di,(80-62)*2
        mov word ptr es:[di],017BAh
        add di,2
        mov cx,61
        mov ax,01720h
        rep stosw
        mov word ptr es:[di],017BAH
        dec dx
        jnz a3

        add di,(80-62)*2
        mov word ptr es:[di],017c8h
        add di,2
        mov cx,61
        mov ax,017CDh
        rep stosw
        mov word ptr es:[di],017BCH

        mov di,(3*80+8)*2+80*4
        mov word ptr es:[di],017cch
        add di,2
        mov cx,61
        mov ax,017cdh
        rep stosw
        mov word ptr es:[di],017B9H
IF DVI_BIOS
        mov di,(16*80+8)*2
ELSE
        mov di,(15*80+8)*2
ENDIF
        mov word ptr es:[di],017c7h
        add di,2
        mov cx,61
        mov ax,017c4h
        rep stosw
        mov word ptr es:[di],017B6H
        pop es

        mov ax,1300h
        mov bx,1eh
        mov cx,text2-text1
        mov dx,0414h
        mov bp,offset text1
        int 10h
        mov cx,12
        mov dx,042dh
        mov bp,offset szstr1
        int 10h

        mov bx,17h
        mov cx,text3-text2
IF DVI_BIOS
        mov dx,110bh
ELSE
        mov dx,100bh
ENDIF
        mov bp,offset text2
        int 10h
        mov bx,1fh
        mov cx,text4-text3
        mov dx,0711h
        mov bp,offset text3
        int 10h
        mov cx,text5-text4
        inc dh
        mov bp,offset text4
        int 10h
        mov cx,text6-text5
        inc dh
        mov bp,offset text5
        int 10h
        mov cx,text7-text6
        inc dh
        mov bp,offset text6
        int 10h
        mov cx,text8-text7
        inc dh
        mov bp,offset text7
        int 10h
        mov cx,text9-text8
        inc dh
        mov bp,offset text8
        int 10h
        mov cx,text10-text9
        inc dh
        mov bp,offset text9
        int 10h
IF DVI_BIOS
        mov cx,clock5-text10
        inc dh
        mov bp,offset text10
        int 10h
;!!!!!!

ENDIF
        mov word ptr [cpos],0

        ; разборка draminit0
        mov al,3
        call GetData
        mov bh,al
        mov al,5
        call GetData
        mov bl,al
        mov ax,bx
        or bx,bx
        jnz ff1
        ;mov ax,word ptr cs:[regDRAMInit0]
ff1:    ;mov word ptr cs:[regDRAMInit0],ax  ;сыюъшЁєхь чряшё№ т draminit
        mov bx,ax
        and bl,011b
        mov [tRRD],bl
        mov bx,ax
        and bl,01100b
        shr bl,2
        mov [tRCD],bl
        mov bx,ax
        and bl,0110000b
        shr bl,4
        mov [tRP],bl
        mov bx,ax
        and bx,01111000000b
        shr bx,6
        mov [tRAS],bl
        mov bx,ax
        and bh,0111100b
        shr bh,2
        mov [tRC],bh
        and ah,011000000b
        shr ah,6
        mov [tCAS],ah

; read data
        mov al,1
        call GetData
        or al,al
        jz l1
        mov bx,word ptr cs:[regPLLCtrl1]
        and bh,011111110b
        mov bh,al
        ;mov word ptr cs:[regPLLCtrl1],bx  - сыюъшЁєхь чряшё№ т pllctrl

        ;and al,1
        mov al,0
        mov [tDVI],al
;        mov ax,cs
;        mov di,offset clock5
;        mov word ptr ss:[di],"  "
;        mov word ptr ss:[di+2],"  "
;        mov word ptr ss:[di+4],"  "
;        mov word ptr ss:[di+6],"  "
;        mov word ptr ss:[di+8],"  "
;        call tostringf
;        mov di,0
;        mov bp,offset clock5
;        call view3


;        mov ax,ds
;        mov di,offset clock5
;        mov word ptr ss:[di],"  "
;        mov word ptr ss:[di+2],"  "
;        mov word ptr ss:[di+4],"  "
;        mov word ptr ss:[di+6],"  "
;        mov word ptr ss:[di+8],"  "
;        call tostringf
;        mov di,80*2
;        mov bp,offset clock5
;        call view3

;        mov ax,es
;        mov di,offset clock5
;        mov word ptr ss:[di],"  "
;        mov word ptr ss:[di+2],"  "
;        mov word ptr ss:[di+4],"  "
;        mov word ptr ss:[di+6],"  "
;        mov word ptr ss:[di+8],"  "
;        call tostringf
;        mov di,80*4
;        mov bp,offset clock5
;        call view3

;        mov ax,ss
;        mov di,offset clock5
;        mov word ptr ss:[di],"  "
;        mov word ptr ss:[di+2],"  "
;        mov word ptr ss:[di+4],"  "
;        mov word ptr ss:[di+6],"  "
;        mov word ptr ss:[di+8],"  "
;        call tostringf
;        mov di,80*6
;        mov bp,offset clock5
;        call view3

;        ret


        call viewt

        mov dx,35h
        cmp [tDVI],0
        jz setautodvi
        sub dx,4
setautodvi:
        call viewdvi

        mov [ypos],0
ll1:
        call create5
        mov bp,offset clock5+4
        mov di,(7*80+50)*2
        call view3
l1:
        mov bl,70h
        mov cx,5
        call viewcursor
l0:
;        xor ax,ax
;        int 16h
        in al,60h
        or al,al
        jz l0
        cmp al,1 ; esc
        jz exit1
        cmp al,1ch ; enter
        jz aenter
        cmp al,4bh ; <-
        jz left
        cmp al,4dh ; ->
        jz right
        cmp al,50h ; 
        jz down
        cmp al,48h ; 
        jz up

;        xor ax,ax
;        int 16h
;        cmp al,27 ; esc
;        jz exit1
;        cmp al,13 ; enter
;        jz aenter
;        cmp ax,4b00h ; <-
;        jz left
;        cmp ax,4d00h ; ->
;        jz right
;        cmp ax,5000h ; 
;        jz down
;        cmp ax,4800h ; 
;        jz up
        jmp l0
aenter:
      ; сборка draminit0
        xor ax,ax
        mov bx,word ptr [tRRD]
        shl bh,2
        or bl,bh
        mov bh,[tRP]
        shl bh,4
        or bl,bh
        xor bh,bh
        mov al,[tRAS]
        shl ax,6
        or ax,bx
        mov bx,word ptr [tRC]
        shl bl,2
        or ah,bl
        shl bh,6
        or ah,bh
        mov word ptr cs:[regDRAMInit0],ax

        ; запись draminit0 в CMOS в 3-й и 5-й регистр
        mov bx,ax
        mov al,3
        call PutData ; ah - в 3-м
        mov ah,bl
        mov al,5
        call PutData ; ah - в 5-м

      ; сборка pll
      mov bx,word ptr cs:[regPLLCtrl1]
      xor ax,ax
      mov al,bh
      add ax,[cpos]          ; учет смещения
      mov bh,al
      mov word ptr cs:[regPLLCtrl1],bx
      ; запись частоты в CMOS в 1-й регистр
      mov ah,bh
      and ah,011111110b
      or ah,[tDVI]
      mov al,1
      call PutData

      ; реинициализация регистров
      call    OEMInitWakeUp

exit1: ret

left:
  cmp [ypos],7
  jz dvi_left
  cmp [ypos],0
  jnz le2
  mov si,[cpos]
  sub si,2
  call mclock
  cmp ax,18
  jbe l0
  call create5
  jmp le3

dvi_left:
  cmp [tDVI],0
  jz l1

  mov si,30h
dvi_left_loop:
  mov dx,si
  call viewdvi

  mov bl,70h
  mov cx,5
  call viewcursor
  call hrefresh4

  inc si
  cmp si,36h
  jnz dvi_left_loop
  mov [tDVI],0
  jmp l1
le2:
  movzx bx,byte ptr [ypos]
  mov si,offset tRRD
  cmp byte ptr [si+bx-1],0
  jz l0
  call create5m
le3:
  mov si,3
lp1:
  mov cx,12
  mov bp,offset clock5+4
  lea bp,[bp+si-4]
  mov di,(7*80+50)*2
  xor dx,dx
  mov bx,80*2
  movzx ax,byte ptr [ypos]
  mul bx
  add di,ax
  call view3
  mov bl,70h
  mov cx,5
  call viewcursor
  call hrefresh4
  dec si
  jnz lp1

  cmp [ypos],0
  jnz le1
  dec word ptr [cpos]
  jmp ll1
le1:
  movzx bx,byte ptr [ypos]
  mov si,offset tRRD
  dec byte ptr [si+bx-1]
  push bx
  call viewt
  pop bx
  mov [ypos],bl
  jmp l1

right:
  cmp [ypos],7
  jz dvi_right
  cmp [ypos],0
  jnz re2
  mov si,[cpos]
  sub si,2
  call mclock
  cmp ax,246
  ja l0
  call create5
  jmp re3

dvi_right:
  cmp [tDVI],1
  jz l1

  mov si,35h
dvi_right_loop:
  mov dx,si
  call viewdvi

  mov bl,70h
  mov cx,5
  call viewcursor
  call hrefresh4

  dec si
  cmp si,2fh
  jnz dvi_right_loop
  mov [tDVI],1
  jmp l1

re2:
  movzx bx,byte ptr [ypos]
  mov di,offset tRRDmx
  mov al,cs:[di+bx-1]
  mov si,offset tRRD
  cmp al,[si+bx-1]
  jz l0
  call create5m
re3:
  mov si,3
lp2:
  mov cx,12
  mov bp,offset clock5+4
  sub bp,si
  add bp,4
  mov di,(7*80+50)*2
  xor dx,dx
  mov bx,80*2
  movzx ax,byte ptr [ypos]
  mul bx
  add di,ax

  call view3

  mov bl,70h
  mov cx,5
  call viewcursor

  call hrefresh4
  dec si
  jnz lp2

  cmp [ypos],0
  jnz re1
  inc word ptr [cpos]
  jmp ll1
re1:
  movzx bx,byte ptr [ypos]
  mov si,offset tRRD
  inc byte ptr [si+bx-1]
  push bx
  call viewt
  pop bx
  mov [ypos],bl
  jmp l1

down:
        in al,60h
        or al,al
        jnl down

  cmp [ypos],7
  jz l0
  mov bl,17h
  mov cx,5
  call viewcursor
  inc [ypos]
  mov bl,70h
  mov cx,5
  call viewcursor
  jmp l1

up:
        in al,60h
        or al,al
        jnl up

  cmp [ypos],0
  jz l0
  mov bl,17h
  mov cx,5
  call viewcursor
  dec [ypos]
  mov bl,70h
  mov cx,5
  call viewcursor
  jmp l1


ViewSetUpBios endp

szstr1 db "Voodoo5 4500 DVI BIOS - Version 1.18.b04sp"
szstr2 db "Copyright (C) 1990-2000 Elpin Systems, Inc."
szstr3 db "Modified (C) 2012 Rainbow."
text0  db "Press F1 to enter setup, F2 for default settings."
text1  db "VGA Bios Setup v1.2 (for 123456789012)"
text2  db "[,,,] - select, [Enter] - apply and exit, [Esc] - exit"
text3  db "Video clock:"
text4  db "row active to row active (tRRD):"
text5  db "RAS to CAS delay (tRCD):"
text6  db "row precharge (tRP):"
text7  db "minimum active time (tRAS):"
text8  db "minimum row cycle time (tRC):"
text9  db "latency (tCAS):"
text10 db "DVI out:"
clock5 db 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0
cpos dw 0
ypos db 0
tRRD db 0
tRCD db 0
tRP  db 0
tRAS db 0
tRC  db 0
tCAS db 0
tRRDmx db 3
tRCDmx db 3
tRPmx  db 3
tRASmx db 15
tRCmx  db 15
tCASmx db 3
tDVI db 0

Patch32KROM     endp

;**********************************************************************
IF TVOUT_BIOS
;
;
;       I2CWriteAuxEEPROM - Write the Auxiliary EEPROM TV out data
;       Designed for ATMEL 24C01A not the 24C01
;
;       Entry:  DX = I/O address of I2C register
;                               AL = Byte for EEPROM
;
        public  I2CWriteAuxEEPROM
I2CWriteAuxEEPROM       proc
        assume  ds:nothing, es:nothing

        push    ecx
        push    bx

        mov     bl,al                                   ;Save data to be written
        mov     cx,5h
RetryWrite:
        dec     cx
        jz              UltimateWriteFail

        call    I2CStart          ; Send a start on the I2C
; The 24C01A requires a dummy write to setup the read address
        mov     al, 0A0h                                ; Required write cycle to set address
        call    I2CSendByte                     ; Send 24C01A address
        jnc     I2CWrite1
        call    I2CStop                         ; Failed, try again at top
        jmp     RetryWrite
I2CWrite1:
        mov     al, ah                          ; Set Address to 0 (dummy write)
        call    I2CSendByte
        jnc     I2CWrite2
        call    I2CStop                         ; Failed, try again at top
        jmp     RetryWrite
I2CWrite2:

        mov     al,bl
;AL = Data to write
        call    I2CSendByte                     ; Write the BYTE

UltimateWriteFail:
        call    I2CStop                         ;  * This reset sequence *

        pop     bx
        pop     ecx
        ret
I2CWriteAuxEEPROM       endp
;*********************************************************************
;CalcNVRAMChecksum - Calculates the NVRAM checksum.
;Checksum(Written to NVRAM byte 127) = 100h - (Sum of NVRAM byte 0-126)
;       Entry:  DX = I/O address of I2C register
; Exit:         NVRAM byte 127 written checksum

        public  CalcNVRAMChecksum
CalcNVRAMChecksum       proc    near
        push    ax
        push    bx
        push    cx


        xor     bx,bx                                           ;Clear checksum accumulator

        mov     cx,127                                  ;Read 127 bytes
ReadNextByte:
        mov     ah,cl                                           ;Set NVRAM read address in AH
        dec     ah
        call    I2CReadAuxEEPROM                ;Read byte from NVRAM
        add     bl,al                                           ;Added byte into BL
        loop    ReadNextByte

        mov     ax,100h
        sub     ax,bx                                           ;Calculate checksum.

;AL = Checksum to write.

        mov     ah,127                                  ;Write checksum to NVRAM byte 127
        call    I2CWriteAuxEEPROM


        pop     cx
        pop     bx
        pop     ax

        ret
CalcNVRAMChecksum       endp

;*********************************************************************
ENDIF

IF      DVI_BIOS
        %out    !                               DVI BIOS

;*********************************************************************
                        public  DeterminePanelSize
;DeterminePanelSize parses the panel EDID block to determine the panel
;size.

DeterminePanelSize              proc            near
        pusha
;Check if the panel has EDID 1.X or 2.X

        xor     si,si                                                   ;Read first 4 bytes of panel
        mov     cx,4                                                    ;EDID block to see EDID block ver.
        call    DFPReadByte

        cmp     ebx,000FFFFFFh                          ;Are we EDID 1.X
        je              ParseEDID1_0                            ;Jump if we're EDID 1.X

;We must be EDID 2.X.  Get XRes size and we're done.
        mov     si,76h
        mov     cx,2
        call    DFPReadByte                                     ;Read XRes
        xchg    bh,bl                                                   ;BX = XRes
        mov     ax,bx                                                   ;Save XRes in AX
        jmp     DONE

ParseEDID1_0:
;*********************************************************************
ParseEstablishedTiming:
;Parse established timing field
        mov     si,23h                                     ;Read 3 bytes from offset 23h
        mov     cx,3
        call    DFPReadByte                                     ;Read established timing field

;Test for 1280x1024
        mov     ax,1280
        test    ebx,FLD_EDID_1280
        jnz     ParseStandardTiming             ;Jump if 1280x1024 mode supported

;Test for 1024x768
        mov     ax,1024
        test    ebx,FLD_EDID_1024
        jnz     ParseStandardTiming             ;Jump if 1024x768 mode supported

;Test for 800x600
        mov     ax,0800
        test    ebx,0C003h
        jnz     ParseStandardTiming             ;Jump if 800x600 mode supported

;Test for 640x480
        mov     ax,0640                                         ;We must at least support 640x480

;*********************************************************************
ParseStandardTiming:
;Parse Standard Timing field
        mov     si,26h
        mov     cx,8                                                    ;There are 8 standard table entries

GetNextStandardTiming:
        push    cx
        mov     cx,1
        xor     ebx,ebx
        call    DFPReadByte                                     ;Read a standard timing field
        cmp     bl,01h                                          ;Did we hit the end of the timing field?
        jne     CalcXRes                                                ;Jump if not the end.

;Must of hit the end of the Standard timing field
        pop     cx
        jmp     ParseDetailedTimingsField       ;Now parse detailed timing field

CalcXRes:
;Active pixels = (value + 31) * 8
        add     bx,31                                                   ;Add into value 31
        shl     bx,03h                                          ;Multiply value by 8
        cmp     ax,bx                                                   ;Check if we found the largest panel size
        jge     GotoNextStandardTiming

;Does the BIOS actually support the panel size found
        call    CheckIfSupportedPanelSize
        jnc     GotoNextStandardTiming  ;Jump if we don't support the panel.

        mov     ax,bx                                                   ;Save largest panel size

GotoNextStandardTiming:
        add     si,02                                                   ;Goto the next panel entry
        pop     cx
        loop    GetNextStandardTiming   ;Go and load next standard timing field

;*********************************************************************
ParseDetailedTimingsField:
        mov     cx,4                                                    ;There are 4 detailed timing fields
        mov     si,36h

GetNextDetailedTiming:
        push    cx
        mov     cx,2
        xor     ebx,ebx
        call    DFPReadByte                                     ;Read a detailed timing field
        add     si,2                                                    ;Point SI to Horizontal Active Area

        or              bx,bx                                                   ;Did we hit a monitor descriptor block??
        jz              GotoNextDetailedTiming  ;Jump if we did a monitor descriptor block
        cmp     bx,0101h                                                ;Did we hit the end of the table
        jne     GetHorizontalActiveArea ;Get the Xres

        pop     cx                                                              ;All done.  End of list.  C-Ya
        jmp     Done

GetHorizontalActiveArea:
        mov     cx,3
        call    DFPReadByte                                     ;Get XRes

        mov     cl,bl                                                   ;BL[7:4] = Upper four bits of XRes
        shr     cl,04                                                   ;CH = Upper four bits of XRes

        shr     ebx,16                                                  ;BL = Lower 8 bits of the XRes
        mov     bh,cl                                                   ;BX = 12 bit XRes

        cmp     ax,bx                                                   ;Compare XRes against panel size.
        jge     GotoNextDetailedTiming

;Does the BIOS actually support the panel size found
        call    CheckIfSupportedPanelSize
        jnc     GotoNextDetailedTiming

        mov     ax,bx                                                   ;Save largest panel size

GotoNextDetailedTiming:
        add     si,16                                                   ;Goto the next detailed timing
        pop     cx
        loop    GetNextDetailedTiming

;*********************************************************************

DONE:

;!!! Rainbow
        mov     bl,CFG_DFP_SIZE_1600            ;1600x1200 panel
        cmp     ax,1600                         ;Check if we're a 1600x1200 panel
        jge     ProgramPanelSize                ;Jump if we are 1600x1200

        mov     bl,CFG_DFP_SIZE_1280            ;1280x1024 panel
        cmp     ax,1280                         ;Check if we're a 1280x1024 panel
        jge     ProgramPanelSize                ;Jump if we are 1280x1024

        mov     bl,CFG_DFP_SIZE_1600            ;1600x1200 panel
        cmp     ax,1600                         ;Check if we're a 1600x1200 panel
        je      ProgramPanelSize                ;Jump if we are 1600x1200

        mov     bl,CFG_DFP_SIZE_1280            ;1280x1024 panel
        cmp     ax,1280                         ;Check if we're a 1280x1024 panel
        je      ProgramPanelSize                ;Jump if we are 1280x1024

        mov     bl,CFG_DFP_SIZE_1024            ;1024x768 panel

ProgramPanelSize:
        call    GetCRTCAddr
        mov     al,SCRATCH_REG3
        call    GetIndexRegister
        and     ah,CFG_DFP_SIZE_MASK            ;Clear bits 2 and 1.
        or              ah,bl                                                   ;OR in panel size
        out     dx,ax

        popa

        ret
DeterminePanelSize              endp

;**********************************************************************
;This routine check if the panel size is support by the BIOS.  This is done
;by comparing the horizontal resolution against support panel sizing.
;Entry:         BX = Panel size
;Exit:          Carry flag set if panel is supported.
;                               Carry   flag NOT set if panel isn't supported.

public  CheckIfSupportedPanelSize
CheckIfSupportedPanelSize               proc    near

                cmp     bx,1024                                         ;Is the XRes 1024
                je              PanelSizeIsSupported            ;This panel is supported.  Jump.
                cmp     bx,1280                                         ;Is the XRes 1280
                je              PanelSizeIsSupported            ;This panel is supported.  Jump.
                cmp     bx,1600                                         ;Is the XRes 1600
                je              PanelSizeIsSupported            ;This panel is supported.  Jump.

PanelSizeIsNOTSupported:
                clc
                ret

PanelSizeIsSupported:
                stc
                ret

CheckIfSupportedPanelSize               endp
;
;       DetermineFPSideScaling - Will check the EDID at offset 0x23
;       to determine if the FlatPanel supports Monitor Side Scaling
;       by checking if more than one mode is supported in the Standardized
;       Modes section of the EDID
; If panel side scaling is supported, Scratch Register 2 bit 3, CR1F[3],
; is set.
;
;       Entry:  None
;       Exit:           None
;
        public  CheckFPSideScaling
CheckFPSideScaling      proc    near
        assume  ds:nothing, es:nothing
        pushad

        mov     cx,3                            ;Read 3 bytes from offset 23h
        mov     si,23h
        call    DFPReadByte

        xor     al,al
        mov     cx,24                   ; 24 bits to check
CheckingBit:
        bt              ebx,0
        jnc     BitIsZero
        inc     al
BitIsZero:
        shr     ebx,1
        loop    CheckingBit

        xor     bl,bl

        cmp     al,1
        jle     WritePanelSideScalingInfo
        mov     bl,FLD_PANELSCALING

WritePanelSideScalingInfo:
        call    GetCRTCAddr
        mov     al,SCRATCH_REG3
        call    GetIndexRegister
        and     ah,not FLD_PANELSCALING ;Clear previous bit
        or              ah,bl                                                   ;OR in panel side scaling info
        out     dx,ax


        popad
        ret
CheckFPSideScaling      endp

;**********************************************************************

;This routine checks the I2C bus for a panel and MT panel chip.
;If both are detected, ScratchRegister2[2] is set.
;Will return carry flag set if panel detected.
        public  CheckForPanel
CheckForPanel           proc    near
        push    dx
        push    bx
        push    ax


        call    DDCEnableDFP
        jz         ErrorCheckForPanel       ;Jump if no DVI display

        xor     si,si                                                   ;Read first 4 bytes of panel
        mov     cx,4                                                    ;EDID block to see EDID block ver.
        call    DFPReadByte
  jc    ErrorCheckForPanel       ;Jump if no DVI display

        cmp     ebx,0FFFFFFFFh                          ;If we're reading back 0FFFFFFFFh, no panel attached
  je    ErrorCheckForPanel       ;Jump if no DVI display


FoundPanel:

;If we're here, we must of found both the DVI and MT chip.
;Now set ScratchRegister2[2]

        call    CheckFPSideScaling
        call    DeterminePanelSize

SetPanelActiveBit:
        call    GetCRTCAddr
        mov     al,SCRATCH_REG3
        call    GetIndexRegister
        and     ah,not FLD_DVI
        or    ah,FLD_DVI
        out   dx,ax
  stc
        jmp     short ExitCheckForPanel

ErrorCheckForPanel:

        clc


ExitCheckForPanel:

        pop     ax
  pop     bx
  pop     dx
  ret
CheckForPanel           endp

;**********************************************************************

ENDIF

        end
;
;       Copyright (c) 1990-1998 Elpin Systems, Inc.
;       All rights reserved.
;
