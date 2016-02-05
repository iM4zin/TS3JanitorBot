#!/usr/bin/perl
use Sys::Syslog qw(:DEFAULT setlogsock);
use File::Basename;
use IO::Socket;
use DBI;
use Data::Dumper;
use warnings; use strict;

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

my $sock = new IO::Socket::INET (
	PeerAddr => $config->{serveraddress},
	PeerPort => $config->{serverport},
	Proto => 'tcp',
	Blocking => 0,
); 
my @clients;

# Connect to the database.
my $dbh = DBI->connect("DBI:mysql:database=" . $config->{db_database} . ";host=" . $config->{db_host} . "",
	$config->{db_username}, $config->{db_password},
	{'RaiseError' => 1});

&stopbot("Could not create socket: $!") unless $sock;

my $botname = $config->{botname};

&ts("use sid=" .$config->{serverid});
&ts_silent("login client_login_name=" .$config->{serveruser}. " client_login_password=" .$config->{serverpass});
&ts("serverinfo");
&ts("servernotifyregister event=textprivate");
#&ts("servernotifyregister event=server");
&ts("servernotifyregister event=channel id=0");

&ts("servernotifyregister event=server");
&ts("servernotifyregister event=textserver");
&ts("servernotifyregister event=textchannel");
&ts("servernotifyregister event=textprivate");

&ts("clientupdate client_nickname=" . escape($botname));

my $pingtime = time;
while (1) {
	my $s;
	while ($s = <$sock>) {
		my @lines = ();
		push @lines, split(/\r/, $s);

		foreach(@lines) {
			chomp;
			if(!/\S/ or /Welcome to the TeamSpeak 3/ or /^TS3$/) {
				next;
			}

			if(/error id=(\d+)/) {
				if($1 !~ /^0$/) {
					&info("error ". $1 ." \n");
					close $sock;
				}
				next;
			}
		

			if(/virtualserver_clientsonline=(\d+)/) {
				&info("Users online: " . ($1 - 1) . "\n");
				next;
			}

			if(/notifytextmessage/) {
				my @datas = split / /, $_;
				my %tmp;
				shift(@datas);
				while(@datas) {
					my ($key, $value) = split /\s*=\s*/, shift(@datas);
					$tmp{$key} = $value;
				}
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
#							print Dumper(\%c);
						}
					}
					print "Total: $count\n";
				}
				print Dumper(\%tmp);
				next;
			}
			
			if(/notifycliententerview/) {
				my @datas = split / /, $_;
				my %tmp;
				shift(@datas);
				while(@datas) {
					my ($key, $value) = split /\s*=\s*/, shift(@datas);
					$tmp{$key} = $value;
				}
				$tmp{'time'} = time;
				if($tmp{'client_type'} =~ /^0$/) {	#no server query
					$clients[$tmp{clid}] = \%tmp;
				}

				&info("Client " .$tmp{client_nickname}. "(" . $tmp{clid} . ") connected");
				print Dumper(\%tmp);
				next;
			}
	
			if(/notifyclientleftview/) {
				my @datas = split / /, $_;
				my %tmp;
				shift(@datas);
				while(@datas) {
					my ($key, $value) = split /\s*=\s*/, shift(@datas);
					$tmp{$key} = $value;
				}

				if(! $clients[$tmp{clid}]) {
					&info("Client (" . $tmp{clid} . ") disconnected.");
				}
				else {
					&info("Client " . $clients[$tmp{clid}]{client_nickname} . "(" . $tmp{clid} . ") disconnected. Online time " . (time - $clients[$tmp{clid}]{'time'}));
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

				}
				delete $clients[$tmp{clid}];
				print Dumper(\%tmp);
				next;
			}

			if(/notifyclientmoved/) {
				my @datas = split / /, $_;
				my %tmp;
				shift(@datas);
				while(@datas) {
					my ($key, $value) = split /\s*=\s*/, shift(@datas);
					$tmp{$key} = $value;
				}
				if($clients[$tmp{clid}]) {
					if($tmp{invokername}) {
						&info("Client " . $clients[$tmp{clid}]{client_nickname} . "(" . $tmp{clid} . ") moved to channel id " . $tmp{ctid} . " by " . $tmp{invokername});
					}
					else {
						&info("Client " . $clients[$tmp{clid}]{client_nickname} . "(" . $tmp{clid} . ") moved to channel id " . $tmp{ctid});
					}
				} else {
					&info("Client (" . $tmp{clid} . ") moved to channel id " . $tmp{ctid} . " by " . $tmp{invokername});

				}
				print Dumper(\%tmp);
				next;
			}

			if(/notifychannelcreated/) {
				my @datas = split / /, $_;
				my %tmp;
				shift(@datas);
				while(@datas) {
					my ($key, $value) = split /\s*=\s*/, shift(@datas);
					if($key =~ /clid/) { $tmp{clid} = $value; }
					$tmp{$key} = $value;
				}
				&info("Channel (" . $tmp{cid} . ") created by " . $tmp{invokername} . "(" . $tmp{invokerid} . ")");
				print Dumper(\%tmp);
				next;
			}

			if(/notifychanneldeleted/) {
				my @datas = split / /, $_;
				my %tmp;
				shift(@datas);
				while(@datas) {
					my ($key, $value) = split /\s*=\s*/, shift(@datas);
					if($key =~ /clid/) { $tmp{clid} = $value; }
					$tmp{$key} = $value;
				}
				&info("Channel (" . $tmp{cid} . ") deleted by " . $tmp{invokername} . "(" . $tmp{invokerid} . ")");
				print Dumper(\%tmp);
				next;
			}

			print "Unknow command: " . $_."\n";
				
		}
	}

	if($pingtime < time - 60) {
		$pingtime = time;
		&ts_silent("serverinfo");
	}
	sleep 1;
}

sub escape {
	$_=shift;
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
	s/\\\\/\\/g;
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
	print $sock $msg . "\n";
	print STDERR scalar localtime() . " Sent: $msg\n";
}
sub ts_silent {
	my $msg = shift;
	chomp $msg;
	print $sock $msg . "\n";
	#print STDERR scalar localtime() . " Sent: $msg\n";
}
sub stopbot {
	my $msg = shift;
	chomp $msg;
	print STDERR scalar localtime() . " BOT STOPPED: $msg\n";
	$dbh->disconnect();
	close $sock;
	die;
}

sub checkop {
	my $uid = shift;
	foreach my $o ($config->{ops}) {
		if($uid eq $o) {
			return 1;
		}
	}
}


die "end";

