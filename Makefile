OS != uname

ND = mkdir -p
LN = ln -f -s

all: system local-bin dotfiles cron

cron:
	crontab ${HOME}/.crontab

local-bin:
	$(ND) ${HOME}/.local/bin
	$(LN) ${HOME}/.dotfiles/bin/chrome ${HOME}/.local/bin/chrome
	$(LN) ${HOME}/.dotfiles/bin/viper  ${HOME}/.local/bin/viper

dotfiles:

	$(LN) ${HOME}/.dotfiles/.crontab     ${HOME}/.crontab
	$(LN) ${HOME}/.dotfiles/.inputrc     ${HOME}/.inputrc
	$(LN) ${HOME}/.dotfiles/.kshrc       ${HOME}/.kshrc
	$(LN) ${HOME}/.dotfiles/.kshrc.alias ${HOME}/.kshrc.alias
	$(LN) ${HOME}/.dotfiles/.profile     ${HOME}/.profile
	$(LN) ${HOME}/.dotfiles/.screenrc    ${HOME}/.screenrc
	$(LN) ${HOME}/.dotfiles/.xbindkeysrc ${HOME}/.xbindkeysrc
	$(LN) ${HOME}/.dotfiles/.Xresources  ${HOME}/.Xdefaults
	$(LN) ${HOME}/.dotfiles/.xsession    ${HOME}/.xsession

	$(ND) ${HOME}/.config/dunst/
	$(ND) ${HOME}/.config/gtk-3.0/
	$(ND) ${HOME}/.config/sxhkd/
	$(ND) ${HOME}/.icewm/

	$(LN) ${HOME}/.dotfiles/.icewm/preferences ${HOME}/.icewm/
	$(LN) ${HOME}/.dotfiles/.dunstrc           ${HOME}/.config/dunst/dunstrc
	$(LN) ${HOME}/.dotfiles/gtk-3.0.ini        ${HOME}/.config/gtk-3.0/settings.ini

	$(LN)  ${HOME}/.dotfiles/sxhkdrc	   ${HOME}/.config/sxhkd/sxhkdrc
	pkill -USR1 sxhkd || echo "Not running"

	git config --global include.path 	${HOME}/.dotfiles/gitaliases

system:
.if "${OS}" == "OpenBSD"
	doas pkg_add -l pkgs-${OS}.txt
.elif "${OS}" == "FreeBSD"
	xargs doas pkg install -y < pkgs-${OS}.txt
.elif "${OS}" == "Linux"
	doas rm -f              /etc/motd
	doas ln -f -s /dev/null /etc/motd
	xargs doas apk add < pkgs-${OS}.txt
.endif

gsettings:
	gsettings set org.gnome.desktop.input-sources sources     "[('xkb', 'us'), ('xkb', 'ru')]"
	gsettings set org.gnome.desktop.input-sources xkb-options "['caps:ctrl_modifier']"
