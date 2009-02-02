#!/usr/bin/perl
# SVN: $Id: InfoBot.pm 55 2008-11-24 05:43:05Z trevorj $
# Give Lucy Roids!
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
package Lucy::Diamonds::Roids;
use base qw(Lucy::Diamond);
use POE;
use strict;
use warnings;

# Oh yeah. We need a table name. and I'm so not typing it in a thousand times.
sub tablename { return 'lucy_roids'; }

sub commands {
	return {
		forget   => [qw(forget)],
		unforget => [qw(remember unforget)],
		search   => [qw(factoid whatis roid)],
		history  => [qw(history)],
	};
}

sub init {
	my $self = shift;

	my $config = $self->diamond_config;
	$self->{fact_regex} = $config->{fact_regex} || '[\w\s]{3,32}';
	$self->{trigger_regex} = $config->{trigger_regex}
	  || 'is|are|tastes|smells|feels|sounds|says|fucks|rapes|murders|kills|hates|loves';
}

# Forget/hide a roid
#TODO make this only forget the latest one, ie, sort by ts, then limit 1.
sub forget {
	my ( $self, $v ) = @_;
	return undef unless $v->{args} =~ /^$self->{fact_regex}$/;
	my $fact = $v->{args};
	my @msg;

	if ( $self->_forget_roid($fact) ) {
		Lucy::debug( "Roids", "forget: $fact", 7 );
		push( @msg, "Ok, I forgot $fact" );
	}

	return @msg;
}

# Forget/hide a roid
sub unforget {
	my ( $self, $v ) = @_;
	return undef
	  unless my ( $fact, $key, $val ) =
		  $v->{args} =~
/^(?:unforget|remember)\s+($self->{fact_regex})\s*(?:(id|who|ts)=(\w+))?$/;
	my @msg;

	my $unforget_args;
	if ($key) {
		Lucy::debug( "Roids",
			"unforget: '$fact' is being remembered with $key=$val", 7 );
		$unforget_args = { fact => $fact, "$key" => $val };
	} else {
		Lucy::debug( "Roids", "unforget: '$fact' is being remembered", 7 );
		$unforget_args = $fact;
	}

	if ( $self->_unforget_roid($unforget_args) ) {
		push( @msg, "Ok, I remembered $fact" );
	}

	return @msg;
}

# Look for roids. God help you if you find them.
sub search {
	my ( $self, $v ) = @_;
	return undef unless $v->{args} =~ /^$self->{fact_regex}$/;
	my $what = $v->{args};
	my @msg;

	Lucy::debug( "Roids", "search: $what", 7 );
	push( @msg, "Search $what" );

	return @msg;
}

# Show roid history
sub history {
	my ( $self, $v ) = @_;
	return undef unless $v->{args} =~ /^$self->{fact_regex}$/;
	my $what = $v->{args};
	my @msg;

	Lucy::debug( "Lucyroids", "history: $what", 7 );
	push( @msg, "History $what" );

	return @msg;
}

sub irc_public {
	my ( $self, $lucy, $who, $where, $what ) =
	  @_[ OBJECT, SENDER, ARG0, ARG1, ARG2 ];
	my $nick = ( split( /[@!]/, $who, 2 ) )[0];
	my $botnick = $lucy->nick_name();
	$where = $where->[0];

	if ( my ( $fact, $def ) =
		$what =~ /^($self->{fact_regex})\s+((?:$self->{trigger_regex}).+)\s*$/ )
	{
		if ( my $r = $self->_get_roid( { forgotten => 0, fact => $fact } ) ) {
			Lucy::debug( "Roids",
				"irc_public: '$fact' is already in db, not saving", 7 );
		} else {
			$self->_put_roid( $fact, $def, $nick, time );
		}

	} elsif ( my ($fact) = $what =~ /^forget\s+($self->{fact_regex})\s*$/ ) {
		if ( $self->_forget_roid($fact) ) {
			$lucy->yield( privmsg => $where => "$nick: Ok, I forgot $fact" );
		} else {
			Lucy::debug( "Roids", "irc_public: '$fact' has NOT been forgot",
				6 );
		}
	} elsif ( my ( $fact, $key, $val ) =
		$what =~
/^(?:unforget|remember)\s+($self->{fact_regex})\s*(?:(id|who|ts)=(\w+))?$/
	  )
	{
		my $unforget_args;
		if ($key) {
			Lucy::debug( "Roids",
				"irc_public: '$fact' is being remembered with $key=$val", 7 );
			$unforget_args = { fact => $fact, "$key" => $val };
		} else {
			Lucy::debug( "Roids", "irc_public: '$fact' is being remembered",
				7 );
			$unforget_args = $fact;
		}

		if ( $self->_unforget_roid($unforget_args) ) {
			$lucy->yield(
				privmsg => $where => "$nick: Ok, I remembered $fact" );
		}
	} elsif ( my ($fact) = $what =~ /^($self->{fact_regex})\?.*$/ ) {
		if ( my $r = $self->_get_roid($fact) ) {
			unless ( $r->{forgotten} ) {
				my $append =
				  ( $r->{ts} > 0 )
				  ? ': ' . Lucy::timesince( $r->{ts} ) . ' ago'
				  : '';
				$append .= '] id=' . $r->{id};

				$lucy->yield( privmsg => $where => "$nick: $fact "
					  . $r->{definition} . ' ['
					  . $r->{who}
					  . $append );
			}
		}
	}
}

