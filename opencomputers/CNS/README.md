# Open Computers Component Naming System (CNS)

A system that works like the Domain Name System (DNS) used on the internet
An OpenComputers component (redstone IO, adapater, screen, computer, microcontroller...) with an component id can be given a name which can then be refered to in code

Example:
Without this system:
``
local maincontroller = component.proxy("F12ACO32-A5C9B-AC2A-543C-E1B0AOC3ACB5");
local redstone_left = component.proxy("A45BA531-5BF1C-A2AB-12CB-F1C7A9A9A521");
```

With the system:
```
local main_controller = component.proxy(cns("main_controller"));
local redstone_left = component.proxy(cns("redstone_left"));
```

For more details have a look at the myRail episodes showing its setup:
https://youtu.be/lp_uL_2OQrU
