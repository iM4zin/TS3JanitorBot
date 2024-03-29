package ts3bot::Commands;
use warnings; use strict;
use Data::Dumper;
use Math::Round;
use DBI;

sub cmd_test {
    my (%tmp) = @_;

    # now retrieve data from the table.
    foreach my $c (@ts3bot::clients) {
        my $sth = $ts3bot::dbh->prepare("SELECT * FROM `".$ts3bot::config->{db_infotable}."` WHERE `uuid` = ? AND `type` = 'TeamSpeak3';") or die "Huh?" . $ts3bot::dbh->errstr;
        $sth->execute(
            $c->{client_unique_identifier}
        ) or die "Huh?" . $ts3bot::dbh->errstr;
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
            &ts3bot::ts("sendtextmessage targetmode=1 target=" . $tmp{invokerid} . " msg=" . ts3bot::escape("Nickname: [URL=client://".$c->{clid}."/".$c->{client_unique_identifier}."~".$urlescape."]".$c->{client_nickname}."[/URL], time: " .$t. ", count: " .$ref->{'onlinecount'}));
        }
        $sth->finish();
    }

}

sub cmd_dump {
	my (%tmp) = @_;
	my $count = 0;
	foreach my $c (@ts3bot::clients) {
		if($c->{clid}) {
			print $c->{clid} . " " . $c->{client_unique_identifier} . " " . $c->{client_nickname} ."\n";
			$count++;
			#print Dumper(\%c);
		}
	}
	print "Total: $count\n";
}

sub cmd_testbad {
	my (%tmp) = @_;
	if($tmp{msg} =~ /\!testbad (.*)/) {
		my $c =ts3bot::checkbadch($1);
		my $n =ts3bot::checkbadnick($1);
		if($c) { &ts3bot::ts("sendtextmessage targetmode=1 target=" . $tmp{invokerid} . " msg=" . ts3bot::escape("chan: $c")); }
		if($n) { &ts3bot::ts("sendtextmessage targetmode=1 target=" . $tmp{invokerid} . " msg=" . ts3bot::escape("nick: $n")); }
		if(!$c and !$n) { &ts3bot::ts("sendtextmessage targetmode=1 target=" . $tmp{invokerid} . " msg=" . ts3bot::escape("No bad string found")); }
	}
	else {
		&ts3bot::ts("sendtextmessage targetmode=1 target=" . $tmp{invokerid} . " msg=" . ts3bot::escape("No string found"));
	}
}

sub cmd_stopbot {
	my (%tmp) = @_;
	$ts3bot::EXIT = 1;
}

1;