##
## Helper functions
##

sub _forget_roid {
	my $self = shift;
	my $fact = shift;
	Lucy::debug( "Roids", "_forget_roid: $fact", 7 );

	# disabled as both are the same because of defaults in _get_roid
	#	my $where =
	#	  ( UNIVERSAL::isa( $fact, 'HASH' ) )
	#	  ? $fact
	#	  : { forgotten => 0, fact => $fact };
	my $where = $fact;

	if ( my $roid = $self->_get_roid($fact) ) {
		if (
			$Lucy::dbh->update(
				$self->tablename,
				{ forgotten => 1 },
				{ id        => $roid->{id} }
			)
		  )
		{
			return 1;
		}
	}
}

sub _unforget_roid {
	my $self = shift;
	my $fact = shift;
	Lucy::debug( "Roids", "_unforget_roid: $fact", 7 );

	my $where =
	  ( UNIVERSAL::isa( $fact, 'HASH' ) )
	  ? $fact
	  : { fact => $fact };

	if ( my $roid = $self->_get_roid($where) ) {
		if (
			$Lucy::dbh->update(
				$self->tablename,
				{ forgotten => 0 },
				{ id        => $roid->{id} }
			)
		  )
		{
			return 1;
		}
	}
}

sub _get_roid {
	my $self  = shift;
	my $fact  = shift;
	my $grab  = shift || [qw/id fact definition who ts forgotten/];
	my $order = shift || 'ts DESC';
	Lucy::debug( "Roids", "_get_roid: $fact", 7 );

	my $where =
	  ( UNIVERSAL::isa( $fact, 'HASH' ) )
	  ? $fact
	  : { forgotten => 0, fact => $fact };

	if ( my $roid =
		$Lucy::dbh->select( $self->tablename, $grab, $where, $order )->hash )
	{
		return $roid unless $roid->{definition} eq 'is ignored';
	}
}

sub _search_roids {
	my $self  = shift;
	my $fact  = shift;
	my $max   = shift || 2;
	my $grab  = shift || [qw/id fact definition who ts forgotten/];
	my $order = shift || 'ts DESC';
	Lucy::debug( "Roids", "_get_roid: $fact", 7 );

	my $where =
	  ( UNIVERSAL::isa( $fact, 'HASH' ) )
	  ? $fact
	  : { forgotten => 0, fact => { like => $fact } };

	if ( my $roid =
		$Lucy::dbh->select( $self->tablename, $grab, $where, $order )->hashes )
	{
		return $roid;
	}
}

sub _put_roid {
	my $self = shift;
	my (%r);
	$r{fact}       = shift || return;
	$r{definition} = shift || return;
	$r{who}        = shift || return;
	$r{ts}         = shift || return;
	$r{forgotten}  = shift || 0;
	Lucy::debug( "Roids", "_put_roid: $r{fact}", 7 );

	$Lucy::dbh->insert( $self->tablename, \%r );
}

sub _roid_exists {
	my $self  = shift;
	my $fact  = shift;
	my $grab  = shift || [qw/id/];
	my $order = shift;
	Lucy::debug( "Roids", "_roid_exists: $fact", 7 );

	my $where =
	  ( UNIVERSAL::isa( $fact, 'HASH' ) )
	  ? $fact
	  : { forgotten => 0, fact => $fact };

	if ( my $roid =
		$Lucy::dbh->select( $self->tablename, $grab, $where, $order ) )
	{
		return 1;
	}
}

1;