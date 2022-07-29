ENV="$HOME"/.kshrc
export ENV

PATH=/sbin:/bin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/usr/X11R6/bin:$PATH

if [ -d "$HOME/.nix-profile/" ]; then
	. "$HOME"/.nix-profile/etc/profile.d/hm-session-vars.sh
fi

for PKG_PREFIX in "$HOME" /usr; do
	if [ -d "$PKG_PREFIX/pkg" ]; then
		PATH="$PATH":"$PKG_PREFIX"/pkg/bin
		PATH="$PATH":"$PKG_PREFIX"/pkg/sbin
		MANPATH="$MANPATH:$PKG_PREFIX/pkg/man"
	fi

done

if [ -z "$XDG_RUNTIME_DIR" ] || [ "$XDG_RUNTIME_DIR" = "/tmp" ]; then
	XDG_RUNTIME_DIR="/tmp/$(id -u)-runtime-dir"

	mkdir -pm 0700 "$XDG_RUNTIME_DIR"
	export XDG_RUNTIME_DIR
fi

LANG=ru
LC_ALL=ru_RU.UTF-8
EDITOR=et
HOSTNAME=$(hostname)

SBT_HOME=$HOME/.local/sbt/
JULIA_HOME=$HOME/.local/julia-1.6.7/
PATH=$SBT_HOME/bin:$PATH
LOCAL_HOME=$HOME/.local
LOCAL_OPT=$HOME/.opt/
PATH="$LOCAL_HOME/bin:$PATH"
PATH="$PATH:$LOCAL_HOME/share/coursier/bin"
PATH="$PATH:$JULIA_HOME/bin"

export LC_ALL LANG
export MANPATH
export EDITOR
export HOSTNAME
export PATH

if [ ! "$GPG_AGENT_INFO" ]; then
	if type keychain >/dev/null; then
		eval $(keychain --eval --agents ssh,gpg 2>/dev/null)
	fi
fi

if [ ! "$DISPLAY" ]; then
	GPG_TTY="$(tty)"
fi

if [ -e "$HOME/.cargo/env" ]; then
	. "$HOME/.cargo/env"
fi

if [ -e "$HOME/.profile-private" ]; then
	. "$HOME/.profile-private"
fi

if [ -e "$HOME"/.profile."$HOSTNAME" ]; then
	. "$HOME"/.profile."$HOSTNAME"
fi

if [ -d "$LOCAL_OPT" ]; then
	for p in "$LOCAL_OPT"/*; do
		if [ -d "$p" ] && [ -d "$p/bin" ]; then
			PATH="$p"/bin:"$PATH"
		fi
	done
fi
