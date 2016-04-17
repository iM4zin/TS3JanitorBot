package ts3bot::Notify;
use warnings; use strict;
use Data::Dumper;
use Math::Round;
use DBI;

sub virtualserver_clientsonline {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	
	if(/virtualserver_clientsonline=(\d+)/) {
		&ts3bot::info("Users online: " . ($1 - 1) . "\n");
	}
}


sub notifycliententerview {
	shift;
	my %c = &ts3bot::parse;
	&ts3bot::clientconnected(%c);

	my $msg = ts3bot::checkbadnick($c{client_nickname});
	if($msg) {
		ts3bot::notifyop($msg);
	}
}

sub notifyclientleftview {
	shift;
	my %c = &ts3bot::parse;
	&ts3bot::clientdisconnected(%c);
}

sub notifyclientmoved {
	shift;
	my %c = &ts3bot::parse;
	return if(defined $ts3bot::clients[$c{clid}]{ctid} and $ts3bot::clients[$c{clid}]{ctid} == $c{ctid});

	if($ts3bot::clients[$c{clid}]{client_nickname}) {
		if($c{invokername}) {
			&ts3bot::info("Client " . $ts3bot::clients[$c{clid}]{client_nickname} . "(" . $c{clid} . ") moved to channel id " . $c{ctid} . " by " . $c{invokername});
		}
		else {
			&ts3bot::info("Client " . $ts3bot::clients[$c{clid}]{client_nickname} . "(" . $c{clid} . ") moved to channel id " . $c{ctid});
		}
	} else {
		if($c{invokername}) {
			&ts3bot::info("Client (" . $c{clid} . ") moved to channel id " . $c{ctid} . " by " . $c{invokername});
		}
		else {
			&ts3bot::info("Client (" . $c{clid} . ") moved to channel id " . $c{ctid});
		}

	}
	$ts3bot::clients[$c{clid}]{ctid} = $c{ctid};
	#print Dumper(\%c);
}
######################################################################
sub notifychannelcreated {
	shift;
	my %tmp = &ts3bot::parse;

	&ts3bot::info("Channel " . $tmp{channel_name} . " (" . $tmp{cid} . ") created by " . $tmp{invokername} . "(" . $tmp{invokerid} . ")");
	#print Dumper(\%tmp);
	my $msg =ts3bot::checkbadch($tmp{channel_name});
	if($msg) {
		notifyop("Channel " . $tmp{channel_name} . " (" . $tmp{cid} . ") created by " . $tmp{invokername} . "(" . $tmp{invokerid} . ")");
		notifyop($msg);
	}
}

sub notifychanneldeleted {
	shift;
	my %tmp = &ts3bot::parse;

	&ts3bot::info("Channel (" . $tmp{cid} . ") deleted by " . $tmp{invokername} . ($tmp{invokerid}? "(".$tmp{invokerid}.")" : ""));
	delete $ts3bot::channels[$tmp{cid}];
}

sub notifychanneledited {
	shift;
	my %tmp = &ts3bot::parse;

	&ts3bot::info("Channel " . $tmp{channel_name} . " (" . $tmp{cid} . ") edited by " . $tmp{invokername} . "(" . $tmp{invokerid} . ")");
	print Dumper(\%tmp);
}

sub notifychannelpasswordchanged {
	shift;
	my %tmp = &ts3bot::parse;

	&ts3bot::info("Channel (" . $tmp{cid} . ") password changed");
}

sub notifychanneldescriptionchanged {
	shift;
	my %tmp = &ts3bot::parse;

	&ts3bot::info("Channel (" . $tmp{cid} . ") password changed");
}


sub notifytextmessage {
	shift;
	my %tmp = &ts3bot::parse;

	# Checking is sender someone else than bot itself
	return if($tmp{invokerid} == $ts3bot::my_client_id);

	# Check is command
	return if(!$tmp{'msg'} =~ /^\!/);

	&ts3bot::info("Got message from $tmp{invokername}: $tmp{msg}");

	# Check is op
	if(!ts3bot::checkop( $tmp{'invokeruid'} )) {
		return;
	}

	if($tmp{msg} =~ /\!dump/) { ts3bot::Commands::cmd_dump(%tmp); return; }
	if($tmp{msg} =~ /\!testbad (.*)/) { ts3bot::Commands::cmd_testbad(%tmp); return; }
	if($tmp{msg} =~ /\!test/) { ts3bot::Commands::cmd_test(%tmp); return; }
	if($tmp{msg} =~ /\!stopbot/) { ts3bot::Commands::cmd_stopbot(%tmp); return; }
}
1;
