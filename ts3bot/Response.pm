package ts3bot::Response;
use warnings; use strict;
use Data::Dumper;
use Math::Round;
use DBI;

my $clientcounterhour = -1;

sub resp_virtualserver_clientsonline {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	
	if(/virtualserver_clientsonline=(\d+)/) {
		&ts3bot::info("Users online: " . ($1 - 1) . "\n");
		if($hour != $clientcounterhour) {
			my $sql = "INSERT INTO onlineclients (clients) VALUES (?);";
			my $sh = $ts3bot::dbh->prepare( $sql ) or die "huh?" . $ts3bot::dbh->errstr;
			$sh->execute(
				($1 - 1)
			) or die "Huh?" . $ts3bot::dbh->errstr;
			$sh->finish;
			$clientcounterhour = $hour;
		}
	}
}

sub resp_notifycliententerview {
	shift;
	my %tmp = &parse;
	$tmp{'time'} = time;
	$ts3bot::clients[$tmp{clid}] = \%tmp;

	&ts3bot::info("Client " .$tmp{client_nickname}. "(" . $tmp{clid} . ") connected");
#	print Dumper(\%tmp);
	my $msg = ts3bot::checkbadnick($tmp{client_nickname});
	if($msg) {
		ts3bot::notifyop($msg);
	}
}

sub resp_notifyclientleftview {
	shift;
	my %tmp = &parse;
	return if(!$ts3bot::clients[$tmp{clid}]);

	if(! $ts3bot::clients[$tmp{clid}]{'client_type'} =~ /^0$/) {
		&ts3bot::info("Client (" . $tmp{clid} . ") disconnected. (unknow client type)");
	}
	elsif(
	$ts3bot::clients[$tmp{clid}]{client_database_id} &&
	$ts3bot::clients[$tmp{clid}]{client_unique_identifier} &&
	$ts3bot::clients[$tmp{clid}]{client_nickname} &&
	$ts3bot::clients[$tmp{clid}]{client_nickname}) {

		my $onlinetime = time - $ts3bot::clients[$tmp{clid}]{'time'};
		my $sql = "INSERT INTO onlinetime (client_id, client_unique_identifier, nickname, onlinetime) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE onlinetime=onlinetime+?, nickname=?, connectioncount=connectioncount+1;";
		my $sh = $ts3bot::dbh->prepare( $sql ) or die "huh?" . $ts3bot::dbh->errstr;
		$sh->execute(
			$ts3bot::clients[$tmp{clid}]{client_database_id},
			$ts3bot::clients[$tmp{clid}]{client_unique_identifier},
			$ts3bot::clients[$tmp{clid}]{client_nickname},
			$onlinetime,
			$onlinetime,
			$ts3bot::clients[$tmp{clid}]{client_nickname}
		) or die "Huh?" . $ts3bot::dbh->errstr;
		$sh->finish;

		if($tmp{reasonid} == 5) {
			&ts3bot::info("Client " . $ts3bot::clients[$tmp{clid}]{client_nickname} . "(" . $tmp{clid} . ") kicked. Online time " . (time - $ts3bot::clients[$tmp{clid}]{'time'}));

			my $onlinetime = time - $ts3bot::clients[$tmp{clid}]{'time'};
			my $sql = "INSERT INTO kicks (client_id, client_unique_identifier, nickname, onlinetime, reasonid, reasonmsg) VALUES (?, ?, ?, ?, ?, ?);";
			my $sh = $ts3bot::dbh->prepare( $sql ) or die "huh?" . $ts3bot::dbh->errstr;
			$sh->execute(
				$ts3bot::clients[$tmp{clid}]{client_database_id},
				$ts3bot::clients[$tmp{clid}]{client_unique_identifier},
				$ts3bot::clients[$tmp{clid}]{client_nickname},
				$onlinetime,
				$tmp{reasonid},
				$tmp{reasonmsg},
			) or die "Huh?" . $ts3bot::dbh->errstr;
			$sh->finish;
		}
		else {
			&ts3bot::info("Client " . $ts3bot::clients[$tmp{clid}]{client_nickname} . "(" . $tmp{clid} . ") disconnected. Online time " . (time - $ts3bot::clients[$tmp{clid}]{'time'}));
		}



	} else {
		&ts3bot::info("Client (" . $tmp{clid} . ") disconnected.");
	}
	delete $ts3bot::clients[$tmp{clid}];
}

sub resp_notifyclientmoved {
	shift;
	my %tmp = &ts3bot::Response::parse;
	return if(defined $ts3bot::clients[$tmp{clid}]{ctid} and $ts3bot::clients[$tmp{clid}]{ctid} == $tmp{ctid});

	if($ts3bot::clients[$tmp{clid}]{client_nickname}) {
		if($tmp{invokername}) {
			&ts3bot::info("Client " . $ts3bot::clients[$tmp{clid}]{client_nickname} . "(" . $tmp{clid} . ") moved to channel id " . $tmp{ctid} . " by " . $tmp{invokername});
		}
		else {
			&ts3bot::info("Client " . $ts3bot::clients[$tmp{clid}]{client_nickname} . "(" . $tmp{clid} . ") moved to channel id " . $tmp{ctid});
		}
	} else {
		if($tmp{invokername}) {
			&ts3bot::info("Client (" . $tmp{clid} . ") moved to channel id " . $tmp{ctid} . " by " . $tmp{invokername});
		}
		else {
			&ts3bot::info("Client (" . $tmp{clid} . ") moved to channel id " . $tmp{ctid});
		}

	}
	$ts3bot::clients[$tmp{clid}]{ctid} = $tmp{ctid};
	#print Dumper(\%tmp);
}
######################################################################
sub resp_notifychannelcreated {
	shift;
	my %tmp = &ts3bot::Response::parse;

	&ts3bot::info("Channel " . $tmp{channel_name} . " (" . $tmp{cid} . ") created by " . $tmp{invokername} . "(" . $tmp{invokerid} . ")");
	#print Dumper(\%tmp);
	my $msg =ts3bot::checkbadch($tmp{channel_name});
	if($msg) {
		notifyop("Channel " . $tmp{channel_name} . " (" . $tmp{cid} . ") created by " . $tmp{invokername} . "(" . $tmp{invokerid} . ")");
		notifyop($msg);
	}
}

sub resp_notifychanneldeleted {
	shift;
	my %tmp = &ts3bot::Response::parse;

	&ts3bot::info("Channel (" . $tmp{cid} . ") deleted by " . $tmp{invokername} . ($tmp{invokerid}? "(".$tmp{invokerid}.")" : ""));
	delete $ts3bot::channels[$tmp{cid}];
}

sub resp_notifychanneledited {
	shift;
	my %tmp = &ts3bot::Response::parse;

	&ts3bot::info("Channel " . $tmp{channel_name} . " (" . $tmp{cid} . ") edited by " . $tmp{invokername} . "(" . $tmp{invokerid} . ")");
	print Dumper(\%tmp);
}

sub resp_notifychannelpasswordchanged {
	shift;
	my %tmp = &ts3bot::Response::parse;

	&ts3bot::info("Channel (" . $tmp{cid} . ") password changed");
}

sub resp_notifychanneldescriptionchanged {
	shift;
	my %tmp = &ts3bot::Response::parse;

	&ts3bot::info("Channel (" . $tmp{cid} . ") password changed");
}









sub parse {
	my @datas = split / /, $_;
	my %tmp;
	while(@datas) {
		my ($key, $value) = split /\s*=\s*/, shift(@datas), 2;
		$tmp{$key} = ts3bot::unescape($value);
	}
	return %tmp;
}
1;