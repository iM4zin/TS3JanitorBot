#!/usr/bin/perl
use Sys::Syslog qw(:DEFAULT setlogsock);
use File::Basename;
use IO::Socket;
use DBI;
use Data::Dumper;
use warnings; use strict;
use Math::Round;


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

my @clients;
my @badch;
my @badnick;
my @cmdqueue;
my $wait_response = 0;
my $last_cmd;
&loadbaddata;

# Connect to the database.
my $dbh = DBI->connect("DBI:mysql:database=" . $config->{db_database} . ";host=" . $config->{db_host} . "",
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
my $clientcounterhour = -1;
my $pingtime = time;
while (1) {
	my $socket_data;
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
					print "ok\n";
					$wait_response = 0;
				}
				next;
			}
		

			if(/virtualserver_clientsonline=(\d+)/) {
				&info("Users online: " . ($1 - 1) . "\n");
				if($hour != $clientcounterhour) {
					my $sql = "INSERT INTO onlineclients (clients) VALUES (?);";
					my $sh = $dbh->prepare( $sql ) or die "huh?" . $dbh->errstr;
					$sh->execute(
						($1 - 1)
					) or die "Huh?" . $dbh->errstr;
					$sh->finish;
					$clientcounterhour = $hour;
				}
				next;
			}

			if(/^notifytextmessage/) {
				shift;
				my %tmp = &parse;
				&info("Got message from $tmp{invokername}: $tmp{msg}");
				if(!checkop( $tmp{'invokeruid'} )) {
					next;
				}

				if($tmp{msg} =~ /\!dump/) {
					my $count = 0;
					foreach my $c (@clients) {
						if($c->{clid}) {
							print $c->{clid} . " " . $c->{client_unique_identifier} . " " . $c->{client_nickname} ."\n";
							$count++;
							#print Dumper(\%c);
						}
					}
					print "Total: $count\n";
				}

				if($tmp{msg} =~ /\!test/) {
					# now retrieve data from the table.
					foreach my $c (@clients) {
						my $sth = $dbh->prepare("SELECT * FROM onlinetime WHERE client_unique_identifier LIKE ?;");
						$sth->execute(
							$c->{client_unique_identifier}
						);
						while (my $ref = $sth->fetchrow_hashref()) {
							my $t;
							if($ref->{'onlinetime'} < 60) {
								$t=$ref->{'onlinetime'}."s";
							}
							elsif($ref->{'onlinetime'} < 60*60) {
								$t=nearest(.01, $ref->{'onlinetime'}/60)."m";
							}
							elsif($ref->{'onlinetime'} < 60*60*24) {
								$t=nearest(.01, $ref->{'onlinetime'}/(60*60))."h";
							}
							else {
								$t=nearest(.01, $ref->{'onlinetime'}/(60*60*24))."d";
							}
							my $urlescape = $c->{client_nickname};
							$urlescape =~ s/ /%20/g;
							print "Nickname: " .$ref->{'nickname'}. ", time: " .$t. ", count: " .$ref->{'connectioncount'}. "\n";
							&ts("sendtextmessage targetmode=1 target=" . $tmp{invokerid} . " msg=" . escape("Nickname: [URL=client://".$c->{clid}."/".$c->{client_unique_identifier}."~".$urlescape."]".$c->{client_nickname}."[/URL], time: " .$t. ", count: " .$ref->{'connectioncount'}));
						}
						$sth->finish();
					}

				}

				if($tmp{msg} =~ /\!testbad (.*)/) {
					my $c =checkbadch($1);
					my $n =checkbadnick($1);
					if($c) { &ts("sendtextmessage targetmode=1 target=" . $tmp{invokerid} . " msg=" . escape("chan: $c")); }
					if($n) { &ts("sendtextmessage targetmode=1 target=" . $tmp{invokerid} . " msg=" . escape("nick: $n")); }
					if(!$c and !$n) { &ts("sendtextmessage targetmode=1 target=" . $tmp{invokerid} . " msg=" . escape("No bad string found")); }
				}
				next;
			}
			
			if(/^notifycliententerview/) {
				shift;
				my %tmp = &parse;
				$tmp{'time'} = time;
				$clients[$tmp{clid}] = \%tmp;

				&info("Client " .$tmp{client_nickname}. "(" . $tmp{clid} . ") connected");
#				print Dumper(\%tmp);
				my $msg =checkbadnick($tmp{client_nickname});
				if($msg) {
					notifyop($msg);
				}
				next;
			}
	
			if(/^notifyclientleftview/) {
				shift;
				my %tmp = &parse;
				next if(!$clients[$tmp{clid}]);

				if(! $clients[$tmp{clid}]{'client_type'} =~ /^0$/) {
					&info("Client (" . $tmp{clid} . ") disconnected. (unknow client type)");
				}
				elsif(
				$clients[$tmp{clid}]{client_database_id} &&
				$clients[$tmp{clid}]{client_unique_identifier} &&
				$clients[$tmp{clid}]{client_nickname} &&
				$clients[$tmp{clid}]{client_nickname}) {

					my $onlinetime = time - $clients[$tmp{clid}]{'time'};
					my $sql = "INSERT INTO onlinetime (client_id, client_unique_identifier, nickname, onlinetime) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE onlinetime=onlinetime+?, nickname=?, connectioncount=connectioncount+1;";
					my $sh = $dbh->prepare( $sql ) or die "huh?" . $dbh->errstr;
					$sh->execute(
						$clients[$tmp{clid}]{client_database_id},
						$clients[$tmp{clid}]{client_unique_identifier},
						$clients[$tmp{clid}]{client_nickname},
						$onlinetime,
						$onlinetime,
						$clients[$tmp{clid}]{client_nickname}
					) or die "Huh?" . $dbh->errstr;
					$sh->finish;

					if($tmp{reasonid} == 5) {
						&info("Client " . $clients[$tmp{clid}]{client_nickname} . "(" . $tmp{clid} . ") kicked. Online time " . (time - $clients[$tmp{clid}]{'time'}));

						my $onlinetime = time - $clients[$tmp{clid}]{'time'};
						my $sql = "INSERT INTO kicks (client_id, client_unique_identifier, nickname, onlinetime, reasonid, reasonmsg) VALUES (?, ?, ?, ?, ?, ?);";
						my $sh = $dbh->prepare( $sql ) or die "huh?" . $dbh->errstr;
						$sh->execute(
							$clients[$tmp{clid}]{client_database_id},
							$clients[$tmp{clid}]{client_unique_identifier},
							$clients[$tmp{clid}]{client_nickname},
							$onlinetime,
							$tmp{reasonid},
							$tmp{reasonmsg},
						) or die "Huh?" . $dbh->errstr;
						$sh->finish;
					}
					else {
						&info("Client " . $clients[$tmp{clid}]{client_nickname} . "(" . $tmp{clid} . ") disconnected. Online time " . (time - $clients[$tmp{clid}]{'time'}));
					}



				} else {
					&info("Client (" . $tmp{clid} . ") disconnected.");
				}
				delete $clients[$tmp{clid}];
				next;
			}

			if(/^notifyclientmoved/) {
				shift;
				my %tmp = &parse;
				next if(defined $clients[$tmp{clid}]{ctid} and $clients[$tmp{clid}]{ctid} == $tmp{ctid});

				if($clients[$tmp{clid}]{client_nickname}) {
					if($tmp{invokername}) {
						&info("Client " . $clients[$tmp{clid}]{client_nickname} . "(" . $tmp{clid} . ") moved to channel id " . $tmp{ctid} . " by " . $tmp{invokername});
					}
					else {
						&info("Client " . $clients[$tmp{clid}]{client_nickname} . "(" . $tmp{clid} . ") moved to channel id " . $tmp{ctid});
					}
				} else {
					if($tmp{invokername}) {
						&info("Client (" . $tmp{clid} . ") moved to channel id " . $tmp{ctid} . " by " . $tmp{invokername});
					}
					else {
						&info("Client (" . $tmp{clid} . ") moved to channel id " . $tmp{ctid});
					}

				}
				$clients[$tmp{clid}]{ctid} = $tmp{ctid};
				#print Dumper(\%tmp);
				next;
			}

			if(/^notifychannelcreated/) {
				shift;
				my %tmp = &parse;

				&info("Channel " . $tmp{channel_name} . " (" . $tmp{cid} . ") created by " . $tmp{invokername} . "(" . $tmp{invokerid} . ")");
				#print Dumper(\%tmp);
				my $msg =checkbadch($tmp{channel_name});
				if($msg) {
					notifyop("Channel " . $tmp{channel_name} . " (" . $tmp{cid} . ") created by " . $tmp{invokername} . "(" . $tmp{invokerid} . ")");
					notifyop($msg);
				}
				next;
			}

			if(/^notifychanneldeleted/) {
				shift;
				my %tmp = &parse;

				&info("Channel (" . $tmp{cid} . ") deleted by " . $tmp{invokername} . ($tmp{invokerid}? "(".$tmp{invokerid}.")" : ""));
				print Dumper(\%tmp);
				next;
			}

			if(/^notifychanneledited/) {
				shift;
				my %tmp = &parse;

				&info("Channel " . $tmp{channel_name} . " (" . $tmp{cid} . ") edited by " . $tmp{invokername} . "(" . $tmp{invokerid} . ")");
#				print Dumper(\%tmp);
				next;
			}
			if(/^notifychannelpasswordchanged/) {
				shift;
				my %tmp = &parse;

				&info("Channel (" . $tmp{cid} . ") password changed");
#				print Dumper(\%tmp);
				next;
			}
			if(/^notifychanneldescriptionchanged/) {
				shift;
				my %tmp = &parse;

				&info("Channel (" . $tmp{cid} . ") password changed");
				#print Dumper(\%tmp);
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
						my %tmp = &parse;
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

sub parse {
	my @datas = split / /, $_;
	my %tmp;
	while(@datas) {
		my ($key, $value) = split /\s*=\s*/, shift(@datas), 2;
		$tmp{$key} = unescape($value);
	}
	return %tmp;
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

