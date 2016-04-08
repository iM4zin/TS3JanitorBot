#!/usr/bin/perl
package ts3bot;
use warnings; use strict;
use Sys::Syslog qw(:DEFAULT setlogsock);
use File::Basename;
use IO::Socket;
use DBI;
use Data::Dumper;
use Math::Round;
use ts3bot::Commands;
use ts3bot::Response;

my $config=do("conf.pl");

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
&loadbaddata;

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
&ts("serverinfo");
&ts("servernotifyregister event=textprivate");
#&ts("servernotifyregister event=server");
&ts("servernotifyregister event=channel id=0");

&ts("servernotifyregister event=server");
&ts("servernotifyregister event=textserver");
&ts("servernotifyregister event=textchannel");
&ts("servernotifyregister event=textprivate");

&ts("clientupdate client_nickname=" . escape($botname));
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
		
			if(/virtualserver_clientsonline=(\d+)/) { ts3bot::Response::resp_virtualserver_clientsonline(); next;}
			if(/^notifycliententerview/) { ts3bot::Response::resp_notifycliententerview(); next;}
			if(/^notifyclientleftview/) { ts3bot::Response::resp_notifyclientleftview(); next;}
			if(/^notifyclientmoved/) { ts3bot::Response::resp_notifyclientmoved(); next;}
			if(/^notifychannelcreated/) { ts3bot::Response::resp_notifychannelcreated(); next;}
			if(/^notifychanneldeleted/) { ts3bot::Response::resp_notifychanneldeleted(); next;}
			if(/^notifychanneledited/) { ts3bot::Response::resp_notifychanneledited(); next;}
			if(/^notifychannelpasswordchanged/) { ts3bot::Response::resp_notifychannelpasswordchanged(); next;}
			if(/^notifychanneldescriptionchanged/) { ts3bot::Response::resp_notifychanneldescriptionchanged(); next;}

			if(/^notifytextmessage/) {
				shift;
				my %tmp = &ts3bot::Response::parse;

				# Check is command
				if(!$tmp{'msg'} =~ /^\!/) {
					next;
				}

				&info("Got command from $tmp{invokername}: $tmp{msg}");

				# Check is op
				if(!checkop( $tmp{'invokeruid'} )) {
					next;
				}

				if($tmp{msg} =~ /\!dump /) { ts3bot::Commands::cmd_dump(%tmp); next; }
				if($tmp{msg} =~ /\!test /) { ts3bot::Commands::cmd_test(%tmp); next; }
				if($tmp{msg} =~ /\!testbad (.*)/) { ts3bot::Commands::cmd_testbad(%tmp); next; }
				next;
			}

			if($wait_response) {
				if($last_cmd =~ /^clientlist/) {
					my @clientlines	;
					print "recieving clientlist\n";
					push @clientlines, split(/\|/, $_);
					#print Dumper(\@clientlines);
					foreach(@clientlines) {
						chomp;
						my %tmp = &ts3bot::Response::parse;
						$tmp{'time'} = time;
						#print Dumper(\%tmp);
						if(!defined($tmp{'client_type'}) or $tmp{'client_type'} =~ /^0$/) {
							&info("Already connected client: $tmp{client_nickname}");
							$clients[$tmp{clid}] = \%tmp;
						}
						else {
							&info("Already connected wrong type client: $tmp{client_nickname}");
						}
					}
				}
				else {
					print "Unknow response\n";
				}
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



die "end";

