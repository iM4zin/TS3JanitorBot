{
	botname        => 'Janitor bot',

	ops => [
		'Z0vv8ay/UDZ4GbVNwKPDbfq57TU=',	# Uuid owner name here
		'RCcDagMhe34gY03rnltsv0oNAG0=',	# or any other comment
		'another_unique_id'		# 
	],

	serveraddress  => '127.0.0.1',
	serverport     => '10011',
	serverid       => '1',
	serveruser     => 'ts3_username',
	serverpass     => 'ts3_password',

	db_host        => 'localhost',
	db_username    => 'ts3db_username_here',
	db_password    => 'ts3db_password_here',
	db_database    => 'ts3db_database_here',
	db_infotable   => 'ts3bot_info',
	db_kicktable   => 'ts3bot_kick',

	pidfile        => './ts3bot.pid',
}
