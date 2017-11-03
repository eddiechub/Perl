#!/usr/bin/perl
# File format is <ric> <purchase price> <quantity1> [<quantity2>]

use strict;
use warnings;
use English;
use POSIX qw(strftime);
use LWP::UserAgent;
use HTTP::Status;
use HTTP::Request::Common qw(GET);
use Text::ParseWords;
# use File::Temp qw(tempfile tempdir);
use File::Temp qw(:POSIX);

my $use_yahoo = 1;
my $printer_mode = 0;
my $highlight = 0;
my $verbose = 0;
my $do_wide = 0;
my $fids = q(1,3,6,11,12,13,32,90,91,21,120,154,22,25,60,61,62,63,203,204,205,206,967);

#my $source = q(IDN_RDF);
my $source = $ENV{SSL_SOURCE_NAME} || q(IDN_RDF);

# method 1
#my $tempdir = tempdir(CLEANUP => 1);
#my $outfile = $tempdir.qq(/out$$);
#my $errfile = $tempdir.qq(/err$$);
#my $badfile = $tempdir.qq(/bad$$);

# method 2
#my $outfile = tempfile("stkXXXX",SUFFIX=>"out");
#my $errfile = tempfile("stkXXXX",SUFFIX=>"err");
#my $badfile = tempfile("stkXXXX",SUFFIX=>"bad");

# method 3
my $outfile = tmpnam();
my $errfile = tmpnam();
my $badfile = tmpnam();

print "outfile=$outfile errfile=$errfile badfile=$badfile\n" if $verbose > 1;

