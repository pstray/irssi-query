#
# Copyright (C) 2001-2002 by Peder Stray <peder@ninja.no>
#

use strict;
use Irssi 20020428.1608;

use Data::Dumper;

# ======[ Script Header ]===============================================

use vars qw{$VERSION %IRSSI};
($VERSION) = '$Revision: 1.7 $' =~ / (\d+\.\d+) /;
%IRSSI = (
	  name	      => 'query',
	  authors     => 'Peder Stray',
	  contact     => 'peder@ninja.no',
	  url	      => 'http://ninja.no/irssi/query.pl',
	  license     => 'GPL',
	  description => 'Give you more control over when to jump to query windows and when to just tell you one has been created. Enhanced autoclose.',
	 );

# ======[ Variables ]===================================================

my($own);

my(%state);		# used for tracking idletime

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

# --------[ sig_print_message ]-----------------------------------------

sub sig_print_message {
    my($dest, $text, $strip) = @_;

    return unless $dest->{level} & MSGLEVEL_MSGS;

    my $server = $dest->{server};
    my $witem  = $server->window_item_find($dest->{target});
    my $net    = lc $server->{chatnet};

    next unless $witem->{type} eq 'QUERY';

    $state{$net}{$witem->{name}}{time} = time;
}

# --------[ sig_query_created ]-----------------------------------------

sub sig_query_created {
    my ($query, $auto) = @_;
    my $qwin = $query->window();
    my $awin = Irssi::active_win();

    if ($auto && $qwin->{refnum} != $awin->{refnum}) {
	if ($own eq $query->{name}) {
	    if (Irssi::settings_get_bool('query_autojump_own')) {
		$qwin->set_active();
	    } else {
		$awin->printformat(MSGLEVEL_CLIENTCRAP, 'query_created',
				   $query->{name}, $qwin->{refnum})
		  if Irssi::settings_get_bool('query_noisy');
	    }
	} else {
	    if (Irssi::settings_get_bool('query_autojump')) {
		$qwin->set_active();
	    } else {
		$awin->printformat(MSGLEVEL_CLIENTCRAP, 'query_created',
				   $query->{name}, $qwin->{refnum})
		  if Irssi::settings_get_bool('query_noisy');
	    }
	}
    }
    undef $own;
}

# --------[ sig_query_nick_changed ]------------------------------------

sub sig_query_nick_changed {
    my($query,$old_nick) = @_;
    my($net) = lc $query->{server}->{chatnet};

    $state{$net}{$query->{name}} = delete $state{$net}{$old_nick};
}

# --------[ sig_session_restore ]---------------------------------------

sub sig_session_restore {
    open STATE, sprintf "< %s/query.state", Irssi::get_irssi_dir;
    while (<STATE>) {
	chomp;
	my($net,$nick,%data) = split "\t";
	$state{$net}{$nick} = \%data;
    }
    close STATE;
}

# --------[ sig_session_save ]------------------------------------------

sub sig_session_save {
    open STATE, sprintf "> %s/query.state", Irssi::get_irssi_dir;
    for my $net (keys %state) {
	for my $nick (keys %{$state{$net}}) {
	    print STATE join("\t",$net,$nick,%{$state{$net}{$nick}}), "\n";
	}
    }
    close STATE;
}

# ======[ Timers ]======================================================

# --------[ check_queries ]---------------------------------------------

sub check_queries {
    my(@queries) = Irssi::queries;
    my($query, $net, $name, $age);

    my($maxage) = Irssi::settings_get_int('query_autoclose');
    my($minage) = Irssi::settings_get_int('query_autoclose_grace');
    my($win) = Irssi::active_win;

    return unless $maxage;

    for $query (@queries) {
	$net    = lc $query->{server}->{chatnet};
	$name   = $query->{name};
	$age    = time - $state{$net}{$name}{time};

	# not old enough
	next if $age < $maxage;

	# unseen messages
	next if $query->{data_level} > 1;

	# active window
	next if $query->is_active &&
	  $query->window->{refnum} == $win->{refnum};

	# graceperiod
	next if time - $query->{last_unread_msg} < $minage;

	# kill it off
	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'query_closed',
			   $query->{name})
	    if Irssi::settings_get_bool('query_noisy');
	$query->destroy;

    }
}

# ======[ Commands ]====================================================

# --------[ cmd_query ]-------------------------------------------------

sub cmd_query {
    my($data,$server,$witem) = @_;
    my(@data) = split " ", $data;
    my(@param,$gotparam);
    my($immortal,$info,$timeout);

    # -immortal
    # -info
    # -mortal
    # -timeout <secs>

    while (@data) {
	$_ = shift @data;

	if (/^-immortal$/) {
	    $gotparam++;
	    $immortal = 1;

	} elsif (/^-info$/) {
	    $gotparam++;
	    $info = 1;

	} elsif (/^-mortal$/) {
	    $gotparam++;
	    $immortal = 0;

	} elsif (/^-timeout/) {
	    $gotparam++;
	    $timeout = shift @data;

	} else {
	    push @param, $_;
	}
    }



    if ($gotparam && !@param) {
	print "Stopping /QUERY";
	Irssi::signal_stop();
	return;
    }

    print "Continue /QUERY @param";
    Irssi::signal_continue("@param",$server,$witem);

    print "Back /QUERY";
}

# ======[ Setup ]=======================================================

# --------[ Register commands ]-----------------------------------------

Irssi::command_bind('query', 'cmd_query');

Irssi::command_bind('debug', sub { print Dumper \%state });

# --------[ Register formats ]------------------------------------------

Irssi::theme_register(
[
 'query_created',
 '{line_start}{hilight Query:} started with {nick $0} in window $1',

 'query_closed',
 '{line_start}{hilight Query:} closed with {nick $0}',
]);

# --------[ Register settings ]-----------------------------------------

Irssi::settings_add_bool('query', 'query_autojump_own', 1);
Irssi::settings_add_bool('query', 'query_autojump', 0);
Irssi::settings_add_bool('query', 'query_noisy', 1);

Irssi::settings_add_int('query', 'query_autoclose', 0);
Irssi::settings_add_int('query', 'query_autoclose_grace', 300);

# --------[ Register signals ]------------------------------------------

Irssi::signal_add_last('message own_private', 'sig_message_own_private');
Irssi::signal_add_last('message private', 'sig_message_private');
Irssi::signal_add_last('query created', 'sig_query_created');

Irssi::signal_add('print text', 'sig_print_message');
Irssi::signal_add('query nick changed', 'sig_query_nick_changed');
Irssi::signal_add('session save', 'sig_session_save');
Irssi::signal_add('session restore', 'sig_session_restore');

# --------[ Register timers ]-------------------------------------------

Irssi::timeout_add(5000, 'check_queries', undef);

# ======[ Initialization ]==============================================

for my $query (Irssi::queries) {
    my($net) = lc $query->{server}->{chatnet};

    $state{$net}{$query->{name}}{time}
      = (sort $query->{last_unread_msg}, $query->{createtime}, time)[0];
}

# ======[ END ]=========================================================

# Local Variables:
# header-initial-hide: t
# mode: header-minor
# end:
