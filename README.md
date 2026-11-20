# neo-login

A neobrutal, monochrome "tech console" login screen for **greetd**, written in QML for **Quickshell**.
Hard shadows, hazard stripes, kanji labels, a scrolling caution tape, and two animated sequences:

- **Success:** screen wipe, boot-style log (`[ OK ]` lines), sync-rate bar, `WELCOME` inversion, then the session starts.
- **Failure:** red flash and shake, a retries counter, then a self-destruct countdown with a short input lockout.

> Preview in any browser, no install: open `preview/index.html` (password `open` succeeds, anything else triggers the alarm).

Features: user avatar and name, password field with reveal toggle, session switcher (segmented tabs for 3 or fewer sessions, `◀ ▶` arrows for more; Tab cycles), clock and date, suspend / reboot / shutdown, hostname chip, light/dark invert toggle (dark by default).

## Requirements

- `greetd` and `quickshell`
- A compositor to host the greeter. `cage` is the simplest (it shows one window fullscreen). The theme uses a normal window, not layer-shell, so it works under cage.
- A CJK font for the kanji labels (e.g. `noto-fonts-cjk`). Space Mono and Archivo Black are bundled.

## Install

```sh
git clone https://github.com/YOURUSER/neo-login && cd neo-login
./install.sh          # installs to /usr/local/share/neo-login, never edits greetd config
```

Arch / EndeavourOS: a `PKGBUILD` is included (`makepkg -si`) and installs to `/usr/share/neo-login`.

Try it in a window first (demo mode: no greetd socket needed, password `open`, Esc quits):

```sh
cage -s -- env QT_QPA_PLATFORM=wayland quickshell -p /usr/local/share/neo-login
```

Then point greetd at it. Back up `/etc/greetd/config.toml` and set the `[default_session]` command:

```toml
[default_session]
command = "cage -s -- env QT_QPA_PLATFORM=wayland QT_WAYLAND_DISABLE_WINDOWDECORATION=1 quickshell -p /usr/local/share/neo-login"
user = "greeter"
```

Some GPUs need `env WLR_NO_HARDWARE_CURSORS=1` before `cage` and/or `QSG_RHI_BACKEND=opengl` next to the other env vars.
Keep a spare TTY (Ctrl+Alt+F3) for your first boot, and restore the backup if anything goes wrong.

## Configuration

Edit `/etc/neo-login/config.json` (falls back to the `config.json` shipped in the theme directory). Missing keys use the defaults below.

| Key | Default | Meaning |
|---|---|---|
| `user` | auto | Account to log in. Empty = first normal user (UID 1000-59999 with a real shell) |
| `displayName` | user | Name shown on the card (uppercased) |
| `avatar` | AccountsService icon | Image path; falls back to the initial letter |
| `defaultSession` | `"hyprland"` | Case-insensitive match against session name/Exec |
| `inverted` | `true` | `true` = white on black, `false` = black on white |
| `showHost` | `true` | Hostname chip |
| `maxAttempts` | `3` | Failures before the lockout/alarm |
| `lockoutSeconds` | `5` | Lockout length after the alarm (or the whole lockout if the alarm is off) |
| `sessionDirs` | `["/usr/share/wayland-sessions"]` | Where to look for `.desktop` sessions |
| `animations.success` | `true` | The ~3 s "connecting" sequence before launch |
| `animations.alarm` | `true` | The red self-destruct sequence |

## Notes

- **The alarm is cosmetic.** The lockout only slows the UI. Real brute-force protection is PAM (`pam_faillock`); configure that separately.
- The success animation adds about 3 seconds before the session starts; set `animations.success` to `false` to skip it.
- Single-user for now: the greeter authenticates the configured/detected user.
- Auth messages are logged by Quickshell (never the password). To debug, send output to a file: `... quickshell -p <dir> >/tmp/greeter.log 2>&1`.

## Troubleshooting

- **Blank screen:** run the nested test above and read the terminal output; check the greeter log.
- **Correct password rejected:** an account lockout may be active (`faillock --user "$USER"`, reset with `sudo faillock --user "$USER" --reset`), or this theme's own lockout is still counting down.
- **Power buttons do nothing:** the `greeter` user may lack polkit permission for `systemctl poweroff/reboot/suspend`.
- **Boxes instead of kanji:** install a CJK font.

## Uninstall

`./install.sh --uninstall`, then restore your previous `command` in `/etc/greetd/config.toml`.

## Credits and license

MIT (see `LICENSE`). Bundled fonts: Space Mono and Archivo Black, SIL OFL (licenses in `greetd-quickshell/fonts/`).
Visual style is inspired by anime mecha and cyberpunk interface design; this project is not affiliated with or endorsed by any rights holders and uses none of their logos or assets.
