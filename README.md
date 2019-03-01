# 3dfx BIOS mod

BIOS for VSA100 chips with setup and overclocking without operation system.

Откопано в старых архивах!!!

Биос основан на официальных исходниках v1.18. 

### ОСОБЕННОСТИ: 

1. 3dfx logo на стартовом экране: 

![logo](https://user-images.githubusercontent.com/47675852/53657517-2ff77780-3c78-11e9-9616-047b8a7a2267.GIF)

2. VGA Bios Setup v1.1 

![biossetup](https://user-images.githubusercontent.com/47675852/53657515-2ff77780-3c78-11e9-86a5-261a493a5fb3.gif) 

### УПРАВЛЕНИЕ: 

На стартовом экране: 
F1 - Вход в VGA Bios Setup. 
F2 - Загрузить настройки "по умолчанию". 

В VGA Bios Setup: 

Курсорные клавиши - Выбор и изменение параметров. 
Enter - Применение настроек и выход. 
Esc - Выход. 

### ПРИМЕЧАНИЯ: 

VGA Bios Setup предназначен для выбора и установки частоты видеокарты, а также параметров памяти, при загрузке компьютера. Что позволяет не перешивать биос каждый раз при смене параметров. Также исчезает необходимость использовать всякие твикеры для видеокарты. 

На многочиповых видеокартах (Voodoo5) параметры устанавливаются синхронно для вскх чипов. 

Настройки сохраняются в CMOS'е. Поэтому, при сбросе CMOS'а на материнской плате настройки вернуться к первоначальным ("по умолчанию"). Могут быть проблемы с программами, включающими компьютер в заранее определенное время. 

После первой прошивки биоса необходимо обязательно запуститься с настройками "по умолчанию". При этом в CMOS материнской платы будут сохранены корректные значения параметров. Если POST материнской платы прошел успешно, то можно перезапуститься и выйти в VGA Bios Setup. 

VGA Bios Setup может не работать с USB клавиатурами. 

VGA Bios Setup может не работать на некоторых компьютерах "белой" сборки (например Hewlett Packard) с фирменными биосами на материнских платах. 

Настройки применяются при закрытии стартового экрана. Поэтому, при установке частоты, на которой видеокарта не работает, есть возможность выйти в VGA Bios Setup и установить рабочую частоту. Или по F2 установить частоту "по умолчанию". 

Если вам необходим bios для какой-то другой видеокарты, основанной на VSA-100 или на VSA-101, или обладающей специальными возможностями (TV-out, DVI-out), то обращайтесь на e-mail автора. 

Перед прошивкой bios'а неплохо бы проверить его работоспособность с помощью vgabios от nVidia или loader'а. 

Частота видеокарты на Voodoo определяется с помощью 3-х параметров. VGA Bios Setup изменяет только один из них. Поэтому шаг изменения частоты колеблется от 1 до 2. По умолчаню приняты параметры: K=1, M=3, N=114 (166 МГц). VGA Bios Setup изменяет соответственно параметр N. 

VGA Bios Setup позволяет изменять частоту от 20 МГц до 250 МГц 

Параметры "по умолчанию" можно изменить например с помощью tdfx bios editor'а. Можно эадать другие параметры K, M, N для расчета частоты. тогда шаг и полученные значения будут другими. 

При редактировании биоса с помошью tdfx bios editor'а, необходимо учитывать следующее: 
- Запрещается изменять текстовые строки, выводящиеся при загрузке. Редактор должен их вообще не показывать. 
- Запрещается вставлять новый 3dfx logo. 
При несоблюдении этих требований работоспособность bios'а скорее всего будет нарушена. 

### СБОРКА

Windows 95/98 + msvc6 + masm (можно в виртуалке поднять)
запускаем BLDVERS.BAT
