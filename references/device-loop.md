# The device loop: driving the app with adb and scrcpy

This is the concrete mechanic behind Stage E's "screenshot to read to act" loop. It is all
`local` work when it drives your own device and account (see `00-authorization.md`); it only
needs the `assessment` gate if an action reaches past your own instance. Either way you stay inside
scope, on your own test accounts and content.

The loop is simple and you repeat it constantly:

1. **Watch** with scrcpy.
2. **Capture** the screen and read it.
3. **Locate** the control you want (by its view-tree node).
4. **Act** (tap, swipe, type, key).
5. **Capture again** and confirm before the next action.

## Watch: scrcpy

Mirror the device so you can see what each action does:

```bash
scrcpy --stay-awake --window-title "test-device"
```

Keep it running in the background. You act through `adb`; scrcpy is your eyes. You can also click
in the scrcpy window directly, but scripted `adb input` is reproducible and goes in the log.

## Capture: screenshot

```bash
adb exec-out screencap -p > shot.png
```

Read `shot.png`. `exec-out` streams the PNG straight to the file without the shell mangling line
endings. Take one before and after every meaningful action, so you always know the state you are
acting on.

## Locate: the view tree

When you need to tap a *specific* control rather than a fixed pixel, dump the accessibility view
tree and find the node:

```bash
# dump on the device, then read it
adb shell uiautomator dump /sdcard/ui.xml
adb shell cat /sdcard/ui.xml
```

Each node carries `text`, `content-desc`, `resource-id`, `clickable`, and `bounds`. Find your
target by whichever attribute is stable (prefer `resource-id`, then `content-desc`, then visible
`text`), read its `bounds="[x1,y1][x2,y2]"`, and tap the centre:

```
centre_x = (x1 + x2) / 2
centre_y = (y1 + y2) / 2
```

```bash
adb shell input tap "$centre_x" "$centre_y"
```

Resolving the tap target from the tree instead of hardcoding coordinates means your steps survive
a different screen size or a shifted layout, and they read clearly in the log.

## Act: input

```bash
adb shell input tap X Y
adb shell input swipe X1 Y1 X2 Y2 DURATION_MS      # scroll / drag; longer duration = slower
adb shell input keyevent 4                          # BACK
adb shell input keyevent 3                          # HOME
adb shell input keyevent 66                         # ENTER
adb shell input text "hello%sworld"                 # %s is a literal space
```

`input text` does not accept raw spaces; use `%s`. For a long-press, use `input swipe x y x y 800`
(same point, long duration).

Launch a specific screen or deep link directly instead of navigating by hand when you can:

```bash
adb shell monkey -p <pkg> -c android.intent.category.LAUNCHER 1
adb shell am start -a android.intent.action.VIEW -d 'app://path' <pkg>/.SomeActivity
```

## Read the app's own logs

Beyond logcat, an app (or your instrumentation) often writes a log file under its data dir. Read
it the same way as any private file:

```bash
adb shell su -c 'cat /data/data/<pkg>/files/<app>.log'      # rooted
adb shell run-as <pkg> cat files/<app>.log                   # debuggable app
```

## Gotchas and their exact fixes

These are the ones that waste time if you have not seen them before.

**Git-Bash rewrites `/sdcard` into a Windows path.** On Windows under Git-Bash / MSYS, a path
like `/sdcard/ui.xml` gets "helpfully" converted to something like `C:/Program Files/Git/sdcard/...`
and the device command fails with "No such file or directory". Disable the conversion for those
commands:

```bash
export MSYS_NO_PATHCONV=1
adb shell uiautomator dump /sdcard/ui.xml      # now the path reaches the device intact
```

Set it for any `adb shell` command that contains a device-side absolute path.

**`adb` goes `unauthorized` or `offline`.** After a reboot, a cable reconnect, or sometimes a
reinstall, the device shows as `unauthorized` or `offline` and nothing works. Restart the adb
server and re-accept the prompt on the device:

```bash
adb kill-server
adb start-server
adb devices            # watch for the "Allow USB debugging?" prompt on the phone; tick "always"
```

`adb reconnect offline` sometimes clears a stuck `offline` without a full restart.

**`uiautomator dump` says "could not get idle state".** This happens when the UI never settles,
for example a screen with a looping animation or an auto-scrolling carousel. The dump waits for
the view tree to be idle and gives up. Options: wait and retry, interact to stop the animation
first, or skip the tree entirely and act off a screenshot by reading the control's position
visually.

**Coordinates look wrong by a constant factor.** When you read a control's position off a
screenshot that your viewer displayed downscaled, the pixel coordinates you read are in the
*displayed* size, not the device's real resolution. Multiply back to real pixels before you
`input tap`. The view-tree `bounds` are always in real device pixels, which is another reason to
prefer them over eyeballing a shrunk image.

**The app vanished mid-session.** On a low-memory device the low-memory killer can kill the app
while it is backgrounded (for example while you are reading logs). A screenshot showing the home
screen or a different app, when you expected yours, is the tell. Relaunch and continue; note it in
the log so you do not misread it as a crash.

**A reinstall silently dropped a permission.** Covered in Stage E: reinstalling a new build
resets runtime permissions and special app-ops. If a feature stops working right after you push a
new build, re-grant before concluding it regressed.

## Scope, every time

Everything here drives a real app on a real device. Act only on your own test accounts and your
own test content, only against hosts in scope. Do not open, tap into, or capture another person's
profile, messages, or data to "check behaviour". If a step would touch something outside scope,
stop and go back to the gate.
