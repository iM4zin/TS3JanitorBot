#!/usr/bin/perl
package ts3bot;
use warnings; use strict;
use Sys::Syslog qw(:DEFAULT setlogsock);
use Digest::MD5 qw(md5 md5_hex md5_base64);
use File::Basename;
use IO::Socket;
use DBI;
use Data::Dumper;
use Math::Round;
use ts3bot::Notify;
use ts3bot::Commands;

our $config=do("conf.pl");

die "Error parsing config file: $@" if $@;
die "Error reading config file: $!" unless defined $config;

#syslog facility is local2 by default
openlog(basename($0), "pid", "local2");

if (-e $config->{pidfile}) {
        open PIDFILE,$config->{pidfile};
        my $p=<PIDFILE>;
        chomp $p;
        close PIDFILE;

	my $exists = kill 0, $p;
	die("Process is already running with pid $p\n") if($exists);
        &info("Removing old pidfile, pid was $p\n");
}
open PIDFILE,">$config->{pidfile}" or &fatal("Cannot write pidfile $config->{pidfile}: $!\n");
print PIDFILE "$$\n";
close PIDFILE;

&info("starting: $config->{botname}\n");

our @clients;
our @channels;
our @badch;
our @badnick;
our @cmdqueue;
our $wait_response = 0;
our $last_cmd;
our $my_client_id;
&loadbaddata;

our $EXIT = 0;

$SIG{INT} = sub{ $EXIT = 1 };

# Connect to the database.
our $dbh = DBI->connect("DBI:mysql:database=" . $config->{db_database} . ";host=" . $config->{db_host} . "",
	$config->{db_username}, $config->{db_password},
	{'RaiseError' => 1});

my $sock = new IO::Socket::INET (
	PeerAddr => $config->{serveraddress},
	PeerPort => $config->{serverport},
	Proto => 'tcp',
	Blocking => 0,
); 


&stopbot("Could not create socket: $!") unless $sock;

$dbh->do('set names utf8');

my $botname = $config->{botname};

&ts("use sid=" .$config->{serverid});
&ts("login client_login_name=" .$config->{serveruser}. " client_login_password=" .$config->{serverpass});
&ts("clientupdate client_nickname=" . escape($botname));
&ts("serverinfo");
&ts("servernotifyregister event=textprivate");
#&ts("servernotifyregister event=server");
&ts("servernotifyregister event=channel id=0");

&ts("servernotifyregister event=server");
&ts("servernotifyregister event=textserver");
&ts("servernotifyregister event=textchannel");
&ts("servernotifyregister event=textprivate");

&ts("whoami");
&ts("clientlist -uid");

my $pingtime = time;
while (1) {
	my $socket_data;
	if(!$sock) {
		print "No connection\n";
	}
	while ($socket_data = <$sock>) {
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		my @lines = ();
		push @lines, split(/\r/, $socket_data);

		foreach(@lines) {
			chomp;
			if(!/\S/ or /^Welcome to the TeamSpeak 3/ or /^TS3$/) {
				next;
			}

			if(/^error id=(\d+)/) {
				if($1 !~ /^0$/) {
					&info("error ". $1 ." \n");
					close $sock;
				}
				else {
					$wait_response = 0;
				}
				next;
			}

			if(/virtualserver_clientsonline=(\d+)/) { ts3bot::Notify::virtualserver_clientsonline(); next;}
			if(/^notifycliententerview/)            { ts3bot::Notify::notifycliententerview(); next;}
			if(/^notifyclientleftview/)             { ts3bot::Notify::notifyclientleftview(); next;}
			if(/^notifyclientmoved/)                { ts3bot::Notify::notifyclientmoved(); next;}
			if(/^notifychannelcreated/)             { ts3bot::Notify::notifychannelcreated(); next;}
			if(/^notifychanneldeleted/)             { ts3bot::Notify::notifychanneldeleted(); next;}
			if(/^notifychanneledited/)              { ts3bot::Notify::notifychanneledited(); next;}
			if(/^notifychannelpasswordchanged/)     { ts3bot::Notify::notifychannelpasswordchanged(); next;}
			if(/^notifychanneldescriptionchanged/)  { ts3bot::Notify::notifychanneldescriptionchanged(); next;}
			if(/^notifytextmessage/)                { ts3bot::Notify::notifytextmessage(); next;}

			if($last_cmd =~ /^clientlist/ and $wait_response) {
				my @clientlines	;
				print "recieving clientlist\n";
				push @clientlines, split(/\|/, $_);
				foreach(@clientlines) {
					chomp;
					my %c = &ts3bot::parse;
					$c{oldconnectinon} = 1;
					&clientconnected(%c);
				}
				#print Dumper(@clients);
			}
			elsif($last_cmd =~ /^whoami/ and $wait_response) {
				my %tmp = &ts3bot::parse;
				$my_client_id = $tmp{client_id};
				
			}
			else {
				print "Unknow command: " . $_."\n";
			}
		
				
		}
	}

	if(scalar(grep {defined $_} @cmdqueue) > 0 && $wait_response == 0) {
		my $msg = shift @cmdqueue;
		$wait_response=1;
		$last_cmd = $msg;
		print $sock $msg . "\n";
		print STDERR scalar localtime() . " Sent: $msg\n";
	}

	if($pingtime < time - 60) {
		$pingtime = time;
		&ts("serverinfo");
	}

	if($EXIT) {
	        foreach my $c (@ts3bot::clients) {
	                if($c->{clid}) {
	                        my %tmp = %{$c};
	                        $tmp{"reasonid"} = 0;
	                        &ts3bot::clientdisconnected(%tmp);
	                }
	        }
		warn "Graceful exit!\n";
		exit;
	}

	sleep 0.2;
}



