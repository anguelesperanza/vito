@echo off
setlocal enabledelayedexpansion
:: ---------------------------------------------------------------
:: Project settings — update these for your project
::
:: TITLE_ID must be exactly 9 characters: 4 letters + 5 digits.
:: ---------------------------------------------------------------
set TARGET=Vita2D-Example
set TITLE_ID=ODIN00002
set TITLE=Odin vita2d Example
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
set ARCH=-march=armv7-a -mtune=cortex-a9 -mfpu=neon -mfloat-abi=hard
:: ---------------------------------------------------------------
:: Clean previous build
:: ---------------------------------------------------------------
if exist %BUILD%   rd /s /q %BUILD%
if exist %ODINASM% rd /s /q %ODINASM%
mkdir %BUILD%
mkdir %ODINASM%
echo.
echo === Building %TARGET% ===
:: ---------------------------------------------------------------
:: Compile Odin -> ARM assembly
:: ---------------------------------------------------------------
echo.
echo Building Odin assembly...
odin build . -target:freestanding_arm32 -o:speed -build-mode:asm -no-entry-point -min-link-libs -no-thread-local
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
    arm-vita-eabi-gcc -c "%LIB%\%%b\bridge.c" -o "%BUILD%\%%b_bridge.o" %ARCH%
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
arm-vita-eabi-gcc -o "%BUILD%\%TARGET%.elf" %OBJ% %ARCH% -Wl,-q ^
    -lvita2d -lSceDisplay_stub -lSceGxm_stub -lSceSysmodule_stub -lSceCtrl_stub ^
    -lScePgf_stub -lScePvf_stub -lSceCommonDialog_stub -lSceAppMgr_stub -lSceSysmem_stub -lSceLibKernel_stub ^
    -lfreetype -lpng16 -ljpeg -lz -lbz2 -lm
if errorlevel 1 goto :fail
:: ---------------------------------------------------------------
:: Package: ELF -> velf -> eboot.bin, param.sfo -> .vpk
:: ---------------------------------------------------------------
echo.
echo Packaging VPK...
vita-elf-create "%BUILD%\%TARGET%.elf" "%BUILD%\%TARGET%.velf"
if errorlevel 1 goto :fail
vita-make-fself -c "%BUILD%\%TARGET%.velf" "%BUILD%\eboot.bin"
if errorlevel 1 goto :fail
vita-mksfoex -s TITLE_ID=%TITLE_ID% "%TITLE%" "%BUILD%\param.sfo"
if errorlevel 1 goto :fail
vita-pack-vpk -s "%BUILD%\param.sfo" -b "%BUILD%\eboot.bin" "%TARGET%.vpk"
if errorlevel 1 goto :fail
echo.
echo Build complete: %TARGET%.vpk
exit /b 0
:fail
echo.
echo Build FAILED
exit /b 1
