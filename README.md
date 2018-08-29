# Handy Ultibo Helper Utilities

This might end up being a collection of helpers common to all my [Ultibo](https://ultibo.org/) projects that others might find helpful.

## Updater.pas

Testing your application on Ultibo can be an inane process of compiling, copying over to SD card, putting it in the Pi, powering on, and having to undo all of that if something is wrong.

This Updater function tries to make the turnaround time a bit quicker, as well as saving your SD card from all that wear.

##### How to use

Do once:
- connect PIN 18 to ground
- edit configuration options at the top of ```Updater.pas```
- start a web server in your Ultibo project folder, e.g., ```python -m http.server 8080```
- add the following line somewhere near the start of your entry point ```UpdateKernel(True);```

Wash rinse repeat:
- compile your app
- restart PI

#### What it does

On boot it:
- checks to see if the configured PIN (default 18) is connected to ground, if not, it skips updating
- waits for the SD card to mount
- waits for the network to come up
- tries to download a file from the configured location to a temporary file
- compares the dates of the downloaded file and the kernel on disk, if they match, it skips updating
- copies the temporary file over the existing kernel7.img file
- optionally reboots

#### Bugs

- It doesn't seem to download a changed file after a reboot, only on a hard power-off-on.
- Pressing ESCAPE to abort the update sometimes hangs.