sub escape {
	$_=shift;
	return if(!$_);
	s/\\/\\\\/g;
	s/\//\\\//g;
	s/\ /\\s/g;
	s/\|/\\p/g;
	s/\a/\\a/g;
#	s/\b/\\b/g;
	s/\f/\\f/g;
	s/\n/\\n/g;
	s/\r/\\r/g;
	s/\t/\\t/g;
#	s/\v/\\v/g;
	return $_;
}

sub unescape {
	$_=shift;
	return if(!$_);
	s/\\\//\//g;
	s/\\s/\ /g;
	s/\\p/\|/g;
	s/\\a/\a/g;
#	s/\\b/\b/g;
	s/\\f/\f/g;
	s/\\n/\n/g;
	s/\\r/\r/g;
	s/\\t/\t/g;
#	s/\\v/\v/g;
	s/\\\\/\\/g;
	return $_;
}
sub info {
	my $msg = shift;
	chomp $msg;
	syslog('LOG_INFO', $msg);
	print STDERR scalar localtime() . " $msg\n";
}

sub fatal {
	my $msg = shift;
	chomp $msg;
	syslog('LOG_ERR', $msg);
	close $sock;
	$dbh->disconnect();
	die(scalar localtime() . " " . $msg);
}

sub ts {
	my $msg = shift;
	chomp $msg;
	push(@cmdqueue, $msg);
}

sub stopbot {
	my $msg = shift;
	chomp $msg;
	print STDERR scalar localtime() . " BOT STOPPED: $msg\n";
	$dbh->disconnect();
	close $sock;
	die;
}