my $delim1 = q(:);
my $delim2 = q(#);
my $freargs = q(-Fc3 -d).$delim1.$delim2;
$freargs .= qq( -e$errfile -b$badfile -o$outfile);
# $freargs .= q( -Ss_name_1);
my $basedir = $ENV{"HOME"} || ".";
my $exedir = $basedir . q(/bin);
my $fre = qq($exedir/sslfre $freargs);

#my $os_type = qx(uname);
my $os_type = $^O;
print $os_type."\n" if $verbose > 1;

#my $headerhighlight = ($os_type =~ /Linux/) ? 5 : 1;
my $headerhighlight = ($os_type =~ /Linux/i) ? 1 : 1;
my $rowhighlight1   = ($os_type =~ /Linux/i) ? 36 : 4;
my $rowhighlight2   = ($os_type =~ /Linux/i) ? 33 : 4;
my $uphighlight     = ($os_type =~ /Linux/i) ? 30 : 4;
my $downhighlight   = ($os_type =~ /Linux/i) ? 31 : 4;
my $cashhighlight   = ($os_type =~ /Linux/i) ? 32 : 4;

#sub modeon { my $mode = shift; printf("\033[%dm",$mode) unless $printer_mode or $os_type eq "MSWin32"; }
sub modeon { my $mode = shift; printf("\033[%dm",$mode) unless $printer_mode or !defined $ENV{TERM}; }
sub modeoff { print("\033[0m") unless $printer_mode or !defined $ENV{TERM}; }

my $hour = (localtime)[2];
my $minute = (localtime)[1];
my $day = (localtime)[6]; # 0..6
my $month = (localtime)[4]; # used to get future contract month
my $mday = (localtime)[3]; # used to get future contract month
my $year = 1900 + (localtime)[5]; # used to get future contract month
#print "The hour is $hour\n";
my @fmonth_codes = ("F","G","H","J","K","M","N","Q","U","V","X","Z");

$ENV{IPCROUTE} = $basedir . q(/Cmds/ipcroute)
    unless -f "/var/triarch/ipcroute";

# Override the default UserName
$ENV{TRIARCH_USER_NAME}="techarch";

my @FILES = ();

#print "ARGV is \"@ARGV\" ($#ARGV)\n";
#print "FILES is \"@FILES\" ($#FILES)\n";

while ( defined $ARGV[0] and $_ = $ARGV[0], /^-/) {
    #print "$_\n";
    shift and last if /^--$/;
    /^-v/ and $verbose++;
    /^-y/ and ($use_yahoo = 1);
    /^-t/ and ($use_yahoo = 0);
    /^-w/ and ($do_wide = 1);
    /^-p/ and ($printer_mode = 1);
    /^-f/ and ($#ARGV > 0) and shift and push(@FILES,$ARGV[0]);
    shift;
}

push(@FILES, @ARGV);
if ( $#FILES < 0 ) {
    if ( defined $ENV{STK_FILE} ) {
	push(@FILES, $ENV{STK_FILE});
	#print "Pushed STK_FILE $ENV{STK_FILE}\n";
    } else {
	print "No files specified\n";
	#print "#Args: $#ARGV #Files: $#FILES\n";
	exit 0;
    }
}

sub cleanup
{
    unlink($outfile);
    unlink($errfile);
    unlink($badfile);
}

sub strip_quotes
{
    my $str = shift;
    if ( $str ne "" ) {
	chomp $str;
	$str =~ s?N/A?0?;
	$str =~ s/"//g;
	$str =~ s/\r//g;
	$str =~ s/\n//g;
	$str =~ s/^0.00$/0/;
    }
    return $str;
}

foreach my $File ( @FILES ) {
    if ( not defined $File or not -f $File ) {
	print "Skipping \"$File\" -- not readable\n" if defined $File;
	next;
    }

    my $now_string;
    if ( $os_type =~ /linux/i ) {
	$now_string = strftime "%a %b %e %H:%M:%S %Y", localtime;
    } elsif ( $os_type eq "MSWin32" ) {
	$now_string = qx{echo %DATE% %TIME%};
	$now_string =~ s/[\n\r]+//g;
    } elsif ( $os_type =~ /Windows/ ) {
	$now_string = qx{date /T};
	$now_string =~ s/[\n\r]+//g;
    } else {
	$now_string = strftime "%a %b %e %H:%M:%S %Y", localtime;
    }
    print "File: [$File] Time: [$now_string] Source: ".($use_yahoo==1?"Yahoo Finance":"TRIARCH")."\n";

    my %amount1 = ();
    my %amount2 = ();
    my %purchase = ();
    my $cash1 = 0;
    my $cash2 = 0;
    my $has_multiple_quantity = 0;

    #print "$fre\n";
    my $symlist = "";
    if ( !$use_yahoo ) {
	if ( !open(PIPE, "|$fre") ) {
	    cleanup();
	    die "could not run $fre";
	}
    }

    if ( !open(FILE, $File) ) {
	cleanup();
	die "could not open $File: $!";
    }
    while (<FILE>) {
	chop;
	next if $_ =~ /^#/ || $_ =~ /^$/;

	my ($record, $purch, $amt1, $amt2, @rest) = split('\t');

	#if ( $amt1 != 0 and $amt2 != 0 )
	$purch = 0 unless $purch;
	$amt1 = 0 unless $amt1;

	if ( defined $amt2 ) {
	    $has_multiple_quantity = 1;
	}

	if ( $record eq "CASH" ) {
	    $cash1 += $amt1;
	    $cash2 += $amt2;
	} else {
	    if ( $use_yahoo ) {
		# build the url request, hack some symbols
		$symlist .= "+" if length($symlist) > 0;
		# remove suffix, get real ticker
		$record =~ s{^\.}{^};
		$record =~ s{\..*$}{};

		if ( $record =~ /=$/ ) {
		    $record =~ s/^(\w+)=$/${1}USD=/ if $record =~ /EUR|GBP/;
		    $record .= "X";
		} elsif ( $record =~ /([A-Z]+)a/ ) {
		    $record = "${1}-A";
		} elsif ( $record eq "^SPX" ) {
		    $record = "^GSPC";
		} elsif ( $record eq "^DJI" ) {
		    #$record = "INDU";
		    # use the ETF which is around 100x less than dow
		    $record = "DIA";
		} elsif ( $record =~ m/^(\w+)c1$/ ) {
		    # Construct contract month/year
		    # http://finance.yahoo.com/futures?t=metals
		    my $root = $1;
		    my $exch = "NYM"; # default
		    my $fmonth = $month+1;
		    my $fyr = $year % 100;
		    if ( $root =~ /GC|SI|HG/ ) { # Metals
			$exch = "CMX";
			if ( $mday > 25 ) {
			    # get next months contract if late in month
			    ++$fmonth;
			}
		    } elsif ( $root =~ /CL|LCO|RB|NG/ ) { # Energy
			$root = "BZ" if $root eq "LCO";
			$exch = "NYM";
			# get next months contract for energy
			++$fmonth;
			if ( $mday > 25 ) {
			    # get next months contract if late in month
			    ++$fmonth;
			}
		    }

		    # not for all contracts since continuos contract changes at different times
		    if ( $fmonth >= 12 ) {
			++$fyr;
			$fyr=0 if $fyr == 100;
			$fmonth = $fmonth - 12;
		    }

		    $record = $root.$fmonth_codes[$fmonth].sprintf("%02d",$fyr).".".$exch;
		}
		#$record = "^IXIC" if $record eq "^";
		$symlist .= $record;
		#print "Added record=$record\n" if $verbose or $record eq "INDU";
		print "Added record=$record\n" if $verbose > 2;
	    } else {
		print PIPE "$source $record $fids\n";
	    }
	}

	$amount1{$record} = $amt1;
	$amount2{$record} = $amt2;
	$purchase{$record} = $purch;

	if ( $verbose > 1 ) {
	    printf "%s: %d %d %d\n", $record, $purch, $amt1, defined $amt2 ? $amt2 : 0;
	    print "$source $record $fids\n";
	}
    }
    close(FILE);

    if ( $use_yahoo ) { 
        # The format is decoded: (check- http://www.gummy-stuff.org/Yahoo-data.htm)
        # s = symbol  n: Company name  v = volume 
	# l: last value with date/time  l1: (letter l and the number 1) just the last value
	# o = open    p: previous close # p2: change percentage
	# c: the change amount. Can either be used as c or c1.  c6, t5 = change and time but with ECN realtime data
        # c1 = change # t1 = time of last trade # d1 = date of last trade
	# g = day low  j: 52-week low.
	# h = day high k: 52-week high.
	# w: 52-week range # e: EPS (Earning per share) # r: P/E (Prince/Earning) ratio # y: yield
	# d1: current date
	# j1: the market cap. This is string like 42.405B for $42 billion.

	# easy command line test 
	#% curl -s 'http://download.finance.yahoo.com/d/quotes.csv?s=csco&f=l1'

	my $format = "snl1c1vkjhgpw";
	my $url = "http://download.finance.yahoo.com/d/quotes.csv?s=$symlist&f=$format&e=.csv";
	my $quote;
	my $max_tries = 10;
	my $tries = 0;
	my $ua  = LWP::UserAgent->new;
	my $req =  HTTP::Request->new( GET => $url );
	$req->header( Pragma => 'no-cache' );
	while ( $tries < $max_tries ) {
	    ++$tries;
	    my $res = $ua->request($req);
	    $quote = $res->content();
	    last if $res->is_success();
	    warn "Attempt $tries to reach yahoo failed: ".status_message($res->code)."\n" if $verbose;
	}
	die "Could not reach yahoo finance web site ($url) after $tries attempts\n" if $tries == $max_tries;
	chomp $quote;
	if ( $verbose > 1 ) { print "Url=$url\nRet=$quote\n"; }
	$quote =~ s/,RTH/-RTH/;

	# write to outfile
	open OUT, ">$outfile" or die "Can't open $outfile for writing: $!";
	foreach (split /\n/, $quote) {
	    chomp;
	    my @cols = parse_line(",",1,$_);

	    next if !defined $cols[2] or $cols[2] eq "N/A" or $cols[2] == 0;

	    # better reliability with year range
	    my $hl = strip_quotes($cols[10]);
	    my ($yrlow,$yrhigh) = $hl =~ m/^(\S+)\s+-\s+(\S+)$/;
	    $yrlow = "0" unless $yrlow and $yrlow =~ m/^[\d.]+$/;
	    $yrhigh = "0" unless $yrhigh and $yrhigh =~ m/^[\d.]+$/;
	    if ( $verbose > 2 ) {
		print "HILO=[$yrhigh $yrlow] (".strip_quotes($cols[10]).")\n";
	    }

	    # make it look like the FRE
	    my $sym = strip_quotes($cols[0]);
	    my $outstr =
		  "3".$delim1.strip_quotes($cols[1]).$delim2
		. "6".$delim1.strip_quotes($cols[2]).$delim2
		. "11".$delim1.strip_quotes($cols[3]).$delim2
		. "32".$delim1.strip_quotes($cols[4]).$delim2
		#. "90".$delim1.strip_quotes($cols[5]).$delim2
		#. "91".$delim1.strip_quotes($cols[6]).$delim2
		. "90".$delim1.$yrhigh.$delim2
		. "91".$delim1.$yrlow.$delim2
		. "12".$delim1.strip_quotes($cols[7]).$delim2
		. "13".$delim1.strip_quotes($cols[8]).$delim2
		. "21".$delim1.strip_quotes($cols[9]).$delim2
		;

	    printf OUT "YAHOO %s %s\n", $sym, $outstr;
	    if ( $verbose > 2 ) {
		printf "YAHOO %s\n", join('|',@cols);
	    } elsif ( $verbose > 1 ) {
		printf "YAHOO %s %s\n", $sym, $outstr;
	    }
	    #printf "YAHOO %s %s\n", $sym, $outstr;
	}
	close OUT;

    } else {
	close(PIPE);
	if ( $CHILD_ERROR != 0 ) {
	    my $exit_value = $? >> 8;
	    my $sig = $? & 127;
	    print "Exception running the program (".
		(($exit_value!=0)?"exit=$exit_value ":"").
		(($sig!=0)?"signal=$sig":"").
		")\n";
	    system("cat $badfile");
	    cleanup();
	    exit 1;
	}
    }

    my $total = $cash1 + $cash2;
    my $total1 = $cash1;
    my $total2 = $cash2;
    my $total_change = 0;
    my $total_pnl = 0;

    # total cash
    my $HaveCash;
    if ( $total > 0 ) {
	$HaveCash = 1;
    } else {
	$HaveCash = 0;
    }

    if ( $verbose > 1 ) {
	print "Has multiple=$has_multiple_quantity\n";
    }

    open(READIN,"$outfile") or die "Cannot read $outfile: $!";
    modeon($headerhighlight);
    print " Name                Last  YrHigh   YrLow  ";
    if ( $do_wide ) {
	print "  High     Low  Change     Volume  ";
    } else {
	print "Change  ";
    }
    if ( $has_multiple_quantity > 0 ) {
	print "  Sub1    Sub2   Total DayPNL";
    } else {
	print " Total DayPNL";;
    }
    if ( $do_wide ) {
    	print "    PNL";
    }
    print "\n";
    modeoff();

    while (<READIN>) {
	my $inline = $_;

	chop;

	my ($source, $record, $Rest) = (/^(\S+)\s+(\S+)\s+(.*)$/);
	my $amt1 = $amount1{$record} || 0;
	my $amt2 = defined $amount2{$record} ? $amount2{$record} : 0;
	my $purch  = $purchase{$record} || 0;

	if ( $verbose > 1 and ( $record =~ /^GE/ or $record =~ /.DJI/ or $record =~ /INDU/ or $record eq "NGQ15.NYM" ) ) {
	    printf "%s: Purch %d Amt %d %d Rest %s\n",
		$record, $purch, $amt1, $amt2, $Rest;
	    printf "@_";
	}

	my ($name, $last, $prev, $change, $high, $low, $volume, $yr_high, $yr_low, $nav, $nav_prev, $bid, $ask, $prev_bid, $prev_ask)
	     = ("", 0.0,  0.0,   0.0,     0.0,   0.0,  0,       0.0,      0.0,     0.0,  0.0,       0.0,  0.0,   0.0,      0.0);

	# EC: 4-3-2012 stupid ICE symbol for HU (unleaded gas)
	my @fiddata = split /$delim2/, $Rest;
	# Could read it all in one step to an associative array
	# TODO: would not need the defs if using the fid map and using the associations!
	foreach my $field ( @fiddata ) {

	    my ($fid, $val) = split /$delim1/, $field;

	    if ( $verbose > 1 and $record =~ /^GE|IBB/ ) {
		printf "Field:%s Delim2=$delim2 Delim1=$delim1 Fid: %s Value: %s\n",$field, $fid, $val;
	    }

	    if ( $fid == 3 ) {
		$name = $val;
		if ( $name =~ /^$/ or $name eq '0' ) {
		    $name = $record;
		    #print "IN=$inline";
		} elsif ( $name =~ s/delayed-\d+//i ) {
		    if ( $record eq "GCc1" ) {
			$name = "GOLD! ";
		    }
		    $name .= "(".$record.")";
		}
		# hard to remember this is unleaded gasoline
		$name =~ s/NY RBOB/UNLEAD GAS/;
		$name =~ s/RBOB/Unlead/;
		#if ( $record eq "PRSCX" ) { print "PRSCX: desc=$name ($val)\n"; }
	    } elsif ( $fid == 6 ) {
		$last = $val;
	    } elsif ( $fid == 21 ) {
		$prev = $val;
	    } elsif ( $fid == 11 ) {
		$change = $val;
	    } elsif ( $fid == 12 ) {
		$high = $val;
		if ( $verbose and $record =~ /GE.N/ ) {
		    print "[++High=$high]\n";
		}
	    } elsif ( $fid == 13 ) {
		$low = $val;
	    } elsif ( $fid == 32 ) {
		$volume = $val;
	    } elsif ( $fid == 90 ) {
		$yr_high = $val;
	    } elsif ( $fid == 91 ) {
		$yr_low = $val;
	    } elsif ( $fid == 120 ) {
		$nav = $val;
	    } elsif ( $fid == 154 ) {
		$nav_prev = $val;

	    # currency/metals
	    } elsif ( $fid == 967 ) {
		if ( $val !~ /^\s*$/ and $val !~ /B2$/ ) {
		    $name = $val;
		}
	    } elsif ( $fid == 22 ) {
		$bid = $val;
	    } elsif ( $fid == 25 ) {
		$ask = $val;
	    } elsif ( $fid == 60 ) {
		$prev_bid = $val;
	    } elsif ( $fid == 61 ) {
		$prev_ask = $val;
	    } elsif ( $fid == 62 and $val > 0.0 ) {
		#62: +381.65
		$yr_high = $val;
	    } elsif ( $fid == 63 and $val > 0.0 ) {
		#63: +129.00
		$yr_low = $val;
	    } elsif ( $fid == 203 and $val > 0.0 ) {
		$high = $val;
	    } elsif ( $fid == 204 and $val > 0.0 ) {
		$low = $val;
	    } elsif ( $fid == 205 and $val > 0.0 ) {
		$yr_high = $val;
	    } elsif ( $fid == 206 and $val > 0.0 ) {
		$yr_low = $val;
	    }
	}

	if ( $verbose and $record =~ /GE.N/ ) {
	    print "[High=$high]\n";
	}

#print "$name: last=$last nav=$nav bid=$bid ask=$ask\n" if $record =~ /IBB/;
	if ( $last == 0.0 ) {
	    if ( $prev != 0.0 ) {
		$last = $prev;
	    } elsif ( $nav != 0.0 ) { # mutual fund
#print "$name: You're not a mutual fund!\n" if $record =~ /IBB/;
		$last = $nav;
		$prev = $nav_prev;
		$change = $nav - $nav_prev;
	    } elsif ( $bid != 0.0 and $ask != 0.0 ) { # currency/metal
#print "$name: You're not a comodty fund!\n" if $record =~ /IBB/;
		$last = $bid + ($ask - $bid) / 2;
		$prev = $prev_bid + ($prev_ask - $prev_bid) / 2;
		$change = $last - $prev;
	    }
	}

	my $lformat;
	if ( $last >= 10000 ) {
	    $lformat=" %7.1f";
	} elsif ( $last >= 1000 ) {
	    $lformat=" %7.2f";
	} else {
	    $lformat=" %7.3f";
	}

	my $yhformat;
	if ( $yr_high >= 10000 ) {
	    $yhformat=" %7.1f";
	} elsif ( $yr_high >= 1000 ) {
	    $yhformat=" %7.2f";
	} else {
	    $yhformat=" %7.3f";
	}

	my $ylformat;
	if ( $yr_low >= 10000 ) {
	    $ylformat=" %7.1f";
	} elsif ( $yr_low >= 1000 ) {
	    $ylformat=" %7.2f";
	} else {
	    $ylformat=" %7.3f";
	}

	my $hformat;
	if ( $high >= 10000 ) {
	    $hformat=" %7.1f";
	} elsif ( $high >= 1000 ) {
	    $hformat=" %7.2f";
	} else {
	    $hformat=" %7.3f";
	}

	my $lowformat;
	if ( $low >= 10000 ) {
	    $lowformat=" %7.1f";
	} elsif ( $low >= 1000 ) {
	    $lowformat=" %7.2f";
	} else {
	    $lowformat=" %7.3f";
	}

	my $cformat;
	if ( $change >= 10000 or $change <= -1000 ) {
	    $cformat=" %7.1f";
	} elsif ( $change >= 1000 or $change <= -100 ) {
	    $cformat=" %7.2f";
	} else {
	    $cformat=" %7.3f";
	}

	#my $vformat;
	#if ( $volume >= 1000000 ) {
	#    $vformat=" %10d";
	#} elsif ( $volume >= 100000 ) {
	#    $vformat=" %9d";
	#} else {
	#    $vformat=" %8d";
	#}

	my $sub1 = $last * $amt1;
	my $sub2 = $last * $amt2;
	my $subtotal_change;

	if (
	    # no value and not a fund that prices only after close
	    ($amt1 + $amt2 != 0) and ($nav == 0 and $high > 0)
	    or $record =~ /IBB/			# because high,low = 0
	    or $day == 0 or $day == 6		# a weekend
	    or $hour < 8 or $hour >= 17 ) {	# before trading and after quoted

	    $subtotal_change = int($change * ($amt1 + $amt2));
	} else {
	    #print "did not add change for $name\n";
	    $subtotal_change = 0;
	}
	if ( $verbose and $record =~ /IBB/ ) {
	    print "$record: $last - $prev = $subtotal_change\n";
	}

	$total_change += 0 + $subtotal_change;

	my $subtotal = 0.0;
	for ( $amt1, $amt2 ) {
	    $subtotal += $last * $_;
	}

	my $subtotal_pnl = $subtotal - $purch;

	$total1 += $sub1;
	$total2 += $sub2;
	$total += $subtotal;
	$total_pnl += $subtotal_pnl;

	#truncate($name,14);
	$name = substr($name,0,16);

	my $hilowind = ' ';
	if ( $amt1 + $amt2 > 0 ) {
	    if ( $yr_high != 0 and $last > $yr_high ) {
		modeon($uphighlight);
		$hilowind = '*';
	    } elsif ( $yr_low != 0 and $last < $yr_low ) {
		modeon($downhighlight);
		$hilowind = '*';
	    }
	}
	printf "$hilowind";

	if ( $highlight == 1 ) {
	    $highlight = 0;
	    modeon($rowhighlight1);
	} else {
	    $highlight = 1;
	    modeon($rowhighlight2);
	}
	if ( $do_wide ) {
	    if ( $has_multiple_quantity > 0 ) {
		printf
		"%-16s".$lformat.$yhformat.$ylformat.$hformat.$lowformat.$cformat.
		" %10d %7.0f %7.0f %7.0f %6.0f %6.0f\n",
		$name, $last, $yr_high, $yr_low, $high, $low, $change, $volume,
		$sub1, $sub2, $subtotal, $subtotal_change, $subtotal_pnl;
	    } else {
		printf
		"%-16s".$lformat.$yhformat.$ylformat.$hformat.$lowformat.$cformat.
		" %10d %7.0f %6.0f %6.0f\n",
		$name, $last, $yr_high, $yr_low, $high, $low, $change, $volume,
		$subtotal, $subtotal_change, $subtotal_pnl;
	    }
	} else {
	    if ( $has_multiple_quantity > 0 ) {
		if ( $verbose > 10 ) {
		    printf "name=$name, last=$last, yhi=$yr_high, ylo=$yr_low, chg=$change, sub1=$sub1, sub2=$sub2, subt=$subtotal, subc=$subtotal_change\n";
		}
		printf
		"%-16s".$lformat.$yhformat.$ylformat.$cformat.
		" %7.0f %7.0f %7.0f %6.0f\n",
		$name, $last, $yr_high, $yr_low, $change,
		$sub1, $sub2, $subtotal, $subtotal_pnl;
	    } else {
		printf
		"$%-16s".$lformat.$yhformat.$ylformat.$cformat.
		" %7.0f %6.0f\n",
		$name, $last, $yr_high, $yr_low, $change,
		$subtotal, $subtotal_pnl;
	    }
	}
	modeoff();
    }

    close(READIN);

    if ( $do_wide ) {
	if ( $has_multiple_quantity > 0 ) {
	    if ( $HaveCash ) {
		modeon($cashhighlight);
		printf " CASH %78d %7d %7d              \n",
			$cash1, $cash2, $cash1 + $cash2;
	    }
	    printf " TOTALS%77.0f %7.0f %7.0f", $total1, $total2, $total;
	    modeon($total_change>=0 ? $uphighlight : $downhighlight);
	    $total_change =~ s/^-0$/0/;
	    printf " %6.0f", $total_change;
	    modeon($total_pnl>=0 ? $uphighlight : $downhighlight);
	    printf " %6.0f\n", 0 + $total_pnl;
	    #printf " TOTALS%77.0f %7.0f %7.0f %6.0f %6.0f\n", $total1, $total2, $total, $total_change, $total_pnl;
	} else {
	    if ( $HaveCash ) {
		modeon($cashhighlight);
		printf " CASH %76d       \n", $cash1;
	    }
	    printf " TOTALS%75.0f",$total;
	    modeon($total_change>=0 ? $uphighlight : $downhighlight);
	    printf " %6.0f", $total_change;
	    modeon($total_pnl>=0 ? $uphighlight : $downhighlight);
	    printf " %6.0f\n", 0 + $total_pnl;
	}
    } else {
	if ( $has_multiple_quantity > 0 ) {
	    if ( $HaveCash ) {
		modeon($cashhighlight);
		printf " CASH %51d %7d %7d       \n",
			$cash1, $cash2, $cash1 + $cash2;
	    }
	    modeon($total_change>=0 ? $uphighlight : $downhighlight);
	    printf " TOTALS%50.0f %7.0f %7.0f %6.0f\n",
		$total1, $total2, $total, $total_pnl;
	} else {
	    if ( $HaveCash ) {
		modeon($cashhighlight);
		printf " CASH %51d       \n", $cash1;
	    }
	    modeon($total_change>=0 ? $uphighlight : $downhighlight);
	    printf " TOTALS%50.0f %6.0f\n", $total, $total_pnl;
	}
    }
    modeoff();

    if ( open(OUT, "< $errfile") ) {
	while ( <OUT> ) {
	    print $_;
	}
    }

    cleanup() unless $verbose;
}

