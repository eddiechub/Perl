#!/tp/perl/5.8.3/bin/perl -w
use strict;
use XML::Parser;

my $level = 0;
my $current_str;
my $debug = $ENV{DEBUG} ? 1 : 0;

my $shift_string = " ";
my $next = 0;

# Keep track of the number of elements, so can use the no element tag suffix '<ya/>'
my %element_counts;
$element_counts{0} = 1;

sub start
{
    my ($parser, $name, %attr) = @_;
    if ( $level > 0 && $element_counts{$level-1} > 0 ) {
	$current_str .= "\n";
    }
    $current_str .= $shift_string x $level;
    $current_str .= "<$name" ;
    foreach (keys %attr) { $current_str .= " $_=\"$attr{$_}\""; }
    $current_str .= ">";
    if ( $level > 0 ) { ++$element_counts{$level}; }
    ++$level;
    $element_counts{$level} = 0;
}

sub end
{
    my ($parser, $name) = @_;

    --$level;

    $current_str =~ s/\s+$//sm;
    if ( $element_counts{$level+1} == 0 && $current_str =~ /\>$/ ) {
	$current_str =~ s{\>$}{/>};
    } else {
	if ( $next != 0 ) {
	    $current_str .= "\n" . $shift_string x $level;
	}
	$current_str .= "</$name>";
    }
    $current_str .= "\n";
    if ( $level == 0 ) {
	print $current_str;
	$current_str = "";
    }
    $next = 1;
}

sub cdata
{
    my ($parser, $data) = @_;
    $data =~ s/^\s+//sm;
    $data =~ s/\s+$//sm;
    $current_str .= $data;
    $next = 0;
}

my $xp = XML::Parser->new();
$xp->setHandlers(Start => \&start, End => \&end, Char => \&cdata);

print "At least one file should be specified\n" and exit 1 unless @ARGV;

foreach (@ARGV) {
    if ( -f $_ ) {
	print "$_\n";
	$xp->parsefile($_)
    } else {
	print "Can't find file: $_\n";
    }
}

