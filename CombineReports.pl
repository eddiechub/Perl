#!/bin/env perl

use warnings;
use strict;

use Spreadsheet::WriteExcel;
use Text::ParseWords;
use Date::Manip;
use File::Basename;

unless ( scalar @ARGV > 0 ) {
    die "No args, no report!";
}

# use the first arg to generate a report name
my $rpt_date = ($ARGV[0] =~ m/.+\.(\d+-\d+-\d{4})\./)[0]
    || UnixDate("now","%Y%m%d");
my $rpt_name = "CombinedReport";
my $rpt_file = $rpt_name . $rpt_date . ".xls";
my $delimiter = "\t";
print "Report file is $rpt_file\n";

# Create a new Excel workbook
my $workbook = Spreadsheet::WriteExcel->new($rpt_file);

#  Add and define a format
my $format_header = $workbook->add_format();
$format_header->set_bold();
$format_header->set_color('blue');
$format_header->set_align('center');
$format_header->set_align();

my $format_data = $workbook->add_format();
#$format_data->set_shrink();
$format_data->set_align('left');

foreach my $file (@ARGV)
{
    next if $file =~ /^$/;
    print "$file\n";
    open FILE, $file or die "Can't open $file: $!";

    # Add a worksheet
    #my $rpt_tab = ($file =~ m/^.+\/([^._]+).+$/)[0];
    my $rpt_tab = basename($file,".xls");
    $rpt_tab =~ s/_.+//;
    print "Adding worksheet: ".$rpt_tab."\n";

    my $worksheet = $workbook->add_worksheet($rpt_tab);
    my $header = <FILE>;
    my @headers = parse_line($delimiter,1,$header);
    if ( $headers[0] =~ /^C0./ ) {
	# go back to begin, not a header
	seek(FILE, 0, "SEEK_SET");
    } else {
	for ( my $col=0; $col < scalar(@headers); $col++ ) {
	    $worksheet->write_string(0, $col, $headers[$col], $format_header);
	}
	$worksheet->freeze_panes(1,0);
    }

    my @maxpositions;
    my $row = 0;
    while ( my $line = <FILE> )
    {
	$row++;
	chomp $line;

	my @data = split /$delimiter/,$line;
	#my @data = parse_line($delimiter,1,$line);
	for ( my $col=0; $col < scalar(@data); $col++ ) {

	    $worksheet->write($row, $col, $data[$col], $format_data);

	    my $collen = length($data[$col])+1;
	    $maxpositions[$col] = 0 unless $maxpositions[$col];
	    if ( $maxpositions[$col] < $collen ) {
		$maxpositions[$col] = $collen < 50 ? $collen : 50;
	    }
	}
    }

    #$worksheet->set_zoom(120);
    #$worksheet->set_print_scale(70);
    $worksheet->fit_to_pages(1);
    $worksheet->repeat_rows(0);
    $worksheet->print_area(0,0,$row+1,2);
    $worksheet->set_footer("&LG5 2.0&C$file&R$rpt_date");
    $worksheet->set_header("&C$file");

    #$worksheet->set_selection(0,0,$row+1,2);
    for ( my $col = 0; $col < scalar(@maxpositions); $col++ ) {
	$worksheet->set_column($col,$col,$maxpositions[$col],$format_data);
    }
}

$workbook->close();

