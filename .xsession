#!/bin/sh -l
# Simulate "login shell"

. "$HOME"/.profile
. "$HOME"/.kshrc

DPI="${DPI:-100}"

cleanup() {
	pkill -P $$
}


for sig in INT QUIT HUP TERM; do
	trap "
    cleanup
    trap - "$sig" EXIT
    kill -s "$sig" "'"$$"' "$sig"
done

trap cleanup EXIT

__start() {
	C="$1"
	shift
	if type "$C"; then
		dunstify "Running - $C"
		"$C" "$@"
	else
		dunstify "Not found - $C"
	fi
}

if type openrc
then
    for level in default graphical
    do
        mkdir -p "${XDG_CONFIG_HOME:-"$HOME"/.config}/rc/runlevels/$level"
        openrc --user "$level"
    done
    rc-service --user --list | xargs -i rc-service --user {} start
fi

eval $(dbus-launch --sh-syntax | tee "$HOME/.xenv")

if [ -d /usr/local/share/fonts ]; then
	for d in /usr/local/share/fonts/*; do
		xset +fp "$d"
	done
fi

__is_docked() {
	xrandr | grep -E '^(HDMI|DP)[0-9-]+ connected'
}

if __is_docked; then
	autorandr docked
fi

eval "$("$HOME"/.dotfiles/scripts/get-dpi)"
if [ "$DPI" -ge 150 ]; then
    QT_FONT_DPI=$DPI
    GDK_SCALE=1
    ELM_SCALE=2
    JVM_OPTIONS="-Dsun.java2d.uiScale=2 $JVM_OPTIONS"
    JVM_OPTIONS="-Dglass.gtk.uiScale=2 $JVM_OPTIONS"
    JAVA_OPTIONS="$JAVA_OPTIONS $JVM_OPTIONS"
    export QT_FONT_DPI GDK_SCALE ELM_SCALE JVM_OPTIONS JAVA_OPTIONS
fi

xrdb "$HOME"/.Xresources

touch "$HOME"/.Xresources."$HOSTNAME"

echo "Xft.dpi: $DPI"                      | tee    "$HOME"/.Xresources."$HOSTNAME"
echo "Xcursor.theme: Adwaita"             | tee -a "$HOME"/.Xresources."$HOSTNAME"
echo "Xcursor.size: $((24 * $DPI / 100))" | tee -a "$HOME"/.Xresources."$HOSTNAME"

xrdb -merge "$HOME"/.Xresources."$HOSTNAME"

setxkbmap 'us,ru' -option 'ctrl:nocaps,grp:shifts_toggle,compose:ralt'
xcape &

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
		if [ -x "$HOME/.fehbg" ]; then
			"$HOME/.fehbg"
		else
			xsetroot -solid black
		fi
	fi
} &

case "$(uname)" in
OpenBSD)
	sct
	;;
esac

xset b off
xidle &

xinput set-prop "/dev/wsmouse" "WS Pointer Wheel Emulation" 1
xinput set-prop "/dev/wsmouse" "WS Pointer Wheel Emulation Button" 2
xinput set-prop "/dev/wsmouse" "WS Pointer Wheel Emulation Axes" 6 7 4 5


__start wpa_gui &
__start emacs --fg-daemon &

if type keychain; then
	eval $(keychain --eval --agents ssh,gpg 2>/dev/null | tee -a "$HOME/.xenv")
fi

__start /usr/libexec/pipewire-launcher &
__start conky &
__start udiskie &
__start cbatticon &
__start urxvtd &
__start sxhkd &
__start dunst &

env | grep -v ^PS | grep -v ^DOAS | tee -a "$HOME/.xenv"
exec wm
