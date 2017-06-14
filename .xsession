#!/bin/ksh -l
# Simulate "login shell"
. "$HOME"/.profile
. "$HOME"/.kshrc

eval $(dbus-launch --sh-syntax)

if [ -d /usr/local/share/fonts ]; then
	for d in /usr/local/share/fonts/*; do
		xset +fp "$d"
	done
fi

DPI=100

__is_docked() {
	xrandr | grep -E 'HDMI[0-9-]+ connected'
}

__is_4k() {
	xrandr | grep 3840 2>/dev/null >/dev/null
}

if type keychain; then
	eval $(keychain --eval --agents ssh,gpg)
fi


if __is_docked; then
	autorandr docked
fi

if __is_4k; then
	DPI=200
fi

xrdb "$HOME"/.Xresources

echo "Xft.dpi: $DPI"                      | xrdb -merge
echo "Xcursor.theme: Adwaita"             | xrdb -merge
echo "Xcursor.size: $((24 * $DPI / 100))" | xrdb -merge

setxkbmap 'us,ru' -option 'ctrl:nocaps,grp:shifts_toggle,compose:ralt'
xcape &
sxhkd &

ulimit -Sc 0

{
	sleep 3
	if [ -d "$HOME"/.config/wallpaper ]; then
		while :; do
			find "$HOME"/.config/wallpaper -type f |
				sort --random-sort |
				while read file; do
					feh --no-fehbg --bg-fill "$file"
					sleep $((60 * 30))
				done
		done
	else
		xsetroot -solid black
	fi
} &

xset b off
xidle &

emacs --daemon &

xinput set-prop "/dev/wsmouse" "WS Pointer Wheel Emulation" 1
xinput set-prop "/dev/wsmouse" "WS Pointer Wheel Emulation Button" 2
xinput set-prop "/dev/wsmouse" "WS Pointer Wheel Emulation Axes" 6 7 4 5

conky &
urxvtd &
dunst &

exec icewm-session --nobg