sub loadbaddata {
	@badch = do {
	    open my $fh, "<", "badchannel.txt"
	        or die "could not open badchannel.txt: $!";
	    <$fh>;
	};
	for (@badch) { s/\r[\n]*//gm; }
	@badch = grep { $_ ne '' } @badch;
	@badch = grep { $_ ne /^\#/ } @badch;

	@badnick = do {
	    open my $fh, "<", "badnick.txt"
	        or die "could not open badnick.txt: $!";
	    <$fh>;
	};
	for (@badnick) { s/\r[\n]*//gm; }
	@badnick = grep { $_ ne '' } @badnick;
	@badnick = grep { $_ ne /^\#/ } @badnick;
}

sub checkop {
	my $uid = shift;
	foreach my $o (@{$config->{ops}}) {
		#print "checkop: $uid\n$o\n\n";
		if($uid eq $o) {
			return 1;
			next;
		}
	}
}

sub notifyop {
	my $msg = shift;
	&info("notifyop: $msg\n");
	foreach my $c (@clients) {
		if($c->{clid}) {
			if(checkop($c->{client_unique_identifier})) {
				&ts("sendtextmessage targetmode=1 target=$c->{clid} msg=" . escape($msg));
			}
		}
	}
}
sub checkbadch {
	my $i = shift;
	for (@badch) {
		if ($i =~ /$_/i) { return "\"$i\" is in patterns (matches $_)"; }
	}
}

sub checkbadnick {
	my $i = shift;
	for (@badnick) {
		if ($i =~ /$_/i) { return "\"$i\" is in patterns (matches $_)"; }
	}
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


sub clientconnected {
	my (%c) = @_;

	$c{'time'} = time;
	$clients[$c{clid}] = \%c;

	if(!defined($c{'client_type'}) or $c{'client_type'} =~ /^0$/) {
		if(!$c{oldconnectinon}) {
			&ts3bot::info("Client " .$c{client_nickname}. "(" . $c{clid} . ") connected");
			my $sql = "INSERT INTO `".$config->{db_infotable}."` (uuid, nickname, type, hash, created) VALUES (?, ?, 'TeamSpeak3', ?, NOW()) ON DUPLICATE KEY UPDATE nickname=?, onlinecount=onlinecount+1;";
			my $sh = $ts3bot::dbh->prepare( $sql ) or die "huh?" . $ts3bot::dbh->errstr;
			$sh->execute(
				$ts3bot::clients[$c{clid}]{client_unique_identifier},
				$ts3bot::clients[$c{clid}]{client_nickname},
				md5_hex($ts3bot::clients[$c{clid}]{client_unique_identifier}.$ts3bot::clients[$c{clid}]{client_nickname}.time),
				$ts3bot::clients[$c{clid}]{client_nickname}
			) or die "huh?" . $ts3bot::dbh->errstr;
			$sh->finish;
		}
		else {
			&ts3bot::info("Old connection: $c{client_nickname}");
			my $sql = "INSERT INTO `".$config->{db_infotable}."` (uuid, nickname, type, hash, created) VALUES (?, ?, 'TeamSpeak3', ?, NOW()) ON DUPLICATE KEY UPDATE nickname=?;";
			my $sh = $ts3bot::dbh->prepare( $sql ) or die "huh?" . $ts3bot::dbh->errstr;
			$sh->execute(
				$ts3bot::clients[$c{clid}]{client_unique_identifier},
				$ts3bot::clients[$c{clid}]{client_nickname},
				md5_hex($ts3bot::clients[$c{clid}]{client_unique_identifier}.$ts3bot::clients[$c{clid}]{client_nickname}.time),
				$ts3bot::clients[$c{clid}]{client_nickname}
			) or die "huh?" . $ts3bot::dbh->errstr;
			$sh->finish;
		}
	}
	else {
		if(!$c{oldconnectinon}) {
			&ts3bot::info("Something " .$c{client_nickname}. "(" . $c{clid} . ") connected");
		}
		else {
			&ts3bot::info("Old connection, not client: $c{client_nickname}");
		}
	}

	

	
}

sub clientdisconnected {
	my (%c) = @_;

	return if(!$ts3bot::clients[$c{clid}]);
	my $onlinetime = time - $ts3bot::clients[$c{clid}]{'time'};

	if($c{reasonid} != 5) {
		if(!$clients[$c{clid}]{'client_type'} =~ /^0$/) {
			&ts3bot::info("Client " . $clients[$c{clid}]{client_nickname} . "(" . $c{clid} . ") disconnected.");
		}
		else {
			my $sql = "UPDATE `".$config->{db_infotable}."` SET `onlinetime` = `onlinetime` + ? WHERE `uuid` = ?;";
			my $sh = $ts3bot::dbh->prepare( $sql ) or die "huh?" . $ts3bot::dbh->errstr;
			$sh->execute(
				$onlinetime,
				$ts3bot::clients[$c{clid}]{client_unique_identifier},
			) or die "huh?" . $ts3bot::dbh->errstr;
			$sh->finish;

			&ts3bot::info("Client " . $clients[$c{clid}]{client_nickname} . "(" . $c{clid} . ") disconnected. Online time " . (time - $ts3bot::clients[$c{clid}]{'time'}));
		}
	}
	else {
		my $sql = "INSERT INTO `".$config->{db_kicktable}."` (uuid, nickname, onlinetime, reasonid, reasonmsg) VALUES (?, ?, ?, ?, ?);";
		my $sh = $ts3bot::dbh->prepare( $sql ) or die "huh?" . $ts3bot::dbh->errstr;
		$sh->execute(
			$ts3bot::clients[$c{clid}]{client_unique_identifier},
			$ts3bot::clients[$c{clid}]{client_nickname},
			$onlinetime,
			$c{reasonid},
			$c{reasonmsg}
		) or die "huh?" . $ts3bot::dbh->errstr;
		$sh->finish;
		&ts3bot::info("Client " . $clients[$c{clid}]{client_nickname} . "(" . $c{clid} . ") kicked.");
	}

	delete $ts3bot::clients[$c{clid}];
}
die "end";

