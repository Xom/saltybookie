#!/usr/bin/perl
use strict;
use warnings;

use lib '/home/frobozz/perl5/lib/perl5';
use Text::CSV;
use String::Approx 'amatch';

my $version = '4.1';
Xchat::register 'SALTY', $version, '', '';
my $status = 0; #loading success flag

my $ratings_file = '/home/frobozz/xom_bot/ratings.noheader.csv';

# 0 name
# 1 id
# 2 wincount
# 3 losscount
# 4 rating
# 5 bestwin
# 6 worstloss
# 7 wellrated (0 = no; 1 = yes)
# 8 deviance (measure of variance in past performance)

my @rows;
my $csv;
if ($csv = Text::CSV->new ( { binary => 1 } )) {
    $status = 1;
} else {
    Xchat::print 'Cannot use CSV: '.Text::CSV->error_diag();
}

if ($status) {
    open my $fh, '<:encoding(utf8)', $ratings_file or Xchat::print "$ratings_file: $!";
    while ( my $row = $csv->getline( $fh ) ) {
        push @rows, $row;
    }
    if ($csv->eof) {
        $status = 2;
    } else {
        $status = 0;
        Xchat::print $csv->error_diag();
    }
    close $fh;
}

my %cooldown;
my %iddict;
my @names;
if ($status) {
    for (my $i = 0; $i < @rows; $i++) {
        $iddict{$rows[$i][0]} = $rows[$i][1];
    }
    @names = keys %iddict;

    # start listener
    Xchat::hook_print('Channel Message', \&chanmsg);
    Xchat::print "-- SALTY v$version loaded successfully.";
} else {
    Xchat::print "-- SALTY v$version failed to load! status: $status";
}

# main handler
sub chanmsg {
    my $channel = Xchat::get_info 'channel';
    my $chatter = Xchat::strip_code $_[0][0];
    my $message = lc(Xchat::strip_code($_[0][1]));
    chanmsgaux($channel, $chatter, $message);
}

sub chanmsgaux {
    my $channel = shift;
    my $chatter = shift;
    my $message = shift;
    # use nick Xom_bot because xchat intercepts messages containing nick!
    if ((substr($message, 0, 4) eq '!xb ') || (substr($message, 0, 4) eq '~xb ')) {
        $message = trim(substr($message, 4));
        my $comma = index($message, ',');
        if ($comma == -1) {
            pstatblock($channel, $message);
        } else {
            my $red = pstatblock($channel, trim(substr($message, 0, $comma)));
            my $blue = pstatblock($channel, trim(substr($message, $comma + 1)));
            if ($red && $blue) {
                pcooldown("$red,$blue", $channel, matchup($red, $blue));
            }
        }
    } elsif (substr($message, 0, 8) eq '!xombot ') {
        chanmsgaux($channel, $chatter, '!xb '.trim(substr($message, 8)));
    } elsif ($channel eq '#saltybet') {
        if ($chatter eq 'Peppermill') {
            my @peppers = split(/\|/, $message);
            my $i = index($peppers[0], ': [e:');
            if ($i == -1) {
                $i = index($peppers[0], 'was not found in the database. check your spelling!');
            }
            if ($i != -1) {
                my $j = index($peppers[1], ': [e:');
                if ($j == -1) {
                    $j = index($peppers[1], 'was not found in the database. check your spelling!');
                }
                if ($j != -1) {
                    Xchat::command 'msg #saltyfart --';
                    chanmsgaux('#saltyfart', $chatter, '!xb '.substr($peppers[0], 0, $i).','.substr($peppers[1], 0, $j));
                } else {
                    chanmsgaux('#saltyfart', $chatter, '!xb '.substr($peppers[0], 0, $i));
                }
            }
        } elsif ((substr($message, 0, 3) eq '`s ') || (substr($message, 0, 3) eq '?s ')) {
            chanmsgaux('#saltyfart', $chatter, '!xb '.trim(substr($message, 3)));
        } elsif(substr($message, 0, 6) eq '!goku ') {
            chanmsgaux('#saltyfart', $chatter, '!xb '.trim(substr($message, 6)));
        }
    }
}

sub pcooldown {
    my $k = shift;
    my $channel = shift;
    my $message = shift;
    $k .= $channel;
    if (!(exists $cooldown{$k})) {
        $cooldown{$k} = Xchat::hook_timer 40000, 'uncooldown', $k;
        Xchat::command "msg $channel $message";
    }
}

sub uncooldown {
    my $k = $_[0];
    Xchat::unhook $cooldown{$k};
    delete $cooldown{$k};
}

sub pstatblock {
    my $channel = shift;
    my $message = shift;
    if (exists $iddict{$message}) {
        my $id = $iddict{$message};
        pcooldown($id, $channel, statblock($id));
        return $id;
    }
    my @matches = amatch($message, [sprintf('%d', (length($message) / 5) + 0.3)], @names);
    if (@matches == 1) {
        my $id = $iddict{$matches[0]};
        pcooldown($id, $channel, statblock($id));
        return $id;
    }
    if (@matches > 1) {
        my $suggests = join(', ', @matches);
        if (substr($suggests, 0, 400) ne $suggests) {
            pcooldown($message, $channel, 'did you mean: '.substr($suggests, 0, 400).'...');
        } else {
            pcooldown($message, $channel, "did you mean: $suggests");
        }
    } else {
        pcooldown($message, $channel, "no clue on $message");
    }
    return 0;
}

