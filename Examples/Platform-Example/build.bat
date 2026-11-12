@echo off
setlocal enabledelayedexpansion
:: ---------------------------------------------------------------
:: Project settings — update these for your project
::
:: TITLE_ID must be exactly 9 characters: 4 letters + 5 digits.
:: ---------------------------------------------------------------
set TARGET=Platform-Example
set TITLE_ID=ODIN00006
set TITLE=Odin Platform Example
:: ---------------------------------------------------------------
:: VitaSDK - default install location of vdpm's bootstrap-vitasdk.ps1.
:: Override by setting VITASDK before running this script.
:: ---------------------------------------------------------------
if "%VITASDK%"=="" set VITASDK=C:\vitasdk
set PATH=%VITASDK%\bin;%PATH%
where arm-vita-eabi-gcc >nul 2>nul
if errorlevel 1 (
    echo arm-vita-eabi-gcc not found. Check VITASDK=%VITASDK%
    exit /b 1
)
:: ---------------------------------------------------------------
:: Folder layout
:: ---------------------------------------------------------------
set BUILD=build
set ODINASM=odin_asm
set LIB=..\..\lib
set BRIDGES=libm vita2d
:: Optimisation level for the bridge .c files.
set BRIDGE_OPT=-O2
set ARCH=-march=armv7-a -mtune=cortex-a9 -mfpu=neon -mfloat-abi=hard
:: ---------------------------------------------------------------
:: Clean previous build
:: ---------------------------------------------------------------
if exist %BUILD%   rd /s /q %BUILD%
if exist %ODINASM% rd /s /q %ODINASM%
mkdir %BUILD%
mkdir %ODINASM%
echo === Building %TARGET% ===
:: ---------------------------------------------------------------
:: Compile Odin -> ARM assembly
:: ---------------------------------------------------------------
echo.
echo Building Odin assembly...
odin build . -target:freestanding_arm32 -o:speed -build-mode:asm -no-entry-point -min-link-libs -no-thread-local -microarch:cortex-a9
if errorlevel 1 goto :fail
for %%f in (*.S) do (
    ren "%%f" "%%~nf.odin.s"
    move "%%~nf.odin.s" "%ODINASM%\" >nul
)
echo Compiling Odin assembly...
for %%f in (%ODINASM%\*.odin.s) do (
    echo  - %%f
    arm-vita-eabi-gcc -c "%%f" -o "%BUILD%\%%~nf.o" %ARCH%
    if errorlevel 1 goto :fail
    REM Odin emits soft-float objects; VitaSDK is hard-float and ld rejects the mix
    REM unless the ABI attributes are dropped. Floats cross into SCE libs via bridge.c.
    REM libm calls made by Odin (sinf, fmaxf, ...) are renamed to the vito_* wrappers
    REM in lib\libm\bridge.c, which convert between the two float conventions.
    arm-vita-eabi-objcopy --remove-section .ARM.attributes --redefine-syms="%LIB%\libm\redefine.syms" "%BUILD%\%%~nf.o"
    if errorlevel 1 goto :fail
)
:: ---------------------------------------------------------------
:: Compile main.c entry shim
:: ---------------------------------------------------------------
echo.
echo Compiling main.c...
arm-vita-eabi-gcc -c main.c -o "%BUILD%\main.o" %ARCH%
if errorlevel 1 goto :fail
:: ---------------------------------------------------------------
:: Compile library ABI bridges, one per lib\<name>\bridge.c listed in BRIDGES
:: ---------------------------------------------------------------
echo.
echo Compiling lib bridges...
for %%b in (%BRIDGES%) do (
    echo  - %LIB%\%%b\bridge.c
    arm-vita-eabi-gcc -c "%LIB%\%%b\bridge.c" -o "%BUILD%\%%b_bridge.o" %ARCH% %BRIDGE_OPT%
    if errorlevel 1 goto :fail
)
:: ---------------------------------------------------------------
:: Link ELF (stub libs resolve SCE imports at load time)
:: ---------------------------------------------------------------
set OBJ=
for %%f in (%BUILD%\*.o) do set OBJ=!OBJ! %%f
echo.
echo Linking ELF...
:: -Wl,-q keeps relocations in the ELF. vita-elf-create turns them into .sce.rel so
:: the loader can relocate the module (real hardware randomizes the load address).
:: __sce_headroom leaves 64 KiB between the code and data segments. vita-elf-create
:: appends its SCE metadata to the code segment without checking that it fits; when
:: the code ended just below a 64 KiB boundary it overflowed and the tool crashed
:: (exit -1073740940, then "Cannot generate module NID" from vita-make-fself).
arm-vita-eabi-gcc -o "%BUILD%\%TARGET%.elf" %OBJ% %ARCH% -Wl,-q -Wl,--defsym,__sce_headroom=0x10000 ^
    -lvita2d -lSceDisplay_stub -lSceGxm_stub -lSceSysmodule_stub -lSceCtrl_stub ^
    -lScePgf_stub -lScePvf_stub -lSceCommonDialog_stub -lSceAppMgr_stub -lSceSysmem_stub -lSceLibKernel_stub -lSceIofilemgr_stub ^
    -lfreetype -lpng16 -ljpeg -lz -lbz2 -lm
if errorlevel 1 goto :fail
:: ---------------------------------------------------------------
:: Package: ELF -> velf -> eboot.bin, param.sfo -> .vpk
:: ---------------------------------------------------------------
echo.
echo Packaging VPK...
vita-elf-create "%BUILD%\%TARGET%.elf" "%BUILD%\%TARGET%.velf"
REM A crash gives a negative exit code, which "if errorlevel 1" does not catch.
if not "%errorlevel%"=="0" goto :fail
vita-make-fself -c "%BUILD%\%TARGET%.velf" "%BUILD%\eboot.bin"
if errorlevel 1 goto :fail
vita-mksfoex -s TITLE_ID=%TITLE_ID% "%TITLE%" "%BUILD%\param.sfo"
if errorlevel 1 goto :fail
:: Everything in assets\ is packed as app0:/assets/..., and sce_sys\ (LiveArea icon and
:: pictures; see tools\make_livearea.py) as sce_sys/... A folder that does not exist is skipped.
set VPK_ADD=
if exist assets  set VPK_ADD=!VPK_ADD! -a assets=assets
if exist sce_sys set VPK_ADD=!VPK_ADD! -a sce_sys=sce_sys
vita-pack-vpk -s "%BUILD%\param.sfo" -b "%BUILD%\eboot.bin" !VPK_ADD! "%TARGET%.vpk"
if errorlevel 1 goto :fail
echo.
echo Build complete: %TARGET%.vpk
exit /b 0
:fail
echo.
echo Build FAILED
exit /b 1
