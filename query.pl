#
# Copyright (C) 2001-2002 by Peder Stray <peder@ninja.no>
#

use strict;
use Irssi 20020428.1608;

use Text::Abbrev;
use POSIX;

use Data::Dumper;

# ======[ Script Header ]===============================================

use vars qw{$VERSION %IRSSI};
($VERSION) = '$Revision: 1.12 $' =~ / (\d+\.\d+) /;
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

my(%state);		# used for tracking idletime and state
my(%defaults);		# used for storing defaults
my($query_opts) = {};	# stores option abbrevs

# ======[ Helper functions ]============================================

# --------[ load_defaults ]---------------------------------------------

sub load_defaults {
    my $file = Irssi::get_irssi_dir."/query";
    local *FILE;

    %defaults = ();
    open FILE, "< $file";
    while (<FILE>) {
	my($mask,$maxage,$immortal) = split;
	$defaults{$mask}{maxage}   = $maxage;
	$defaults{$mask}{immortal} = $immortal;
    }
    close FILE;
}

# --------[ save_defaults ]---------------------------------------------

sub save_defaults {
    my $file = Irssi::get_irssi_dir."/query";
    local *FILE;

    open FILE, "> $file";
    for (keys %defaults) {
	my $d = $defaults{$_};
	print FILE join("\t", $_,
			exists $d->{maxage} ? $d->{maxage} : -1,
			exists $d->{immortal} ? $d->{immortal} : -1,
		       ), "\n";
    }
    close FILE;
}

# --------[ sec2str ]---------------------------------------------------

sub sec2str {
    my($sec) = @_;
    my($ret);
    use integer;

    $ret = ($sec%60)."s ";
    $sec /= 60;

    $ret = ($sec%60)."m ".$ret;
    $sec /= 60;

    $ret = ($sec%24)."h ".$ret;
    $sec /= 24;

    $ret = $sec."d ".$ret;

    $ret =~ s/\b0[dhms] //g;
    $ret =~ s/ $//;

    return $ret;
}

# --------[ set_defaults ]----------------------------------------------

sub set_defaults {
    my($serv,$nick,$address) = @_;
    my $net = lc $serv->{chatnet};

    return unless $address;
    $state{$net}{$nick}{address} = $address;

    for my $mask (sort {userhost_cmp($serv,$a,$b)}keys %defaults) {
	if ($serv->mask_match_address($mask, $nick, $address)) {
	    for my $key (keys %{$defaults{$mask}}) {
		$state{$net}{$nick}{$key} = $defaults{$mask}{$key}
		  if $defaults{$mask}{$key} >= 0;
	    }
	}
    }
}

# --------[ time2str ]--------------------------------------------------

sub time2str {
    my($time) = @_;
    return strftime("%c", localtime $time);
}

# --------[ userhost_cmp ]----------------------------------------------

sub userhost_cmp {
    my($serv, $am, $bm) = @_;
    my($an,$aa) = split "!", $am;
    my($bn,$ba) = split "!", $bm;
    my($t1,$t2);

    $t1 = $serv->mask_match_address($bm, $an, $aa);
    $t2 = $serv->mask_match_address($am, $bn, $ba);

    return $t1 - $t2 if $t1 || $t2;

    $an = $bn = '*';
    $am = "$an!$aa";
    $bm = "$bn!$ba";

    $t1 = $serv->mask_match_address($bm, $an, $aa);
    $t2 = $serv->mask_match_address($am, $bn, $ba);

    return $t1 - $t2 if $t1 || $t2;

    for ($am, $bm, $aa, $ba) {
	s/(\*!)?[^*]*@/$1*/;
    }

    $t1 = $serv->mask_match_address($bm, $an, $aa);
    $t2 = $serv->mask_match_address($am, $bn, $ba);

    return $t1 - $t2 if $t1 || $t2;

    return 0;

}

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

# --------[ sig_query_address_changed ]---------------------------------

sub sig_query_address_changed {
    my($query) = @_;

    set_defaults($query->{server}, $query->{name}, $query->{address});

}

# --------[ sig_query_created ]-----------------------------------------

