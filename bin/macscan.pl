#!/opt/perl/bin/perl -w
#
# $Header: /tmp/netpass/NetPass/bin/macscan.pl,v 1.8 2005/04/20 15:42:08 jeffmurphy Exp $

#   (c) 2004 University at Buffalo.
#   Available under the "Artistic License"
#   http://www.gnu.org/licenses/license-list.html#ArtisticLicense

=head1 NAME

macscan.pl - periodically scan the switches looking for unknown MACs as well
as ports with multiple MACs.

=head1 SYNOPSIS

 macscan.pl [-q] [-D] [-c cstr] [-U dbuser/dbpass] [-t thread-queue-size] [-s secs]
     -q             be quiet. exit status only.
     -D             enable debugging
     -c             db connect string
     -U             db user[/pass]
     -t             thread queue size
     -s             thread sleep time

=head1 OPTIONS

=over 8

=item B<-q>

Be quiet, don't print anything. Just exit with non-zero status if 
an error occurred. Otherwise, exit with zero status.

=item B<-D> 

Enable debugging output. 

=item B<-c cstr> 

Connect to alternate database.

=item B<-U user/pass> 

Credentials to connect to the database with.

=item B<-t thead-queue-size> 

A number denoting how many switches to delegate to each thread for monitoring.
The default is 20. If you have 100 switches in your NetPass configuration,
5 threads will be spawned. Each thread will linearly search each switch for
multi-mac violations. Each thread requires a connection to the database, 
so don't set this number too low or you'll needless use DB resources.

=item B<-s thead-sleep-time> 

After a thread has finished all of its work, it sleeps for a time. If you don't
have many switches, or don't want to be overly aggressive about checking for 
unknown MAC addresses, you can make this time long. If you want to be more 
aggressive, or have a lot of switches (meaning that the time for each thread
to come back to the first switch again is long) then you can shorten this
time. The default is 300 seconds (5 minutes). So if you only have one switch,
we'll check it every 5 minutes. If you have 2 switches, the check time will
be somewhat (but not much) longer. You can estimate about 30 seconds to check 
a switch.

=back

=head1 DESCRIPTION

This script fetches all configured switches (see L<netpass.conf>) and will continuously
scan each switch for the MAC addresses attached to its ports. If an unregistered
MAC is found, the port is placed back into the quarantine. 

If multiple MACs are found, and one (or more) is unregistered, the port is placed
back into the quarantine and the registered MACs are pointed at a web page 
letting them know why they've been quarantined. The unregistered MACs are implicitly
directed to the default webpage.

This script will only quarantine ports if the MULTI_MAC configuration setting
is set to ALL_OK.

=head1 AUTHOR

Jeff Murphy <jcmurphy@buffalo.edu>

$Id: macscan.pl,v 1.8 2005/04/20 15:42:08 jeffmurphy Exp $

=cut


use strict;
use threads;
use Getopt::Std;
use lib '/opt/netpass/lib/';
use FileHandle;
use Pod::Usage;

use NetPass::LOG qw(_log _cont);
require NetPass;

BEGIN {
    use Config;
    $Config{useithreads} or die "Recompile Perl with threads to run this program.";
}

my %opts : shared;
getopts('c:U:qt:s:Dh?', \%opts);
pod2usage(2) if exists $opts{'h'} || exists $opts{'?'};

# foreach network in <switchmap> {
#    foreach switch in network {
#       ($a, $b) = get_mac_port_table()
#    }
#    if UNKNOWN MAC {
#       moveport switch/port -> bad
#       if MULTIPLE MACS {
#          set_message(MULTIPLE_OK_WITH_UNKNOWN)
#       }
#    }
#

my $D : shared = exists $opts{'D'} ? 1 : 0;

NetPass::LOG::init *STDOUT if $D;
NetPass::LOG::init [ 'macscan', 'local0' ] unless $D;

print "Running in foreground (debugging mode)..\n" if $D;
daemonize("macscan", "/var/run/netpass") unless $D;

my $threadSleep : shared = 300;

$threadSleep = $opts{'s'} if exists $opts{'s'};

my $dbuser : shared;
my $dbpass : shared;
($dbuser, $dbpass) = exists $opts{'U'} ? split('/', $opts{'U'}) : (undef, undef);

my $cstr : shared = exists $opts{'c'} ? $opts{'c'} : undef;

print "Connecting to NetPass ..\n" if $D;

my $np = new NetPass(-cstr   => $cstr,
		     -dbuser => $dbuser, -dbpass => $dbpass,
		     -debug => exists $opts{'D'} ? 1 : 0,
		     -quiet => exists $opts{'q'} ? 1 : 0);

die "Failed to connect to NetPass: $np\n" unless (ref($np) eq "NetPass");

print "Finding all networks ..\n" if $D;

my $nws = $np->cfg->getNetworks();
my @threads;

my $allSwitches = $np->cfg->getSwitches();


# we devide the switches up into groups of "$ps"
# and give each group out to a thread for periodic
# polling

my $ps = exists $opts{'t'} ? $opts{'t'} : 20;

for(my $i = 0 ; $i <= $#{$allSwitches} ; $i += $ps) {
	my $end = $i + $ps - 1;
	$end = $#{$allSwitches} unless ($#{$allSwitches} > $end);

	print "Spawning thread for switches $i thru $end\n" if $D;
	push @threads, new threads (\&thread_entry, @{$allSwitches}[$i..$end]);
	_log("DEBUG", "thread ".$threads[$#threads]->tid." created\n");
}

print "Parent thread waiting\n" if $D;
$threads[0]->join;
print "Parent thread joined\n" if $D;


exit 0;

sub thread_entry {
        my @switches = @_;

	my $tid = threads->tid();

	print "[$tid] Creating thread-local NetPass Connection\n" if $D;

	# perl threads require that each thread have a private DBH. 
	# this means we need a private NP.
	
	my $np = new NetPass(-cstr   => $cstr,
			     -dbuser => $dbuser, -dbpass => $dbpass,
			     -debug  => exists $opts{'D'} ? 1 : 0,
			     -quiet  => exists $opts{'q'} ? 1 : 0);
	
	die "Failed to connect to NetPass: $np\n" unless (ref($np) eq "NetPass");

	# fetch list of ports we "know" about from the config. we
	# use this list to quickly throw away data we aren't interested in

	my %ports;

	# pre-create the SNMP objects for speed. pre-fetch valid
	# ports, again, for speed.

	print "[$tid] Pre-creating SNMP objects.\n" if $D;

	my %snmp;
	foreach my $switch (@switches) {
		foreach my $p (@{$np->cfg->configuredPorts($switch)}) {
			$ports{$p} = 1;
		}
		my ($r, $w) = $np->cfg->getCommunities($switch);
		$snmp{$switch} = new SNMP::Device('hostname'       => $switch,
						  'snmp_community' => $w
						 );
	}

	print "[$tid] Entering loop.\n" if $D;

	while ( 1 ) {
		for my $switch (sort keys %snmp) {
			print "[$tid] Wokeup. Processing $switch ..\n" if $D;
			_log("DEBUG", "thread ".threads->self->tid. " wokeup\n");
			
			my ($mp, $pm) = $snmp{$switch}->get_mac_port_table();
			
			# foreach port:
			#      if port's network has macscan=on AND multi_mac=all_ok then
			#              if port contains unknown mac -> quarantine
			#      fi
			# end

			foreach my $p (keys %$pm) {

				my $nw = $np->cfg->getMatchingNetwork(-switch => $switch,
								      -port   => $p);

				next if ($nw eq "none"); # port is not managed by netpass

				_log("DEBUG", "getMatchingNetwork($switch, $p) = $nw\n") if $D;

				my $macscan   = $np->cfg->policy('MACSCAN', $nw);
				my $multi_mac = $np->cfg->policy('MULTI_MAC', $nw);

				if ($macscan == 0) {
					_log("INFO", "macscan is disabled for this port: $switch/$p ($nw)\n");
					next;
				}

				if ($multi_mac ne "ALL_OK") {
					_log("INFO", "multi_mac is $multi_mac for this port: $switch/$p ($nw)\n");
					next;
				}

				if (!exists $ports{$p}) {
					#print "skipping port $p\n";
				} else {
					
					# check each mac on this port. if any are unknown -> quar
					
					my $portIsOK = 1; # assume true
					my @okMacs;
					my @nOkMacs;
					my $mac;
					
					foreach $mac (@{$pm->{$p}}) {
						my $mok = $np->db->macIsRegistered($mac);

						if ( $mok == -1 ) {
							_log("ERROR", "macIsRegistered($mac) failed: ".$np->db->error()."\n");
						}
						elsif( $mok == 0 ) {
							$portIsOK = 0;
							push @nOkMacs, $mac;
						} 
						else {
							push @okMacs, $mac;
						}
					}
					
					# if any of the MACs were bad, then portIsOK = 0
					# and we need to:
					#     a) set a message on the OK macs so they
					#        understand why they've been quarantined
					#     b) quarantine port
					
					if( ! $portIsOK ) {
						if ($#{$pm->{$p}} > 0) {
							foreach $mac (sort @okMacs) {
								print "[$tid] Found an OK mac with nok neighbors. Adding mmac result..\n" if $D;
								_log("INFO", "Found OK mac $mac on multimac port $switch/$p\n");
								$np->db->addResult(-mac => $mac,
										   -type => 'manual',
										   -id => 'msg:multi_mac');
							}
						}
						
						print "[$tid] Found nok macs ".(join(',', sort @nOkMacs))." on $switch/$p\n" if $D;
						_log("INFO", "Found unreg'd macs ".(join(',', sort @nOkMacs))." on $switch/$p\n");

						$np->movePort(-switch => $switch,
							      -port   => $p,
							      -vlan   => 'quarantine');
					}
				}
			}
		}
		sleep ($threadSleep);
	}
}


# borrowed from mailgraph.pl

sub daemonize
{
    use POSIX 'setsid';

    my ($myname, $pidDir) = (shift, shift);
    chdir $pidDir or die "$myname: can't chdir to $pidDir: $!";
    -w $pidDir or die "$myname: can't write to $pidDir\n";

    open STDIN, '/dev/null' or die "$myname: can't read /dev/null: $!";
    open STDOUT, '>/dev/null'
      or die "$myname: can't write to /dev/null: $!";

    defined(my $pid = fork) or die "$myname: can't fork: $!";
    if($pid) {
	# parent
	my $pidFile = $pidDir . "/" . $myname . ".pid";
	open PIDFILE, "> " . $pidFile
	  or die "$myname: can't write to $pidFile: $!\n";
	print PIDFILE "$pid\n";
	close(PIDFILE);
	exit 0;
    }
    # child
    setsid                  or die "$myname: can't start a new session: $!";
    open STDERR, '>&STDOUT' or die "$myname: can't dup stdout: $!";
}
