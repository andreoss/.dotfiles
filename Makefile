cron:
	crontab ${HOME}/.crontab


all:
	ln -f -s  ${HOME}/.dotfiles/.Xresources ${HOME}/.Xdefaults
	ln -f -s  ${HOME}/.dotfiles/.kshrc     ${HOME}/.kshrc
	ln -f -s  ${HOME}/.dotfiles/.profile   ${HOME}/.profile
	ln -f -s  ${HOME}/.dotfiles/.xsession  ${HOME}/.xsession
	ln -f -s  ${HOME}/.dotfiles/.crontab   ${HOME}/.crontab
	ln -f -s  ${HOME}/.dotfiles/.screenrc  ${HOME}/.screenrc
	ln -f -s  ${HOME}/.dotfiles/.screenrc  ${HOME}/.screenrc

	mkdir -p  ${HOME}/.icewm/
	mkdir -p  ${HOME}/.config/gtk-3.0/

	ln -f -s  ${HOME}/.dotfiles/.icewm/preferences ${HOME}/.icewm/

	ln -f -s  ${HOME}/.dotfiles/gtk-3.0.ini ${HOME}/.config/gtk-3.0/settings.ini

	mkdir -p  ${HOME}/.config/
	mkdir -p  ${HOME}/.config/sxhkd/
