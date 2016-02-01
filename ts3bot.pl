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

&info("starting: $config->{botname}\n");

if (-e $config->{pidfile}) {
        open PIDFILE,$config->{pidfile};
        my $p=<PIDFILE>;
        chomp $p;
        close PIDFILE;
        &info("Removing old pidfile, pid was $p\n");
}
open PIDFILE,">$config->{pidfile}" or &fatal("Cannot write pidfile $config->{pidfile}: $!\n");
print PIDFILE "$$\n";
close PIDFILE;

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

&ts("use sid=" .$config->{serverid});
&ts_silent("login client_login_name=" .$config->{serveruser}. " client_login_password=" .$config->{serverpass});
&ts("serverinfo");
&ts("servernotifyregister event=textprivate");
#&ts("servernotifyregister event=server");
&ts("servernotifyregister event=channel id=0");

my $pingtime = time;
while (1) {
	my $s;
	while ($s = <$sock>) {
		my @lines = ();
		push @lines, split(/\r/, $s);

		foreach(@lines) {
			chomp;
#			print $_ ."\n";
			if(!/\S/ or /Welcome to the TeamSpeak 3/ or /TS3/) {
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
				my %d;
				shift(@datas);
				while(@datas) {
					my ($key, $value) = split /\s*=\s*/, shift(@datas);
#					print "*  " . $key . " : " . $value ."\n";
					$d{$key} = $value;
				}
				&info("Got message from $d{invokername}: $d{msg}");
				if(!checkop( $d{'invokeruid'} )) {
					next;
				}

#				print Dumper(\%d);
				if($d{msg} =~ /\!dump/) {
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
				next;
			}
			
			if(/notifycliententerview/) {
				my @datas = split / /, $_;
				my $clid;
				my %tmp;
				shift(@datas);
				while(@datas) {
					my ($key, $value) = split /\s*=\s*/, shift(@datas);
#					print "*  " . $key . " : " . $value ."\n";
					if($key =~ /clid/) { $clid = $value; }
					$tmp{$key} = $value;
				}
				$tmp{'time'} = time;
				if($tmp{'client_type'} =~ /^0$/) {	#no server query
					$clients[$clid] = \%tmp;
				}

				&info("Client " .$tmp{client_nickname}. "(" . $clid . ") connected");
				# print $clients[$clid]{clid} . "\n";
				#print Dumper($clients[$clid]);
				next;
			}
	
			if(/notifyclientleftview/) {
				my @datas = split / /, $_;
				my $clid;
				shift(@datas);
				while(@datas) {
					my ($key, $value) = split /\s*=\s*/, shift(@datas);
					if($key =~ /clid/) { $clid = $value; }
				}

				if(! $clients[$clid]) {
					&info("Client (" . $clid . ") disconnected.");
				}
				else {
					&info("Client " . $clients[$clid]{client_nickname} . "(" . $clid . ") disconnected. Online time " . (time - $clients[$clid]{'time'}));
					my $onlinetime = time - $clients[$clid]{'time'};

				#	print "INSERT INTO onlinetime (client_id, client_unique_identifier, onlinetime) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE onlinetime=onlinetime+?;\n";
				#	print $clients[$clid]{client_database_id}."\n";
				#	print $clients[$clid]{client_unique_identifier}."\n";
				#	print time - $clients[$clid]{'time'}."\n";
				#	print time - $clients[$clid]{'time'}."\n";

					my $sql = "INSERT INTO onlinetime (client_id, client_unique_identifier, onlinetime) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE onlinetime=onlinetime+?;";

					my $sh = $dbh->prepare( $sql ) or die "huh?" . $dbh->errstr;
					$sh->execute(
						$clients[$clid]{client_database_id},
						$clients[$clid]{client_unique_identifier},
						$onlinetime,
						$onlinetime,
					) or die "Huh?" . $dbh->errstr;
					$sh->finish;

				}
				delete $clients[$clid];
				next;
			}
			if(/notifyclientmoved/) {
				my @datas = split / /, $_;
				my $clid;
				my %d;
				shift(@datas);
				while(@datas) {
					my ($key, $value) = split /\s*=\s*/, shift(@datas);
					if($key =~ /clid/) { $clid = $value; }
					$d{$key} = $value;
				}
				&info("Client (" . $clid . ") moved.");
				print Dumper(\%d);
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

