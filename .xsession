#!/bin/ksh -l
# Simulate "login shell"
. "$HOME"/.profile
. "$HOME"/.kshrc

__loop() {
    dunstify "Running - $*" 
    "$@"
    __loop "$@"
}

eval $(dbus-launch --sh-syntax | tee "$HOME/.xenv")

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
	current=$(xrandr | perl -nE 'print $1 if /current \s+ (\d+) \s* x \s* (\d+)/xmgsi')
	if [ "$current" -ge 3000 ]; then
		echo 1
	else
		xrandr | grep 3840 2>/dev/null >/dev/null
	fi
}

if type keychain; then
	eval $(keychain --eval --agents ssh,gpg 2>/dev/null | tee -a "$HOME/.xenv")
fi

if __is_docked; then
	autorandr docked
fi

if __is_4k; then
	DPI=$(($DPI * 2))
fi

xrdb "$HOME"/.Xresources

echo "Xft.dpi: $DPI" | xrdb -merge
echo "Xcursor.theme: Adwaita" | xrdb -merge
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

case "$(uname)" in
OpenBSD)
	sct 4500
	;;
esac

xset b off
xidle &

xinput set-prop "/dev/wsmouse" "WS Pointer Wheel Emulation" 1
xinput set-prop "/dev/wsmouse" "WS Pointer Wheel Emulation Button" 2
xinput set-prop "/dev/wsmouse" "WS Pointer Wheel Emulation Axes" 6 7 4 5


__loop conky &
__loop urxvtd &
__loop dunst &

if [ "$HOSTNAME" = "wks" ]; then
	xpra shadow
fi

__loop emacs --fg-daemon &


{
	while :; do
		sleep 1
		uptime | sed 's/.*://;s/,//g' | xargs -Ixxx xsetroot -name xxx
	done
} &

WM=

if type dwm; then
	WM=dwm
else
	if type icewm-session; then
		WM="icewm-session --nobg"
	fi
fi

env | grep -v ^PS | grep -v ^DOAS | tee -a "$HOME/.xenv"

exec $WM
