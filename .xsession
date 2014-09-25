#!/bin/ksh -l
# Simulate "login shell"
. "$HOME"/.profile
. "$HOME"/.kshrc

DPI=100

__is_docked() {
	xrandr | tee -a .xrandr.log | grep -E 'HDMI[0-9-]+ connected'
}

__is_4k() {
	xrandr | tee -a .xrandr.log | grep 3840 2>/dev/null >/dev/null
}

if [ -z "$SSH_AGENT_PID" ] && [ -x /usr/bin/ssh-agent ]; then
	for k in id_rsa id_ecdsa id_ecdsa_sk id_ed25519 id_ed25519_sk id_dsa; do
		if [ -f "$HOME/.ssh/$k" ]; then
			eval $(ssh-agent -s)
			ssh-add </dev/null
			break
		fi
	done
fi
if [ "$SSH_AGENT_PID" ]; then
	ssh-add -D </dev/null
	eval $(ssh-agent -s -k)
fi

xrdb "$HOME"/.Xresources

if __is_docked; then
	autorandr docked
fi

if __is_4k; then
	DPI=200
fi
echo "Xft.dpi: $DPI" | xrdb -merge

# setxkbmap 'us,ru' -option 'grp:shifts_toggle,compose:ralt'
setxkbmap 'us,ru' -option 'ctrl:nocaps,grp:shifts_toggle,compose:ralt'
xcape &
sxhkd &

# Disable core dumps
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

exec icewm-session
