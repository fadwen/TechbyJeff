# CopilotKey

Companion script for the Tech by Jeff post
[PowerToys: A Tour, and Taking Back the Copilot Key](https://techbyjeff.net/powertoys-tour-and-the-copilot-key/).

## Watch-KeyState.ps1

Logs every key transition the system reports for a short window, after any remapping has
happened. It polls `GetAsyncKeyState` for all 255 virtual keys about 200 times a second and
prints one line per down or up edge.

```powershell
.\Watch-KeyState.ps1 -Seconds 90
```

Then press the key you want to identify, hold it together with another key, and press Esc.
Each line shows the elapsed time, the edge, the virtual-key code, and its name:

```text
listening 90 s (Esc ends early)
   9.916s  DOWN  0x5D Apps
   9.966s  UP    0x5D Apps
  18.633s  DOWN  0x5D Apps
  18.988s  DOWN  0x43 C
  19.157s  UP    0x43 C
  19.449s  UP    0x5D Apps
  35.234s  DOWN  0x1B Escape
  35.357s  UP    0x1B Escape
ended by Esc
```

That capture is from a Surface Pro 11 with PowerToys Keyboard Manager switched off and the
Windows **Customize Copilot key on keyboard** setting on **Right control**. The Copilot key
on that keyboard arrives as Apps, so the Windows setting has nothing to act on.

`-LogPath` appends the same lines to a file. Mouse buttons are skipped. It needs Windows
PowerShell 5.1 or PowerShell 7 and nothing else.

The script sees keys pressed in any window while it runs, which is the point. Close anything
you would rather not have in the log before you start it.
