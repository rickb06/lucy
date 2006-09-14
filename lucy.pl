#!/usr/bin/perl
# SVN: $Id: lucy.pl 205 2006-05-17 06:29:45Z trevorj $
# _____________
# Lucy; irc bot
# ~trevorj <[trevorjoynson@gmail.com]>
#
#	Copyright 2006 Trevor Joynson
#
#	This file is part of Lucy.
#
#	Lucy is free software; you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation; either version 2 of the License, or
#	(at your option) any later version.
#
#	Lucy is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with Lucy; if not, write to the Free Software
#	Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
#
package Lucy;
use warnings;
use strict;
no strict "refs";
use vars qw($VERSION $dbh $sessid $lucy);
$VERSION = "0.5svn";

# temporary fix as I don't want much arg parsing going on unless it's needed
if ( defined $ARGV[0] && $ARGV[0] =~ /^--chdir="?(.+)"?$/ ) {
	print "Changing working directory to " . $1 . "\n";
	chdir $1;
}

BEGIN {
	unshift( @INC, "./lib" );
}

use Lucy::Config;
use Lucy::Common;
use Lucy::Sky;
use POE;
use DBIx::Simple;

# grab dbi object
$dbh = DBIx::Simple->connect(
	$config->{DBdsn},
	$config->{DBuser},
	$config->{DBpass},
	{
		RaiseError => 0,
		AutoCommit => 1,
		PrintWarn  => ( $config->{debug_level} > 6 ) ? 1 : 0,
		PrintError => ( $config->{debug_level} > 4 ) ? 1 : 0
	}
  )
  or die "Cannot connect to DB!";

# Lucy in the Skyyyyy with Diamonds
$lucy = Lucy::Sky->new();

## Diamonds, aka plugins if you're lame
$lucy->add_diamond( @{ $config->{Diamonds} } );

#TODO move this into the plugins, so that we only use the ones we need
$lucy->add_event(
	qw(
	  irc_disconnected
	  irc_error
	  irc_mode
	  irc_socketerr
	  irc_001
	  irc_315
	  irc_324
	  irc_352
	  irc_364
	  irc_365
	  irc_invite
	  irc_join
	  irc_part
	  irc_quit
	  irc_kick
	  irc_topic
	  irc_ctcp_action
	  irc_public
	  irc_msg
	  irc_bot_command
	  irc_bot_msg
	  irc_bot_public
	  irc_nick
	  irc_mode
	  irc_notice
	  irc_snotice
	  )
);

#	  got_pong
#  irc_isupport
#  irc_bot_connected
#  irc_ping

$poe_kernel->run();
exit(0);

# gotta have the session id available
sub sessid {
	return $lucy->session_id;
}

1;