sub statblock {
    my $id = shift;
    my $bwin = bestwin($id);
    my $wloss = worstloss($id);
    my $sblock = sprintf('%+.1f', rating($id));
    if ((wellrated($id) == 0) || (rating($wloss) - rating($bwin) > 5)) {
        $sblock .= '?';
    }
    $sblock = sprintf('%s[%s; 3%dW 5%dL', ucfirst(name($id)), $sblock, wincount($id), losscount($id));
    if ($bwin) {
        $sblock .= '; best win was vs. '.statsub($bwin, 1);
    }
    if ($wloss) {
        $sblock .= '; worst loss was vs. '.statsub($wloss, -1);
    }
    return "$sblock]";
}

sub statsub {
    my $id = shift;
    my $depth = shift;
    my $bwin = bestwin($id);
    my $wloss = worstloss($id);
    my $dubious = ((wellrated($id) == 0) || (rating($wloss) - rating($bwin) > 5 + abs($depth)));
    my $sblock = sprintf('%+.1f', rating($id));
    if ($dubious) {
        $sblock .= '?';
    }
    $sblock = sprintf('%s(%s, %d-%d', ucfirst(name($id)), $sblock, wincount($id), losscount($id));
    if ($dubious && (abs($depth) < 3)) {
        if ($bwin && ($depth >= 0)) {
            $sblock .= ', best win: '.statsub($bwin, $depth + 1);
        }
        if ($wloss && ($depth <= 0)) {
            $sblock .= ', worst loss: '.statsub($wloss, $depth - 1);
        }
    }
    return "$sblock)";
}

sub matchup {
    my $red = shift;
    my $blue = shift;
    my $rdubious = ((wellrated($red) == 0) || (rating(worstloss($red)) - rating(bestwin($red)) > 5));
    my $bdubious = ((wellrated($blue) == 0) || (rating(worstloss($blue)) - rating(bestwin($blue)) > 5));
    my $rrating = sprintf('%+.1f', rating($red));
    my $brating = sprintf('%+.1f', rating($blue));
    if ($rdubious) {
        $rrating .= '?';
    }
    if ($bdubious) {
        $brating .= '?';
    }
    my $predwin;
    my $ratio;
    if (abs(rating($red) - rating($blue)) < 0.001) {
        $predwin = 0.5;
        $ratio = '1:1';
    } else {
        $predwin = 1 / (1 + exp(rating($blue) - rating($red)));
        $predwin = ($predwin * 665 + 1) / 667;
        $ratio = $predwin > 0.5 ? ('3'.oddsfmt($predwin / (1 - $predwin)).':1') : ('1:3'.oddsfmt((1 - $predwin) / $predwin).'');
    }
    return sprintf((($rdubious || $bdubious) ?
        'MATCHUP: %s[%s, 3%d-5%d] ~ %.1f%%? vs. %.1f%%? ~ %s[%s, 3%d-5%d]; %.3f:%.3f? = %s?'
        : 'MATCHUP: %s[%s, 3%d-5%d] ~ %.1f%% vs. %.1f%% ~ %s[%s, 3%d-5%d]; %.3f:%.3f = %s'),
        ($predwin > 0.5 ? ('*3'.uc(name($red)).'*') : ucfirst(name($red))),
        $rrating, wincount($red), losscount($red),
        ($predwin * 100), 100 - ($predwin * 100),
        ($predwin < 0.5 ? ('*3'.uc(name($blue)).'*') : ucfirst(name($blue))),
        $brating, wincount($blue), losscount($blue),
        $predwin, 1 - $predwin, $ratio);
}

sub oddsfmt {
    my $odds = shift;
    if ($odds < 10) {
        return sprintf('%.1f', $odds);
    }
    if ($odds < 35) {
        return sprintf('%d', $odds);
    }
    if ($odds < 100) {
        return sprintf('%d0', ($odds + 5) / 10);
    }
    if ($odds < 633) {
        return sprintf('%d00', ($odds + 50) / 100);
    }
    return '666';
}

sub rowofid {
    my $id = shift;
    return $id - 1;
}

sub name {
    my $id = shift;
    return $rows[rowofid($id)][0];
}

sub wincount {
    my $id = shift;
    return $rows[rowofid($id)][2];
}

sub losscount {
    my $id = shift;
    return $rows[rowofid($id)][3];
}

sub rating {
    my $id = shift;
    return $rows[rowofid($id)][4];
}

sub bestwin {
    my $id = shift;
    return $rows[rowofid($id)][5];
}

sub worstloss {
    my $id = shift;
    return $rows[rowofid($id)][6];
}

sub wellrated {
    my $id = shift;
    return $rows[rowofid($id)][7];
}

# http://perlmonks.org/?node_id=36684
sub trim {
    @_ = $_ if not @_ and defined wantarray;
    @_ = @_ if defined wantarray;
    for (@_ ? @_ : $_) { s/^\s+//, s/\s+$// }
    return wantarray ? @_ : $_[0] if defined wantarray;
}

