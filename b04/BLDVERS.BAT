nmake /s /nologo
ren full.rom bios.rom

rem v5500 pci dvi
rem resub bios.rom 121a 3

rem v4500 pci dvi
resub bios.rom 121a 5