sub sig_query_created {
    my ($query, $auto) = @_;
    my $qwin = $query->window();
    my $awin = Irssi::active_win();

    my $serv = $query->{server};
    my $nick = $query->{name};
    my $net  = lc $serv->{chatnet};

    if ($auto && $qwin->{refnum} != $awin->{refnum}) {
	if ($own eq $query->{name}) {
	    if (Irssi::settings_get_bool('query_autojump_own')) {
		$qwin->set_active();
	    } else {
		$awin->printformat(MSGLEVEL_CLIENTCRAP, 'query_created',
				   $nick, $qwin->{refnum})
		  if Irssi::settings_get_bool('query_noisy');
	    }
	} else {
	    if (Irssi::settings_get_bool('query_autojump')) {
		$qwin->set_active();
	    } else {
		$awin->printformat(MSGLEVEL_CLIENTCRAP, 'query_created',
				   $nick, $qwin->{refnum})
		  if Irssi::settings_get_bool('query_noisy');
	    }
	}
    }
    undef $own;

    $state{$net}{$nick} = { time => time };

    $serv->redirect_event('userhost', 1, ":$nick", -1, undef,
			  {
			   "event 302" => "redir query userhost",
			   "" => "event empty",
			  });
    $serv->send_raw("USERHOST :$nick");

}

# --------[ sig_query_destroyed ]---------------------------------------

sub sig_query_destroyed {
    my($query) = @_;

    delete $state{lc $query->{server}{chatnet}}{$query->{name}};
}


# --------[ sig_query_nick_changed ]------------------------------------

sub sig_query_nick_changed {
    my($query,$old_nick) = @_;
    my($net) = lc $query->{server}{chatnet};

    $state{$net}{$query->{name}} = delete $state{$net}{$old_nick};
}

# --------[ sig_redir_query_userhost ]----------------------------------

