# $Header: /tmp/netpass/NetPass/lib/SNMP/Device/BayStack.pm,v 1.7 2006/01/05 21:02:35 jeffmurphy Exp $

#   (c) 2004 University at Buffalo.
#   Available under the "Artistic License"
#   http://www.gnu.org/licenses/license-list.html#ArtisticLicense

package SNMP::Device::BayStack;

use SNMP::Device;
use Net::SNMP;
use Bit::Vector;
use Data::Dumper;
use NetPass::LOG qw (_log _cont);
use Time::HiRes qw (gettimeofday tv_interval);

@ISA = ('SNMP::Device');

use strict;

=head1 NAME

SNMP::Device::BayStack - BayStack SNMP Controls

=head1 SYNOPSIS

This object is a subclass of L<|SNMP::Device> and shouldn't be used
directly. When a new SNMP::Device is created, it will return an
object of this type if it's appropriate.

=head1 SYNOPSIS

This object allows us to interface with the various Nortel BayStack switches.
Those include 450, 470 and 5510.

=head1 PUBLIC METHODS

=head2 B<init()>

=over 8

init is called immediately after the discovery of device type.
this is an optional function and in this module, is used to set the
snmp version to '2'

=back

=cut

sub init {
	my $self	= shift;

	$self->log( ref($self) . "->init(): setting snmp version to '2'");
	$self->snmp_version('2');
	
	# set snmp to undef to force re-create on next snmp() call...
	# i'll find a nicer way to do this.. perhaps a snmp_refresh call or something
	$self->{_snmp} = undef;
	$self->log( ref($self) . "->init(): resetting snmp session");
	$self->snmp;

        return 1;
}

=head2 B<restore()>

=over 8

Restore a previously saved configuration to the switch from a tftp server.

=back

=cut

sub restore {
	my $self 	= shift;
	my $direction 	= "3";	# get cfg from tftp server
	
	return $self->_baystack_cfg_transfer($direction);
}

=head2 B<backup()>

=over 8

Backup the switch config to a tftp server.

=back

=cut

sub backup {
	my $self 	= shift;
	my $direction 	= "4";	# send cfg to tftp server

	return $self->_baystack_cfg_transfer($direction);
}

=head2 B<get_unit_info()>

=over 8

This will return a hash with the serial, description, and type of
each unit in a stack.

=back

=cut

sub get_unit_info {
	my $self = shift;

	my $stack_info = {};

	my $oids = {
        		'serial'        => '.1.3.6.1.4.1.45.1.6.3.3.1.1.7.8',
			'sys_descr'	=> '.1.3.6.1.4.1.45.1.6.3.3.1.1.5.8',
			'type'		=> '.1.3.6.1.4.1.45.1.6.3.3.1.1.6.8',
			
		   };
	
        foreach my $oid (keys %$oids) {
                $self->_loadTable($oids->{$oid}, $oid, $stack_info);
        }
	
	$self->_loadSwFw($stack_info); 

	return $stack_info;

}

=head2 B<get_if_info($port)>

=over 8

This will return a hash with all interfaces (or just the one
you specified) and their information, including unit, port, admin status, 
operational status, autonegotiation, duplex, speed, fcs errors, vlan 
tagged/untagged, PVID, and member VLANS. The B<$port> parameter
is the final digit of the OID, not really the port number.

=back

=cut

sub get_if_info {
	my $self = shift;
	my $port = shift;

	my $port_info = {};

	my $oids = {
			'port'	  	  => '.1.3.6.1.4.1.45.1.6.15.1.1.1.3',
        		'if_descr'        => '.1.3.6.1.2.1.2.2.1.2',

        		'if_status'       => '.1.3.6.1.2.1.2.2.1.8',
        		'if_ad_status'    => '.1.3.6.1.2.1.2.2.1.7',

			# 2 full, 1 half
			'duplex'          => '.1.3.6.1.4.1.2272.1.4.10.1.1.12',
			# 2 disabled, 1 enabled
			'autoneg'         => '.1.3.6.1.4.1.2272.1.4.10.1.1.11',
			# speed in mbps e.g. 10,100,1000
			#'speed'           => '.1.3.6.1.4.1.2272.1.4.10.1.1.15',
			# 0=0, 1=10, 2=100, 3=1000
			'speed'           => '.1.3.6.1.4.1.2272.1.4.10.1.1.14',

			'fcs_errors'      => '.1.3.6.1.2.1.10.7.2.1.3',

			'vlan_port_type'  => '.1.3.6.1.4.1.2272.1.3.3.1.4',
		        # 1 = not trunk, 2 = trunk
        		'vlan_default_id' => '.1.3.6.1.4.1.2272.1.3.3.1.7'
		   };

	if ($port) {
		my @vbl;
		my $oid2name = {};
		foreach my $name (keys %$oids) {
			push @vbl, $oids->{$name}.".$port";
			$oid2name->{$oids->{$name}.".$port"} = $name;
		}

		my $r = $self->snmp->get_request(-varbindlist => \@vbl);

		if ($self->snmp->error) {
			$port_info->{$port}->{'error'} = $self->snmp->error;
		} else {
			foreach my $oid (keys %$oid2name) {
				$port_info->{$port}->{$oid2name->{$oid}} = $r->{$oid};
			}
		}
		return $port_info;
	}


	# otherwise, we need to fetch all of the ports and do a bigger hash

        foreach my $oid (keys %$oids) {
                $self->_loadTable($oids->{$oid}, $oid, $port_info);
        }

	$self->_loadVlanPortMembers($port_info);

	# get unit number		
	foreach my $num(sort keys %{$port_info}) {
		$port_info->{$num}{'unit'} = 1;
	
		my $mod = $port_info->{$num}{'if_descr'};

		if($mod =~ /module\s+(\d+)/) {
			$port_info->{$num}{'unit'} = $1;
		}
		if($mod =~ /Unit\s+(\d+)/) {
			$port_info->{$num}{'unit'} = $1;
		}
	}

	return $port_info;

}

=head2 B<set_default_vlan_id(port, vlan)>

=over 8

Set the default VLAN that untagged packets will be placed into. If you want to
I<add> a port to a VLAN, so that already tagged packets will be delivered to that port,
use L<add_vlan_membership>. Returns 1 on success, 0 on failure.

=back

=cut

sub set_default_vlan_id {
        my $self = shift;
        my $port = shift;
        my $vid  = shift;

        # nortel (450s, 470s, 5510 and late-model 350s)

        # RAPID-CITY::rcVlanPortNumVlanIds.24 = INTEGER: 1
        # RAPID-CITY::rcVlanPortNumVlanIds.25 = INTEGER: 3
        # RAPID-CITY::rcVlanPortVlanIds.24 = Hex-STRING: 03 2C
        # RAPID-CITY::rcVlanPortVlanIds.25 = Hex-STRING: 00 01 00 0C 03 2C
        # RAPID-CITY::rcVlanPortType.24 = INTEGER: access(1)
        # RAPID-CITY::rcVlanPortType.25 = INTEGER: trunk(2)
        # RAPID-CITY::rcVlanPortDefaultVlanId.24 = INTEGER: 12
        # RAPID-CITY::rcVlanPortDefaultVlanId.25 = INTEGER: 1

        # this one sets the default "PVID"

        # .iso.org.dod.internet.private.enterprises.rapidCity.rcMgmt.rcVlan.rcVlanPortTable.rcVlanPortEntry.rcVlanPortDefaultVlanId
        # .1.3.6.1.4.1.2272.1.3.3.1.3.7.PORT = integer
        # "meaningless when the port is not a trunk port" but we set it anyway since
        # tests indicate that it really is used even on 'access' ports.

        my $vlan_default_id = ".1.3.6.1.4.1.2272.1.3.3.1.7.$port";
        $self->snmp->set_request ($vlan_default_id, INTEGER, $vid);

        if($self->snmp->error) {
            #_log ("ERROR", "SNMP err". $self->snmp->error."\n");
            $self->err($self->snmp->error);
            return 0;
        }

        #_log ("DEBUG", "def id succ set to $vid\n") if $self->debug;
        return 1;
}

=head2 B<del_vlan_membership(port, id)>

=over 8

Remove the port from the specified VLAN. Preserve membership in other
VLANs, if any. Returns: 0 on failure, 1 on success.

=back

=cut

sub del_vlan_membership {
    	my ($self, $port, $id) = (shift, shift, shift);

    	#    rcVlanId OBJECT-TYPE
    	#        SYNTAX        INTEGER (1..4094)

    	return 0 if ($id < 1 || $id > 4094);

    	$self->snmp->translate(['-all' => 0]); #[ -octetstring => 0x0 ]);

    	# fetch bitfield

	# PortSet can vary in size. Some models return 32 bytes,
	# others 64. In the 470 Mib (BOSS 3.1) it's declared as 
	# an 88 byte octet string. Instead of hardcoding the length,
	# we'll calculate it.

    	my $oid = ".1.3.6.1.4.1.2272.1.3.2.1.11.$id";
    	my $vl  = $self->snmp->get_request($oid);

    	if($self->snmp->error) {
        	$self->err($self->snmp->error);
        	return 0;
    	}

	my $field_length = length($vl->{$oid});

    	_log ("INFO", "HEX field[BEF]: [$field_length bytes] ", 
	      unpack('H*', $vl->{$oid})."\n") if $self->debug > 1;

	my $bit_width = $field_length * 8;

    	my $bv = Bit::Vector->new_Hex($bit_width, unpack('H*', $vl->{$oid}));

    	# set our port bit to zero

    	_log("INFO", "Bitfield[BEF]:\n".$bv->to_Bin()."\n") if $self->debug > 1;

    	$bv->Bit_Off($bit_width - 1 - $port); # MSB=port0, in B::V, MSB=bit255

    	_log("INFO", "Bitfield[AFT]:\n".$bv->to_Bin()."\n") if $self->debug > 1;

    	_log ("INFO", "HEX field[AFT]:".$bv->to_Hex()."\n") if $self->debug > 1;
    
	$self->snmp->set_request($oid, OCTET_STRING, pack('H*', $bv->to_Hex()));
    
	if($self->snmp->error) {
        	$self->err($self->snmp->error);
        	return 0;
    	}

    	return 1;
}

=head2 B<add_vlan_membership(port, id)>

=over 8

Add the port to the specified VLAN. Preserve membership in other VLANs,
if any. Returns: 0 on failure, 1 on success.

=back

=cut

sub add_vlan_membership {
    	my ($self, $port, $id) = (shift, shift, shift);

    	#    rcVlanId OBJECT-TYPE
    	#        SYNTAX        INTEGER (1..4094)

    	return 0 if ($id < 1 || $id > 4094);

    	# fetch bitfield

	# PortSet can vary in size. Some models return 32 bytes,
	# others 64. In the 470 Mib (BOSS 3.1) it's declared as 
	# an 88 byte octet string. Instead of hardcoding the length,
	# we'll calculate it.

    	my $oid = ".1.3.6.1.4.1.2272.1.3.2.1.11.$id";
    	my $vl  = $self->snmp->get_request($oid);

    	if($self->snmp->error) {
        	$self->err($self->snmp->error);
        	return 0;
    	}

	my $field_length = length($vl->{$oid});

    	_log ("INFO", "HEX field[BEF]: [$field_length bytes] ", 
	      unpack('H*', $vl->{$oid})."\n") if $self->debug > 1;

	my $bit_width = $field_length * 8;

    	my $bv = Bit::Vector->new_Hex($bit_width, unpack('H*', $vl->{$oid}));

    	# set our port bit to zero

    	_log("INFO", "Bit field[BEF]:\n".$bv->to_Bin()."\n") if $self->debug > 1;
    
	$bv->Bit_On($bit_width - 1 - $port);
    
	_log ("INFO", "Bit field[AFT]:\n".$bv->to_Bin()."\n") if $self->debug > 1;
	_log ("INFO", "HEX field[AFT]:".$bv->to_Hex()."\n") if $self->debug > 1;

    	$self->snmp->set_request($oid, OCTET_STRING, pack('H*', $bv->to_Hex()));
    
	if($self->snmp->error) {
        	$self->err($self->snmp->error);
        	return 0;
    	}

    	return 1;
}

=head2 B<check_if_tagged(port)>

=over 8

Check if port is a tagged trunk. Returns 1 if the port is tagged, 0 if
untagged.

=back

=cut

sub check_if_tagged {
    	my $self = shift;
    	my $port = shift;

    	my $oid = ".1.3.6.1.4.1.2272.1.3.3.1.4.$port";

    	my $res = $self->snmp->get_request ( $oid );
    	return ($res->{$oid} == 2) ? 1 : 0;
}

=head2 B<get_all_ports()>

=over 8

Retrieve the list of ports on this device. Return array reference on success
or C<undef> on failure.

=back

=cut

sub get_all_ports {
        my $self = shift;
        my @ports;

        my $oid   = ".1.3.6.1.2.1.2.2.1.1";
        my $oid_n = $oid;

        while (1) {
                my $res = $self->snmp->get_next_request(-varbindlist => [$oid_n]);
                return undef if !$res;

                $oid_n = (keys(%$res))[0];

                last if ($oid ne substr($oid_n, 0, length($oid)));
                push @ports, $res->{$oid_n};
        }

        return \@ports;
}

=head2 B<get_vlan_membership(port)>

=over 8

Retrieve the list of VLANs that this port is a member of. Return them via
an array reference. Return array reference on success or C<undef> on failure.

=back

=cut

sub get_vlan_membership {
        my $self = shift;
        my $port = shift;

        $self->snmp->translate(['-all' => 0]); #[ -octetstring => 0x0 ]);

        my $oid = ".1.3.6.1.4.1.2272.1.3.3.1.3.$port";

        my $vid = $self->snmp->get_request ( $oid );

        if($self->snmp->error) {
            	$self->err($self->snmp->error);
            	return undef;
        }
        #_log("DEBUG",  "port $port membership: ".length($vid->{$oid})."  ".unpack('H*', $vid->{$oid})."\n") if($self->debug);

        my @vs;
        for (my $i = 0; $i < length($vid->{$oid}); $i+=2) {
            push @vs, hex(unpack('H*', substr($vid->{$oid}, $i, 2)));
        }

        return \@vs;
}

=head2 B<get_default_vlan_id(port)>

=over 8

For trunked ports, this is the vlan that incoming untagged packets are
tagged into. Nortel calls this "PVID". Returns: the PVID (positive integer)
on success, B<0 on failure>.

=back

=cut

sub get_default_vlan_id {
	my $self = shift;
	my $port = shift;
	    
	$self->snmp->translate([ -all => 0x0 ]);
	      
	my $vlan_default_id = ".1.3.6.1.4.1.2272.1.3.3.1.7.$port";
		
        my $vid = $self->snmp->get_request ($vlan_default_id);
	
	if($self->snmp->error) {
		$self->err($self->snmp->error);
		return 0;
        }
	
        return $vid->{$vlan_default_id};
}

=head2 B<$port = get_mac_port($mac)>

=over 8

Given a MAC address, determine if it's on the current switch. If it is,
return the port number, otherwise return C<undef>

=back

=cut

sub get_mac_port {
        my $self = shift;
        my $mac  = shift;
	my $decmac = HexMac2DecMac($mac);
	my $mac_table_oid = '.1.3.6.1.2.1.17.4.3.1.2'; # SNMPv2-SMI::mib-2.17.4.3.1.2

	_log("DEBUG", "get_mac_port($mac) oid=$mac_table_oid\n") if $self->debug;
	my $response = $self->snmp->get_request ("$mac_table_oid.$decmac");
	_log("DEBUG", "get_mac_port($mac) resp=",Dumper($response),"\n") if $self->debug;

	if ($self->snmp->error) {
		$self->err($self->snmp->error);
		_log("ERROR", "$mac get_request failed ".$self->snmp->error."\n");
		return undef;
	}

	if ($response->{"$mac_table_oid.$decmac"} eq "noSuchInstance") {
		return undef;
	}

        return $response->{"$mac_table_oid.$decmac"};
}


=head2 B<($module, $port) = get_ifDesc($ifIndex)>

=over 8

Given an ifIndex, return the module and port that it corresponds too. This is
used by the topology search routine (get_next_switch).

=back

=cut

sub get_ifDesc {
	my $self       = shift;
	my $ifIndex    = shift;
	my $ifDescBase = "1.3.6.1.2.1.2.2.1.2";

	my $oid = $ifDescBase.".".$ifIndex;

	#_log("DEBUG", "get_ifDesc($ifIndex) oid=$oid\n");
	my $response = $self->snmp->get_request ($oid);
	#_log("DEBUG", "get_ifDesc($ifIndex) resp=", Dumper($response), "\n");


	if ($self->snmp->error) {
		$self->err($self->snmp->error);
		_log("ERROR", "get_request($oid) failed ".$self->snmp->error."\n");
		return undef;
	}

	if ($response->{$oid} eq "noSuchInstance") {
		_log("ERROR", "get_request($oid) returned noSuchInstance\n");
		return undef;
	}

	# .1.3.6.1.2.1.2.2.1.2.1 = STRING: BayStack - module 1, port 1

	if ($response->{$oid} =~ /module\s+(\d+),\s+port\s+(\d+)/) {
		return ($1, $2);
	} 

	# for unstacked units:
	# BayStack 450-12F - 12
	# BayStack 450-24T - 12
        # Nortel Networks BayStack 470_24 Ethernet Switch Module - Port 22
        # Nortel Networks BayStack 470_24 Ethernet Switch Module - Unit 1 Port 22
	# etc

        if ($response->{$oid} =~ /BayStack\s470.*-\sPort\s(\d+)/) {
                return (1, $1);
        }

        if ($response->{$oid} =~ /BayStack\s470.*-\sUnit\s(\d+)\sPort\s(\d+)/) {
                return ($1, $2);
        }

	if ($response->{$oid} =~ /BayStack\s450-\S+\s\-\s(\d+)/) {
		return (1, $1);
	} 

	_log("ERROR", "could not parse module/port out of \"",
	     $response->{$oid}, "\"\n");

	return undef;
}

=head2 B<$ip = get_next_switch($ifIndex)>

=over 8

Given a port, determine if there's a switch attached to it. 

 ON SUCCESS RETURNS
       Either and IP address of the next switch or ""
 ON FAILURE RETURNS
       C<undef>

Pay attention to the return value. "" means there is no 
downstream switch. C<undef> means there was an SNMP failure.

=back

=cut

sub get_next_switch {
	my $self    = shift;
	my $ifIndex = shift;

	my $topo_oid = '.1.3.6.1.4.1.45.1.6.13.2.1.1.3'; # S5-ETH-MULTISEG-TOPOLOGY-MIB::s5EnMsTopNmmIpAddr

	my $response = $self->snmp->get_table (-baseoid        => "$topo_oid",
					       -maxrepetitions => 10); # populate hash

	if ($self->snmp->error) {
		_log("ERROR", "get_table failed for ",
		     $self->ip, " if=$ifIndex ".$self->snmp->error."\n");
		return undef;
	}

	#_log("DEBUG", "topo \n", Dumper($response), "\n");
	
	my ($targetModule, $targetPort) = $self->get_ifDesc($ifIndex);

	#_log("DEBUG", "target for $ifIndex is $targetModule $targetPort\n");

	foreach my $key (keys %{$response}) {
		my ($slot, $port, $next_ip, $seg_id) = ($key =~ /^$topo_oid\.
								 (\d{1,3})\. # slot
								 (\d{1,3})\. # port
								 (\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\. # next_ip
								 (\d{1,3}) # segment id
								 $/x);
		
		return $next_ip if ( ($slot == $targetModule) && 
				     ($port == $targetPort) );
	}
        return "";
}

=head2 B<($mp, $pm) = get_mac_port_table()>

=over 8

Fetch the MAC-to-Port mapping using the bridge mib (rfc1493). Returns two HASH REFs
(\%mac_to_port, \%port_to_mac) on success, C<undef> on failure. The MACs in the hashes
will be zero padded and lowercase.

=back

=cut

sub get_mac_port_table {
	my $self = shift;

    	# .iso.org.dod.internet.mgmt.mib-2.ip.ipNetToMediaTable
    	# .1.3.6.1.2.1.4.22

    	# .iso.org.dod.internet.mgmt.mib-2.at.atTable
   	# .1.3.6.1.2.1.3.1

    	# .iso.org.dod.internet.mgmt.mib-2.dot1dBridge.dot1dTp.dot1dTpFdbTable.dot1dTpFdbEntry.dot1dTpFdbPort
    	# .1.3.6.1.2.1.17.4.3.1.2


    	my $m2p = {};
    	my $p2m = {};
    	my $res;
    	my $oid = ".1.3.6.1.2.1.17.4.3.1.2";

	my $startTime = [gettimeofday];

    	if (!defined($res = $self->snmp->get_table(-baseoid        => $oid,
						   -maxrepetitions => 10))) {
        	$self->err($self->snmp->error);
		_log("DEBUG", "timeout=".$self->snmp_timeout." ip=".$self->ip." failed after ".tv_interval($startTime)." secs\n");
        	return undef;
    	}

  	MAC: foreach my $key (keys %{$res}) {

        	my ($m1, $m2, $m3, $m4, $m5, $m6) = 
		($key =~ /^.*?\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/); # MAC pieces, base 10.
        	
		my $mac = 	sprintf("%2.2x", $m1) .
          			sprintf("%2.2x", $m2) .
          			sprintf("%2.2x", $m3) .
          			sprintf("%2.2x", $m4) .
          			sprintf("%2.2x", $m5) .
          			sprintf("%2.2x", $m6);

		$mac =~ tr [A-Z] [a-z];

        	my $ifIndex = $res->{$key};

        	if (defined ($ifIndex)) {
            		$m2p->{$mac} = [] if !exists $m2p->{$mac};
            		$p2m->{$ifIndex} = [] if !exists $p2m->{$ifIndex};
            		push @{$m2p->{$mac}}     , $ifIndex;
            		push @{$p2m->{$ifIndex}} , $mac;
        	}
    	}

	_log("DEBUG", "timeout=".$self->snmp_timeout." ip=".$self->ip." succeeded after ".tv_interval($startTime)." secs\n");
	
    	return ($m2p, $p2m);
}


# PRIVATE MEMBERS

sub _baystack_cfg_transfer {
	my $self	= shift;
    	my $direction 	= shift;

	my %oid = (
		   ## action:  to/from tftp server...  4=to 3=from 
		   action	=> ".1.3.6.1.4.1.45.1.6.4.2.1.24.0",
		
		   ## the filename of the cfg file  
		   filename 	=> ".1.3.6.1.4.1.45.1.6.4.2.2.1.4.1",

		   ## ip of the tftp server
		   tftpserver	=> ".1.3.6.1.4.1.45.1.6.4.2.2.1.5.1",
		
		   ## status of last transfer
	 	   ## 4=failed, 3=success, 2=inprogress, 1=other
		   status	=> ".1.3.6.1.4.1.45.1.6.4.2.1.25.0",
            	  );

	# WE MAY HAVE TO SET THE FILENAME AND SERVER IN A SEPERATE REQUEST IN
	# ORDER TO ASSURE THAT THEY ARE SET BEFORE THE ACTION

	$self->snmp->set_request ( 
              	## set the filename being written/read
              	$oid{filename}, OCTET_STRING, $self->file,
 
               	##set the tftp server address
                 $oid{tftpserver}, IPADDRESS, $self->tftpserver,
        );
	
	return $self->snmp->error if($self->snmp->error);
	
	$self->snmp->set_request ( 
		 ## set file transfer direction
                 $oid{action}, INTEGER, $direction,
	);

	return $self->snmp->error if($self->snmp->error);

}

sub _loadTable {
	my $self	= shift;	
	my $base_oid    = shift;
	my $desc        = shift;
	my $info	= shift;

	my $table = $self->snmp->get_table(-baseoid => $base_oid,
					   -maxrepetitions => 10);
	if (!defined($table)) {
		$table = $self->snmp->get_table(-baseoid => $base_oid,
						-maxrepetitions => 10);
		if (!defined($table)) {
			foreach my $num(sort keys %{$info}) {
				$info->{$num}{$desc} = 'N/A';
			}
			return 0;
		}
        }

	foreach my $k (keys %$table) {
        	$k =~ /(\d+)(\.0)*$/;
        	my $id = sprintf('%04d', $1);
		$info->{$id}{$desc} = $table->{$k};
	}

	return 1;
}

sub _loadVlanPortMembers {
	my $self	= shift;
	my $info	= shift;

      	# enterprises.rapidCity.rcMgmt.rcVlan.rcVlanPortTable.rcVlanPortEntry.rcVlanPortVlanIds
	my $base_oid = '.1.3.6.1.4.1.2272.1.3.3.1.3';
        my $desc     = 'vlan_ids';

        # turn off session translation... that's b/c these are mal-formed HEX values being returned
        # and Net::SNMP thinks that they are ascii chars sometimes...

        $self->snmp->translate([
                              -all     => 0x0
                            ]);

        my $table = $self->snmp->get_table(-baseoid => $base_oid,
					   -maxrepetitions => 10);

        if (!defined($table)) {
		# try one more freakin time
        	$table = $self->snmp->get_table(-baseoid => $base_oid,
						-maxrepetitions => 10);

        	if (!defined($table)) {
			foreach my $num(sort keys %{$info}) {
				$info->{$num}{$desc} = 'N/A';
			}
			return 0;
		}
        }

        foreach my $k (keys %$table) {
                $k =~ /(\d+)$/;
                my $id = sprintf("%04d", $1);

                my $hex = sprintf('0x%s', unpack('H*', $table->{$k}));
                $hex =~ s/^0x//;
                next if $hex =~ //;

                $hex =~ substr($hex,0,4);

                my @a = split(//,$hex);         # this will catch multiple vlans
                my @vlans = ();

                while($#a > 0) {
                      my $h = join('', splice(@a,0,4));
                      my $vec = Bit::Vector->new_Hex(16, $h);
                      push(@vlans, $vec->to_Dec());
                }

		$info->{$id}{$desc} = join(',', @vlans);

        }
        return 1;
} # end _loadVlanPortMembers

sub _loadSwFw {
	my $self	= shift;
	my $info	= shift;

        my $base_oid    = '.1.3.6.1.4.1.45.1.6.3.5.1.1.7';

        my $table = $self->snmp->get_table(-baseoid => $base_oid, 
					   -maxrepetitions => 10);

	foreach my $num(sort keys %{$info}) {
		$info->{$num}{'firmware'} = 'N/A';
		$info->{$num}{'software'} = 'N/A';
	}
	return 0 if (!defined($table)); 

        foreach my $k (keys %$table) {
        	$k =~ /(\d+)(\.0\.\d)*$/;

                my $id = sprintf("%04d", $1);
		if($2 eq ".0.1") {
			$info->{$id}{'software'} = $table->{$k};
		} elsif ($2 eq ".0.2") {
			$info->{$id}{'firmware'} = $table->{$k};
		} else {

		}
        }
        return 1;

} # end _loadSwFw

=head2 $dm = HexMac2DecMac($hm)

=over 8

This routine takes a mac address in hex format (e.g. 00FF00FF00FF) and
returns it in decimal format (0.255.0.255.0.255). This is useful when certain
OIDs contain mac address... .1.3.6.4.9999.2.1.0.255.0.255.0.255 = ...

=back

=cut

sub HexMac2DecMac {
	my $hex_mac = shift; # hexadecimal mac in raw 12-character format (no : or - separators). 
	my $dec_mac = ''; # rv

	my ($m1, $m2, $m3, $m4, $m5, $m6) = 
	  ($hex_mac =~ /^(\w{2})(\w{2})(\w{2})(\w{2})(\w{2})(\w{2})$/); # MAC pieces, base 16.
	
	$m1 = hex($m1);
	$m2 = hex($m2);
	$m3 = hex($m3);
	$m4 = hex($m4);
	$m5 = hex($m5);
	$m6 = hex($m6);
	
	return "$m1.$m2.$m3.$m4.$m5.$m6"; # decimal equivalent of hexadecimal mac address.
}

=head1 AUTHOR

   Rob Colantuoni <rgc@buffalo.edu>
   Jeff Murphy <jcmurphy@buffalo.edu>
   Chris Miller <cwmiller@buffalo.edu>

=head1 LICENSE

   (c) 2004 University at Buffalo.
   Available under the "Artistic License"
   http://www.gnu.org/licenses/license-list.html#ArtisticLicense

=head1 REVISION

$Id: BayStack.pm,v 1.7 2006/01/05 21:02:35 jeffmurphy Exp $

=cut



1;
