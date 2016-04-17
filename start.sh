#!/bin/sh

if [ ! -f badchannel.txt ] ; then cp example_badchannel.txt badchannel.txt; fi;
if [ ! -f badnick.txt ]; then cp example_badnick.txt badnick.txt; fi;
if [ -f conf.pl ];
then
	git pull
	perl ts3bot.pl
	rc=$?; if [[ $rc != 255 ]]; then echo 'you may have to do "cpan Math::Round module"'; fi
else
	echo 'do "cp example_conf.pl conf.pl && nano conf.pl"'
fi

