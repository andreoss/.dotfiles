OS != uname

ND = mkdir -p
LN = ln -f -s

all: local-bin dotfiles cron system

cron:
	crontab ${HOME}/.crontab

local-bin:
	$(ND) ${HOME}/.local/bin
	$(LN) ${HOME}/.dotfiles/bin/wdate    ${HOME}/.local/bin/wdate
	$(LN) ${HOME}/.dotfiles/bin/chrome   ${HOME}/.local/bin/chrome
	$(LN) ${HOME}/.dotfiles/bin/et       ${HOME}/.local/bin/et
	$(LN) ${HOME}/.dotfiles/bin/jetbrains       ${HOME}/.local/bin/jetbrains
	$(LN) ${HOME}/.dotfiles/bin/signal-desktop  ${HOME}/.local/bin/signal-desktop
	$(LN) ${HOME}/.dotfiles/bin/tm       ${HOME}/.local/bin/tm
	$(LN) ${HOME}/.dotfiles/bin/viper    ${HOME}/.local/bin/viper
	$(LN) ${HOME}/.dotfiles/bin/x        ${HOME}/.local/bin/x
	$(LN) ${HOME}/.dotfiles/bin/wm       ${HOME}/.local/bin/wm

dotfiles:
	$(LN) ${HOME}/.dotfiles/.crontab     ${HOME}/.crontab
	$(LN) ${HOME}/.dotfiles/.inputrc     ${HOME}/.inputrc
	$(LN) ${HOME}/.dotfiles/.kshrc       ${HOME}/.kshrc
	$(LN) ${HOME}/.dotfiles/.zshrc       ${HOME}/.zshrc
	$(LN) ${HOME}/.dotfiles/.kshrc.alias ${HOME}/.kshrc.alias
	$(LN) ${HOME}/.dotfiles/.profile     ${HOME}/.profile
	$(LN) ${HOME}/.dotfiles/.screenrc    ${HOME}/.screenrc
	$(LN) ${HOME}/.dotfiles/.xbindkeysrc ${HOME}/.xbindkeysrc
	$(LN) ${HOME}/.dotfiles/.Xresources  ${HOME}/.Xdefaults
	$(LN) ${HOME}/.dotfiles/.xsession    ${HOME}/.xsession
	$(LN) ${HOME}/.dotfiles/.ideavimrc   ${HOME}/.ideavimrc
	$(LN) ${HOME}/.xsession              ${HOME}/.xinitrc

	$(ND) ${HOME}/.config/dunst/
	$(ND) ${HOME}/.config/gtk-3.0/
	$(ND) ${HOME}/.config/sxhkd/
	$(ND) ${HOME}/.icewm/

	$(LN) ${HOME}/.dotfiles/.icewm/preferences ${HOME}/.icewm/
	$(LN) ${HOME}/.dotfiles/.icewm/toolbar     ${HOME}/.icewm/
	$(LN) ${HOME}/.dotfiles/.dunstrc           ${HOME}/.config/dunst/dunstrc
	$(LN) ${HOME}/.dotfiles/gtk-3.0.ini        ${HOME}/.config/gtk-3.0/settings.ini
	$(LN) ${HOME}/.dotfiles/sxhkdrc	           ${HOME}/.config/sxhkd/sxhkdrc
	pkill -USR1 sxhkd || echo "Not running"

	git config --global include.path 	   ${HOME}/.dotfiles/gitaliases
	pkill -USR1 sxhkd ||:

	xrdb ~/.Xdefaults ||:
system:
	doas rm -f              /etc/motd
	doas ln -f -s /dev/null /etc/motd
.if "${OS}" == "OpenBSD"
	doas rcctl set sndiod flags -b24000
	doas rcctl restart sndiod
	doas sysctl  -f sysctl-${OS}.txt
	doas pkg_add -l pkgs-${OS}.txt
	doas syspatch
	doas fw_update
	echo 'machine gop 13' | doas tee /etc/boot.conf
.elif "${OS}" == "FreeBSD"
	xargs doas pkg install -y < pkgs-${OS}.txt
.elif "${OS}" == "Linux"
	xargs doas apk add < pkgs-${OS}.txt
.endif

gsettings:
	gsettings set org.gnome.desktop.input-sources sources     "[('xkb', 'us'), ('xkb', 'ru')]"
	gsettings set org.gnome.desktop.input-sources xkb-options "['caps:ctrl_modifier']"
