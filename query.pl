#
# Copyright (C) 2001-2002 by Peder Stray <peder@ninja.no>
#

use strict;
use Irssi;

# ======[ Script Header ]===============================================

use vars qw{$VERSION %IRSSI};
($VERSION) = '$Revision: 1.5 $' =~ / (\d+\.\d+) /;
%IRSSI = (
	  name	      => 'query',
	  authors     => 'Peder Stray',
	  contact     => 'peder@ninja.no',
	  url	      => 'http://ninja.no/irssi/query.pl',
	  license     => 'GPL',
	  description => 'Give you more control over when to jump to query windows and when to just tell you one has been created.',
	 );

# ======[ Variables ]===================================================

my($own);

# ======[ Signal Hooks ]================================================

# --------[ sig_message_own_private ]-----------------------------------

sub sig_message_own_private {
    my($server,$msg,$nick,$orig_target) = @_;
    $own = $nick;
}

# --------[ sig_message_private ]---------------------------------------

sub sig_message_private {
    my($server,$msg,$nick,$addr) = @_;
    undef $own;
}

# --------[ sig_query ]-------------------------------------------------

sub sig_query {
    my ($query, $auto) = @_;
    my $qwin = $query->window();
    my $awin = Irssi::active_win();

    if ($auto && $qwin->{refnum} != $awin->{refnum}) {
	if ($own eq $query->{name}) {
	    if (Irssi::settings_get_bool('query_autojump_own')) {
		$qwin->set_active();
	    } else {
		$awin->printformat(MSGLEVEL_CLIENTCRAP, 'auto_query_message',
				     $query->{name}, $qwin->{refnum})
		  if Irssi::settings_get_bool('query_noisy');
	    }
	} else {
	    if (Irssi::settings_get_bool('query_autojump')) {
		$qwin->set_active();
	    } else {
		$awin->printformat(MSGLEVEL_CLIENTCRAP, 'auto_query_message',
				     $query->{name}, $qwin->{refnum})
		  if Irssi::settings_get_bool('query_noisy');
	    }
	}
    }
    undef $own;
}

# ======[ Setup ]=======================================================

# --------[ Register settings ]-----------------------------------------

Irssi::settings_add_bool('query', 'query_autojump_own', 1);
Irssi::settings_add_bool('query', 'query_autojump', 0);
Irssi::settings_add_bool('query', 'query_noisy', 1);

# --------[ Register formats ]------------------------------------------

Irssi::theme_register(
[
 'auto_query_message',
 '{line_start}{hilight Query:} started with {nick $0} in window $1',
]);

# --------[ Register signals ]------------------------------------------

Irssi::signal_add_last('query created', 'sig_query');
Irssi::signal_add_last('message private', 'sig_message_private');
Irssi::signal_add_last('message own_private', 'sig_message_own_private');

# ======[ END ]=========================================================

# Local Variables:
# header-initial-hide: t
# mode: header-minor
# end:
