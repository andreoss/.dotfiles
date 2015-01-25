set -o vi

HISTSIZE=$((1 << 16))
HISTFILE="$HOME"/.history
HOSTNAME="$(hostname)"
if [ ! -e "$HISTFILE" ]

then
    touch     "$HISTFILE"
    chmod 600 "$HISTFILE"
fi

__PROMPT='> '
__PROMPT_BUF=$(mktemp)
__TITLE_UPDATE_INTERNAL=1

__LPID=0

exec 3>&1

__sub_proc() {
	__PPID="$$"
	__SPID="$(pgrep -P "$__PPID" | sed -n 1p)"
	if [ "$__SPID" -ne "$__LPID" ]; then
		ps -o args= -o etime= -o time= -p "$__SPID"
	fi
}

__title() {
	__SUB="$(__sub_proc)"
	__BUF="$(cat "$__PROMPT_BUF")"

	if [ "$__SUB" ]; then
		echo -ne "\033]0;${__BUF}: ${__SUB}\007"
	else
		echo -ne "\033]0;${__BUF}\007"
	fi >&3
}

__short_pwd() {
	__DIR=
	if [ -z "${INSIDE_EMACS-}" ]; then
		case "$PWD" in
		"$HOME")
			__DIR=
			;;
		$HOME/*)
			__DIR=${PWD##"$HOME/"}
			;;
		*)
			__DIR="$PWD"
			;;
		esac
	fi
	printf '%s' "$__DIR"
}

__git_work_tree() {
	git rev-parse --is-inside-work-tree 2>/dev/null >/dev/null
}

__git_branch() {
	if git show-ref --verify --quiet HEAD; then
		git rev-parse --symbolic-full-name --abbrev-ref HEAD
	else
		echo "(empty)"
	fi
}
__vcs_status() {
	if __git_work_tree; then
		printf '%s' "$(__git_branch)"
	fi
}

__ps1_short() {
	if [ "${USER:-}" = "root" ]; then
		__PROMPT='# '
	else
		__PROMPT="${__PROMPT:-* }"
	fi
	printf '%s' "$__PROMPT"
}

__ps1() {
	if [ "${USER:-}" = "root" ]; then
		__PROMPT='# '
	else
		__PROMPT="${__PROMPT:-* }"
	fi
	__DIR="$(__short_pwd)"

	if [ "$__DIR" ]; then
		__VCS="$(__vcs_status)"
		printf '%s %s %s\n%s' "$__VCS" "$__DIR" "${IN_NIX_SHELL-}" "$__PROMPT"
	else
		printf '%s' "$__PROMPT"
	fi

	if [ "$SSH_CLIENT" -a ! "$STY" -a "$SSH_TTY" = "$(tty)" ]; then
		echo -n "$HOSTNAME"
	fi >"$__PROMPT_BUF"

	if [ "$__VCS" ]; then
		echo "${__VCS} ${__DIR:-~}"
	else
		echo "${__DIR:-~}"
	fi >>"$__PROMPT_BUF"

}

if [ "$TERM" != "dumb" ]; then
	if [ "$__LPID" -eq 0 ]; then
		{
			while :; do
				__title
				sleep "$__TITLE_UPDATE_INTERNAL"
			done
		} &
		__LPID="$!"
	fi >/dev/null 2>&1
fi

PS1='$(__ps1)'
DOAS_PS1='$(__ps1)'
export PS1 DOAS_PS1 __LPID

JAVA_HOME=/usr/local/jdk-17/
PATH=$JAVA_HOME/bin:$PATH
SBT_HOME=$HOME/.local/sbt/
PATH=$SBT_HOME/bin:$PATH
LOCAL_HOME=$HOME/.local
PATH="$LOCAL_HOME/bin:$PATH"
PATH="$PATH:$LOCAL_HOME/share/coursier/bin"
PATH="$PATH:$HOME/pkg/bin"
MANPATH="$MANPATH:$HOME/pkg/man"

export PATH SBT_HOME JAVA_HOME MANPATH


if [ -e "$HOME"/.kshrc.alias ]
then
    . "$HOME"/.kshrc.alias
fi
