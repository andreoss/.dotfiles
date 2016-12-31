#!/bin/sh

__ts() {
	date "+%x-%X"
}
__log() {
	__level="$1"
	shift
	echo >&2 "$(__ts) ${__level}: $*"
}

__panic() {
	__log ERROR "$*"
	exit 1
}

__check_path() {
	type "$1" >/dev/null || __panic "no '$1' in PATH "
}

SOURCES_ROOT="$HOME/src"
GIT_REPO="https://github.com/emacs-mirror/emacs"
PREFIX="$HOME/.local"

AUTOCONF_VERSION=2.65
CC=egcc
MAKEINFO="/usr/local/bin/gmakeinfo"

export AUTOCONF_VERSION MAKEINFO CC

if [ ! -d "$SOURCES_ROOT" ]; then
	mkdir -p "$SOURCES_ROOT"
fi

cd "$SOURCES_ROOT"

if [ ! -d emacs ]; then
	__log INFO Cloning
	git clone --quiet --jobs=5 --depth=1 "$GIT_REPO"
fi

cd emacs

git pull --quiet --depth=1 --jobs=5

__log INFO Clean
gmake clean

__log INFO Autogen
./autogen.sh

__log INFO Autogen
./configure \
	--prefix="${PREFIX:?no prefix}" \
	--with-x-toolkit=lucid \
	--with-sqlite3 \
	--with-imagemagick \
	--without-harfbuzz \
	--without-cairo \
	--without-libotf \
	--without-toolkit-scroll-bars \
	--enable-link-time-optimization

gmake bootstrap
gmake
gmake install
