cron:
	crontab ${HOME}/.crontab


all:
	ln -f -s  ${HOME}/.dotfiles/.Xdefaults ${HOME}/.Xdefaults
	ln -f -s  ${HOME}/.dotfiles/.kshrc     ${HOME}/.kshrc
	ln -f -s  ${HOME}/.dotfiles/.xsession  ${HOME}/.xsession
	ln -f -s  ${HOME}/.dotfiles/.crontab   ${HOME}/.crontab
	ln -f -s  ${HOME}/.dotfiles/.screenrc  ${HOME}/.screenrc
	mkdir -p  ${HOME}/.config/
	mkdir -p  ${HOME}/.config/sxhkd/

	sudo cp ${HOME}/.dotfiles/rc.conf      /etc/rc.conf.local
