OS != uname

all: system dotfiles cron

cron:
	crontab ${HOME}/.crontab


dotfiles:
	ln -f -s  ${HOME}/.dotfiles/.Xresources  ${HOME}/.Xdefaults
	ln -f -s  ${HOME}/.dotfiles/.kshrc       ${HOME}/.kshrc
	ln -f -s  ${HOME}/.dotfiles/.kshrc.alias ${HOME}/.kshrc.alias
	ln -f -s  ${HOME}/.dotfiles/.profile     ${HOME}/.profile
	ln -f -s  ${HOME}/.dotfiles/.xsession    ${HOME}/.xsession
	ln -f -s  ${HOME}/.dotfiles/.xbindkeysrc ${HOME}/.xbindkeysrc
	ln -f -s  ${HOME}/.dotfiles/.crontab     ${HOME}/.crontab
	ln -f -s  ${HOME}/.dotfiles/.screenrc    ${HOME}/.screenrc
	ln -f -s  ${HOME}/.dotfiles/.inputrc     ${HOME}/.inputrc

	mkdir -p  ${HOME}/.icewm/
	mkdir -p  ${HOME}/.config/gtk-3.0/

	ln -f -s  ${HOME}/.dotfiles/.icewm/preferences ${HOME}/.icewm/

	ln -f -s  ${HOME}/.dotfiles/gtk-3.0.ini ${HOME}/.config/gtk-3.0/settings.ini

	git config --global include.path 	${HOME}/.dotfiles/gitaliases

	mkdir -p  ${HOME}/.config/
	mkdir -p  ${HOME}/.config/sxhkd/

.if "${OS}" == "OpenBSD"
system:
	doas pkg_add -l pkgs-${OS}.txt
.elif "${OS}" == "FreeBSD"
system:
	xargs sudo pkg install -y < pkgs-${OS}.txt
.else
system:
	@echo "Unsupported: ${OS}"
	@exit 1
.endif