sub sig_redir_query_userhost {
    my($serv,$data) = @_;

    $data =~ s/^\S*\s*://;
    for (split " ", $data) {
	if (/([^=*]+)\*?=.(.+)/) {
	    set_defaults($serv, $1, $2);
	}
    }
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

    my($defmax) = Irssi::settings_get_int('query_autoclose');
    my($minage) = Irssi::settings_get_int('query_autoclose_grace');
    my($win)    = Irssi::active_win;

    for my $query (@queries) {
	my $net    = lc $query->{server}{chatnet};
	my $name   = $query->{name};
	my $state  = $state{$net}{$name};

	my $age    = time - $state->{time};
	my $maxage = $defmax;

	$maxage = $state->{maxage} if defined $state->{maxage};

	# skip the ones we have marked as immortal
	next if $state->{immortal};

	# maxage = 0 means we have disabled autoclose
	next unless $maxage;

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

    my(@params,@opts,$query,$net,$nick);
    my($state,$info,$save);

    while (@data) {
	my $param = shift @data;

	if ($param =~ s/^-//) {
	    my $opt = $query_opts->{lc $param};

	    if ($opt) {

		if ($opt eq 'window') {
		    push @opts, $param;

		} elsif ($opt eq 'immortal') {
		    $state->{immortal} = 1;

		} elsif ($opt eq 'info') {
		    $info = 1;

		} elsif ($opt eq 'mortal') {
		    $state->{immortal} = 0;

		} elsif ($opt eq 'timeout') {
		    $state->{maxage} = shift @data;

		} elsif ($opt eq 'save') {
		    $save++;

		} else {
		    # unhandled known opt

		}

	    } elsif ($net = Irssi::chatnet_find($param)) {
		$net = $net->{name};
		push @opts, "-$net";

	    } else {
		# bogus opt...
		push @opts, "-$param";

	    }

	} else {
	    # normal parameter
	    push @params, $param;

	}
    }

    if (@params) {
	Irssi::signal_continue("@opts @params",$server,$witem);

	# find the query...
	my $serv = Irssi::server_find_chatnet($net || $server->{chatnet});
	return unless $serv;
	$query = $serv->window_item_find($params[0]);

    } else {

	if ($witem && $witem->{type} eq 'QUERY') {
	    $query = $witem;
	}

    }

    if ($query) {
	$nick = $query->{name};
	$net  = lc $query->{server}{chatnet};

	my $opts;
	for (keys %$state) {
	    $state{$net}{$nick}{$_} = $state->{$_};
	    $opts++;
	}

	$state = $state{$net}{$nick};

	if ($info) {
	    Irssi::signal_stop();
	    my(@items,$key,$val);

	    my $timeout = Irssi::settings_get_int('query_autoclose');
	    $timeout = $state->{maxage} if defined $state->{maxage};

	    if ($timeout) {
		$timeout .= " (".sec2str($timeout).")";
	    } else {
		$timeout .= " (Off)";
	    }

	    @items = (
		      Server   => $net,
		      Nick     => $nick,
		      Address  => $state->{address},
		      Created  => time2str($query->{createtime}),
		      Immortal => $state->{immortal}?'Yes':'No',
		      Timeout  => $timeout,
		      Idle     => sec2str(time - $state->{time}),
		     );

	    $query->printformat(MSGLEVEL_CLIENTCRAP, 'query_info_header');
	    while (($key,$val) = splice @items, 0, 2) {
		$query->printformat(MSGLEVEL_CLIENTCRAP, 'query_info',
				    $key, $val);
	    }
	    $query->printformat(MSGLEVEL_CLIENTCRAP, 'query_info_footer');

	    return;
	}

	if ($save) {
	    Irssi::signal_stop;

	    unless ($state->{address}) {
		$query->printformat(MSGLEVEL_CLIENTCRAP,
				    'query_crap', 'This query has no address yet');
		return;
	    }

	    my $mask = Irssi::Irc::get_mask($nick, $state->{address},
					    Irssi::Irc::MASK_USER |
					    Irssi::Irc::MASK_DOMAIN
					   );

	    for (qw(immortal maxage)) {
		if (exists $state->{$_}) {
		    $defaults{$mask}{$_} = $state->{$_};
		} else {
		    delete $defaults{$mask}{$_};
		}
	    }

	    save_defaults;

	    return;
	}

	if (!@params && ($opts || $state{$net}{$nick}{immortal})) {
	    Irssi::signal_stop;

	    return if $opts;

	    $witem->printformat(MSGLEVEL_CLIENTCRAP,
				'query_crap', 'This query is immortal');
	}

    }

}

# ======[ Setup ]=======================================================

# --------[ Register commands ]-----------------------------------------

Irssi::command_bind('query', 'cmd_query');
Irssi::command_set_options('query', 'immortal mortal info save +timeout');
abbrev $query_opts, qw(window immortal mortal info save timeout);

#Irssi::command_bind('debug', sub { print Dumper \%state });

# --------[ Register formats ]------------------------------------------

Irssi::theme_register(
[
 'query_created',
 '{line_start}{hilight Query:} started with {nick $0} in window $1',

 'query_closed',
 '{line_start}{hilight Query:} closed with {nick $0}',

 'query_info_header', '',

 'query_info_footer', '',

 'query_crap',
 '{line_start}{hilight Query:} $0',

 'query_warn',
 '{line_start}{hilight Query:} {error Warning:} $0',

 'query_info',
 '%#$[8]0: $1',

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

Irssi::signal_add('query address changed', 'sig_query_address_changed');
Irssi::signal_add('query destroyed', 'sig_query_destroyed');
Irssi::signal_add('query nick changed', 'sig_query_nick_changed');

Irssi::signal_add('redir query userhost', 'sig_redir_query_userhost');

Irssi::signal_add('session save', 'sig_session_save');
Irssi::signal_add('session restore', 'sig_session_restore');

# --------[ Register timers ]-------------------------------------------

Irssi::timeout_add(5000, 'check_queries', undef);

# ======[ Initialization ]==============================================

for my $query (Irssi::queries) {
    my($net)  = lc $query->{server}{chatnet};
    my($nick) = $query->{name};

    $state{$net}{$nick}{time}
      = (sort $query->{last_unread_msg}, $query->{createtime}, time)[0];

    set_defaults($query->{server}, $nick, $query->{address});
}

load_defaults;

if (Irssi::settings_get_int("autoclose_query")) {
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'query_warn',
		       "autoclose_query is set, please set to 0");
}

# ======[ END ]=========================================================

# Local Variables:
# header-initial-hide: t
# mode: header-minor
# end:
