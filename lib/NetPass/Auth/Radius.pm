# $Header: /tmp/netpass/NetPass/lib/NetPass/Auth/Radius.pm,v 1.3 2005/04/08 20:08:21 jeffmurphy Exp $

#   (c) 2004 University at Buffalo.
#   Available under the "Artistic License"
#   http://www.gnu.org/licenses/license-list.html#ArtisticLicense

package NetPass::Auth::Radius;

use strict;
no strict 'refs';

use Class::ParmList qw(simple_parms parse_parms);
use NetPass::LOG qw(_log _cont);
use NetPass::Config;
use base 'NetPass';

use Authen::Radius;

use vars qw(@ISA);

@ISA = qw(NetPass);
my $VERSION = '1.0001';

=head1 NAME

NetPass::Auth::Radius - Routines for authenticating against RADIUS

=head1 SYNOPSIS

 use NetPass;
 $bool = $np->authenticateUser($username, $password)

 $err = $np->error

=head1 DESCRIPTION

This module is a subclass of NetPass. It's not intended to be called
directly, but should be referenced via the NetPass object.

=cut

sub authenticateUser {
    my $np = shift;
    my ($u, $p) = (shift, shift);

    foreach my $rs ($np->cfg()->{'cfg'}->keys('radius')) {
	_log("DEBUG", "trying radius server $rs\n");
	
	my $sec = $np->{'cfg'}->{'cfg'}->obj('radius')->obj($rs)->value('secret');

	_log("DEBUG", "trying radius secret $sec\n");
	
	my $r = new Authen::Radius(Host   => $rs,
				   Secret => $sec);
	if (!defined($r)) {
		_log("ERROR", "Failed to connect to radius server ($rs)\n");
		return 0;
	}

	$r->clear_attributes;
	$r->add_attributes (
		    { Name => 1, Value => $u, Type => 'string' },
		    { Name => 2, Value => $p, Type => 'string' }
        );

	$r->send_packet(ACCESS_REQUEST);
        my $rcv = $r->recv_packet();
        return 1 if (defined($rcv) and $rcv == ACCESS_ACCEPT);
    }

    return 0;
}

=AUTHOR

Jeff Murphy <jcmurphy@buffalo.edu>

=head1 LICENSE

   (c) 2004 University at Buffalo.
   Available under the "Artistic License"
   http://www.gnu.org/licenses/license-list.html#ArtisticLicense

=head1 REVISION

$Id: Radius.pm,v 1.3 2005/04/08 20:08:21 jeffmurphy Exp $

=cut

1;

