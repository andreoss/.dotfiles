ENV="$HOME"/.kshrc
export ENV
PATH=/sbin:/bin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/usr/X11R6/bin

for PKG_PREFIX in "$HOME" /usr; do
	if [ -d "$PKG_PREFIX/pkg" ]; then
		PATH="$PATH":"$PKG_PREFIX"/pkg/bin
		PATH="$PATH":"$PKG_PREFIX"/pkg/sbin
		MANPATH="$MANPATH:$PKG_PREFIX/pkg/man"
	fi
done

LANG=ru
LC_ALL=ru_RU.UTF-8
EDITOR=et

export LC_ALL LANG
export MANPATH
export EDITOR

if [ ! "$GPG_AGENT_INFO" ]; then
	if type keychain >/dev/null; then
		eval $(keychain --eval --agents ssh,gpg 2>/dev/null)
	fi
fi
