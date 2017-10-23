#!/tp/perl/5.8.3/bin/perl -w

use strict;
use English;
use Date::Manip;

BEGIN {
    if ( $ENV{LD_LIBRARY_PATH} !~ /mqm/ ) {
	$ENV{LD_LIBRARY_PATH} = $ENV{LD_LIBRARY_PATH} . ":/tp/mqm/5.3.0/lib/";
	my $command = "$EXECUTABLE_NAME -wS $PROGRAM_NAME " . join(' ',@ARGV);
	print "exec $command\n";
	exec($command);
    }
}

use MQSeries;
use MQSeries::Command;
use MQSeries::Message;

use Data::Dumper;

my $CompCode = MQCC_FAILED;
my $Reason = MQRC_UNEXPECTED_ERROR;

#$ENV{MQSERVER} = "S_G3/TCP/mq-dev.wfg.com(3414)"
#$ENV{MQSERVER} = "S_G4/TCP/mq-csprod.citadelsolutions.com(1414)"
$ENV{MQSERVER} = "/S_G3/TCP/MQ-G3-STABLEDEV.citadelgroup.com(1414)"
    unless defined $ENV{MQSERVER};

insert_msymbol_gmsym("TEST123", 99999);
update_msymbol_gmsym("TEST123", "TEST1234", 99999);

sub insert_msymbol_gmsym
{
    my ($msym, $msuk) = @_;

    my $queuename = 'SECURITY.MSYMBOL.UPD';

    my $action_id = 1; # 1 = insert, 2 = update
    my $mlen = length($msym);
    my $val = pack("NNNa${mlen}", $action_id, $msuk, $mlen, $msym);

    writequeue($queuename, $val);
}

sub update_msymbol_gmsym
{
    my ($oldmsym, $msym, $msuk) = @_;

    my $queuename = 'SECURITY.MSYMBOL.UPD';

    my $action_id = 2; # 1 = insert, 2 = update
    my $omlen = length($oldmsym);
    my $mlen = length($msym);
    my $val = pack("NNNa${mlen}Na${omlen}", $action_id, $msuk, $mlen, $msym, $omlen, $oldmsym);

    writequeue($queuename, $val);
}

sub writequeue
{
    my ($queuename, $val) = @_;

    my $queue = MQSeries::Queue->new
	(
	    QueueManager => 'QM_G4',
	    Queue => $queuename,
	    Mode => 'output',
	    CompCode => \$CompCode,
	    Reason => \$Reason,
	) or die "unable to open queue for writing $Reason $CompCode\n";

    my $message = MQSeries::Message->new;

    $message->Data($val);
    my $ret = $queue->Put(Message => $message);
    die
	( "Unable to PUT message\n" .
	  "Ret = $ret\n" .
	  "CompCode = " . $queue->CompCode() . "\n" .
	  "Reason = " . $queue->Reason() . "\n" .
	  Dumper($message)."\n"
	)
	unless $ret;

}

sub readqueue
{
    my $queuename = 'SECURITY.MSYMBOL.UPD';
    my $options = 'MQOO_INQUIRE';
    my $queue = MQSeries::Queue->new
	(
	    QueueManager => 'QM_G4',
	    Queue => $queuename,
	    Mode => 'input_shared',
	    CompCode => \$CompCode,
	    Reason => \$Reason,
	) or die "unable to open queue ($queuename) for reading (shared) $Reason $CompCode: " . (MQReasonToText($Reason))[0] . "\n";
	    #ObjDesc => [],
	    #Options => MQOO_INPUT_SHARED | MQOO_FAIL_IF_QUIESCING | MQOO_INQUIRE,
	    #Options => MQOO_INPUT_SHARED,

=nana
    my $inq = $queue->ObjDesc;
    foreach my $key (keys %$inq) {
	print "$key $inq->{$key}\n"
	    if $inq->{$key} !~ /^\s*$/;
    }
    print "\n";
=cut

    my %inq = $queue->Inquire
	(
qw(AlterationDate AlterationTime CurrentQDepth QName QType QDesc OpenInputCount DefinitionType TriggerType Usage Shareability RetentionInterval MsgDeliverySequence)
	) or print((MQReasonToText($queue->Reason()))[0] . "\n\n");

    print "Queue Size=$inq{CurrentQDepth}\n" if defined $inq{CurrentQDepth};
=nana
    foreach my $key (keys %inq) {
	print "$key $inq{$key}\n"
	    if $inq{$key} !~ /^\s*$/;
    }
    print "\n";
=cut

    my $num_msgs=0;
    my $tries = 0;
    my $message = MQSeries::Message->new;
    while ( 1 ) {

	my $ret = $queue->Get
	    (
		Message => $message,
		#Sync => 1,
	    );

	die
	    ( "Unable to GET message\n" .
	      "Ret = $ret\n" .
	      "CompCode = " . $queue->CompCode() . "\n" .
	      "Reason = " . $queue->Reason() . "\n" .
	      Dumper($message)."\n"
	    )
	    unless $ret;

	if ( $ret == -1 and $tries++ < 10 ) {
	    sleep 1;
	    next;
	}

	last if $ret == -1;

	#print Dumper($message->Data())."\n";
	if ( $message->Data() ) {
=nana
	    my $mdesc = $message->MsgDesc();
	    foreach my $key (keys %$mdesc) {
		print "$key $mdesc->{$key}\n"
		    if $mdesc->{$key} !~ /^\s*$/;
	    }
	    print "\n";
=cut
	    print "Data: " . $message->Data() . "\n\n";
	}
	$num_msgs++;
    }
    print "Num Messages Read=$num_msgs\n";
}

