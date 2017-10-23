#!/bin/env perl

use strict;
use warnings;
use English;

BEGIN {
    if ( $ENV{LD_LIBRARY_PATH} !~ /mqm/ ) {
	$ENV{LD_LIBRARY_PATH} = "$ENV{LD_LIBRARY_PATH}:/tp/mqm/5.3.0/lib/";
	my $command = "$EXECUTABLE_NAME -wS $PROGRAM_NAME " . join(' ',@ARGV);
	print "exec $command\n";
	exec($command);
    }
}

use MQSeries;
use MQSeries::Command;
use MQSeries::Message;

my $CompCode = MQCC_FAILED;
my $Reason = MQRC_UNEXPECTED_ERROR;

$ENV{MQSERVER} = "S_G5/TCP/mq-csprod.citadelsolutions.com(2414)"; 

my $coption = {	ChannelName    => 'S_G5',
		TransportType  => 'TCP',
		ConnectionName => 'mq-csprod.citadelsolutions.com(2414)',
		#MaxMsgLength   => 16 * 1024 * 1024,
	    };

my $queue = MQSeries::Queue->new
    (
	QueueManager => 'QM_G5',
	Queue => 'G5.RECONCILE.REFERENTIAL.QUEUE',
	Mode => 'input_shared',
	CompCode => \$CompCode,
	Reason => \$Reason,
	#Options => $coption,
    ) or die "unable to open queue $Reason $CompCode\n";

while ( 1 ) {

    my $getmessage = MQSeries::Message->new;

    my $ret = $queue->Get
	(
	    Message => $getmessage,
	    Sync => 1,
	);

    die
	( "Unable to get message\n" .
	  "Ret = $ret\n" .
	  "CompCode = " . $queue->CompCode() . "\n" .
	  "Reason = " . $queue->Reason() . "\n" .
	  Dumper($getmessage)."\n"
	)
	unless $ret;
	#unless $ret and $ret != -1;

    last if $ret == -1;

    print "Data: " . $getmessage->Data() . "\n\n";
}

