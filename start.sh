#!/bin/sh

if [ -f $FILE ];
then
   perl ts3bot.pl
else
   echo "Config file dosent not exists!. Copy example_conf.pl to conf.pl, edit it and try again."
fi
