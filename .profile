ENV="$HOME"/.kshrc
export ENV
PATH=/sbin:/bin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/usr/X11R6/bin
if [ -d "$HOME/pkg" ]
then
    PATH="$PATH":"$HOME"/pkg/bin
    PATH="$PATH":"$HOME"/pkg/sbin
    MANPATH="$MANPATH:$HOME/pkg/man"
fi
LANG=ru
LC_ALL=ru_RU.UTF-8
export LC_ALL LANG
export MANPATH
