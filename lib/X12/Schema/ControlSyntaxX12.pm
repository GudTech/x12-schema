package X12::Schema::ControlSyntaxX12;

use Moose;
use namespace::autoclean;

use X12::Schema::Segment;
use X12::Schema::Element;

has '_segments' => (is => 'bare');
has 'tx_set_def' => (is => 'ro', isa => 'X12::Schema::Sequence', required => 1);

sub _setup {
    my ($self, $vers) = @_;

    $self->{_segments} = {
        ISA => X12::Schema::Segment->new(
            tag => 'ISA', friendly => 'ISA',
            elements => [
                X12::Schema::Element->new( name => 'AuthQual', required => 1, type => 'ID 2/2', expand => { '00' => 'None', '01' => 'UCS', '02' => 'EDX', '03' => 'AdditionalData', '04' => 'Rail', '05' => 'DoD', '06' => 'Federal' } ),
                X12::Schema::Element->new( name => 'Auth', required => 1, type => 'AN 10/10', allow_blank => 1 ),
                X12::Schema::Element->new( name => 'SecQual', required => 1, type => 'ID 2/2', expand => { '00' => 'None', '01' => 'Password' } ),
                X12::Schema::Element->new( name => 'Sec', required => 1, type => 'AN 10/10', allow_blank => 1 ),
                X12::Schema::Element->new( name => 'SenderQual', required => 1, type => 'ID 2/2' ),
                X12::Schema::Element->new( name => 'Sender', required => 1, type => 'AN 15/15' ),
                X12::Schema::Element->new( name => 'ReceiverQual', required => 1, type => 'ID 2/2' ),
                X12::Schema::Element->new( name => 'Receiver', required => 1, type => 'AN 15/15' ),
                X12::Schema::Element->new( name => 'Date', required => 1, type => 'DT 6/6' ),
                X12::Schema::Element->new( name => 'Time', required => 1, type => 'TM 4/4' ),
                X12::Schema::Element->new( name => 'VersionQual', required => 1, $vers ge '00402' ? (type => 'B 1/1') : (type => 'ID 1/1', expand => { U => 'US' }) ),
                X12::Schema::Element->new( name => 'Version', required => 1, type => 'ID 5/5' ),
                X12::Schema::Element->new( name => 'InterchangeNo', required => 1, type => 'N 9/9' ),
                X12::Schema::Element->new( name => 'AckRequested', required => 1, type => 'ID 1/1', expand => { 0 => 0, 1 => 1 } ),
                X12::Schema::Element->new( name => 'Usage', required => 1, type => 'ID 1/1', expand => { P => 'Production', T => 'Test' } ),
                X12::Schema::Element->new( name => 'ComponentSep', required => 1, type => 'B 1/1' ),
            ]
        ),
        GS => X12::Schema::Segment->new(
            tag => 'GS', friendly => 'GS',
            elements => [
                X12::Schema::Element->new( name => 'FunctionCode', required => 1, type => 'ID 2/2' ),
                X12::Schema::Element->new( name => 'Sender', required => 1, type => 'AN 2/15' ),
                X12::Schema::Element->new( name => 'Receiver', required => 1, type => 'AN 2/15' ),
                X12::Schema::Element->new( name => 'Date', required => 1, type => 'DT 8/8' ),
                X12::Schema::Element->new( name => 'Time', required => 1, type => 'TM 4/8' ),
                X12::Schema::Element->new( name => 'GroupNo', required => 1, type => 'N0 1/9' ),
                X12::Schema::Element->new( name => 'VersionQual', required => 1, type => 'ID 1/2', expand => { T => "TDCC", X => "X12" } ),
                X12::Schema::Element->new( name => 'Version', required => 1, type => 'AN 1/12' ),
            ]
        ),
        ST => X12::Schema::Segment->new(
            tag => 'ST', friendly => 'ST',
            elements => [
                X12::Schema::Element->new( name => 'Type', required => 1, type => 'ID 3/3' ),
                X12::Schema::Element->new( name => 'TxSetNo', required => 1, type => 'AN 4/9' ),
            ]
        ),

        SE => X12::Schema::Segment->new(
            tag => 'SE', friendly => 'SE',
            elements => [
                X12::Schema::Element->new( name => 'SegmentCount', required => 1, type => 'N0 1/10' ),
                X12::Schema::Element->new( name => 'TxSetNo', required => 1, type => 'AN 4/9' ),
            ]
        ),
        GE => X12::Schema::Segment->new(
            tag => 'GE', friendly => 'GE',
            elements => [
                X12::Schema::Element->new( name => 'SetCount', required => 1, type => 'N0 1/6' ),
                X12::Schema::Element->new( name => 'GroupNo', required => 1, type => 'N0 1/9' ),
            ]
        ),
        IEA => X12::Schema::Segment->new(
            tag => 'IEA', friendly => 'IEA',
            elements => [
                X12::Schema::Element->new( name => 'GroupCount', required => 1, type => 'N0 1/5' ),
                X12::Schema::Element->new( name => 'InterchangeNo', required => 1, type => 'N0 9/9' ),
            ]
        ),
    };
}

sub parse_interchange {
    my ($self, $source) = @_;

    die "Interchange must start with ISA\n" unless $source->peek_code eq 'ISA';
    my $ver = $source->peek->[12][0][0];
    $ver =~ /^[0-9]{5}$/ or die "Malformed interchange syntax version number\n";

    $self->_setup($ver);
    my $ISA = $self->{_segments}{ISA}->decode( $source );

    my $isa_time = delete $ISA->{Time};
    $ISA->{Date}->set( map( ($_ => $isa_time->$_) , qw( hour minute second nanosecond ) ) );

    # not actual data
    delete $ISA->{VersionQual} if $ver ge '00402';
    delete $ISA->{ComponentSep};

    my @groups;

    while ($source->peek_code eq 'GS') {
        my $GS = $self->{_segments}{GS}->decode( $source );
        my @txsets;
        my %txsetids;
        # DIVERSITY: we may need to execute a syntax switch here at some point

        my $gs_time = delete $GS->{Time};
        $GS->{Date}->set( map( ($_ => $gs_time->$_) , qw( hour minute second nanosecond ) ) );

        while ($source->peek_code eq 'ST') {
            my $icount = $source->segment_counter;
            my $ST = $self->{_segments}{ST}->decode( $source );

            # DIVERSITY: will need to select this on the basis of $ST->{Type}
            my $defn = $self->tx_set_def;

            #my $defn = $self->types->{ "$GS->{VersionQual} $GS->{Version} $ST->{Type}" }
            #    or die "No schema available for standard=$GS->{VersionQual} $GS->{Version} transaction set type=$ST->{Type}\n";

            my $body = $defn->decode( $source, { SE => 1 } );

            die "Expected SE after transaction set, found ".$source->peek_code."\n" unless $source->peek_code eq 'SE';
            my $SE = $self->{_segments}{SE}->decode( $source );
            my $count = $source->segment_counter - $icount;

            die "Transaction set control numbers $ST->{TxSetNo} in header and $SE->{TxSetNo} in footer do not match\n" unless $ST->{TxSetNo} eq $SE->{TxSetNo};
            die "Transaction set $ST->{TxSetNo} claims $SE->{SegmentCount} children but has $count\n" if $count != $SE->{SegmentCount};
            die "Transaction set identifier $ST->{TxSetNo} used more than once\n" if $txsetids{$ST->{TxSetNo}}++;

            push @txsets, { ID => $ST->{TxSetNo}, Code => $ST->{Type}, Data => $body };
        }

        die "Expected GE after group $GS->{GroupNo}, found ".$source->peek_code."\n" if $source->peek_code ne 'GE';
        my $GE = $self->{_segments}{GE}->decode( $source );

        die "Group control numbers $GS->{GroupNo} in header and $GE->{GroupNo} in footer do not match\n" if $GS->{GroupNo} != $GE->{GroupNo};
        die "Group $GS->{GroupNo} claims $GE->{SetCount} children but has ${\ scalar @txsets }\n" if @txsets != $GE->{SetCount};

        push @groups, { %$GS, TransactionSets => \@txsets };
    }

    die "Expected IEA after interchange $ISA->{InterchangeNo}, found ".$source->peek_code."\n" if $source->peek_code ne 'IEA';
    my $IEA = $self->{_segments}{IEA}->decode( $source );

    die "Interchange control numbers $ISA->{InterchangeNo} in header and $IEA->{InterchangeNo} in footer do not match\n" if $ISA->{InterchangeNo} != $IEA->{InterchangeNo};
    die "Interchange $ISA->{InterchangeNo} claims $IEA->{Count} children but has ${\ scalar @groups }\n" if @groups != $IEA->{GroupCount};

    return { %$ISA, Groups => \@groups };
}

sub emit_interchange {
    my ($self, $sink, $data) = @_;

    $self->_setup( $data->{Version} );

    my $ISA = { %$data };
    delete $ISA->{Groups};
    $ISA->{Time} = $ISA->{Date};

    $ISA->{ComponentSep} = $sink->component_sep;
    $ISA->{VersionQual}  = $sink->repeat_sep if $ISA->{Version} ge '00402';

    $self->{_segments}{ISA}->encode( $sink, $ISA );

    for my $gr (@{ $data->{Groups} }) {
        my $GS = { %$gr };
        delete $GS->{TransactionSets};

        $GS->{Time} = $GS->{Date};

        $self->{_segments}{GS}->encode( $sink, $GS );

        for my $st (@{ $gr->{TransactionSets} }) {
            my $ctr = $sink->segment_counter;
            $self->{_segments}{ST}->encode( $sink, { TxSetNo => $st->{ID}, Type => $st->{Code} } );
            $self->tx_set_def->encode( $sink, $st->{Data} );
            $self->{_segments}{SE}->encode( $sink, { TxSetNo => $st->{ID}, SegmentCount => $sink->segment_counter - $ctr + 1 } );
        }

        $self->{_segments}{GE}->encode( $sink, { SetCount => scalar(@{ $gr->{TransactionSets} }), GroupNo => $gr->{GroupNo} } );
    }

    $self->{_segments}{IEA}->encode( $sink, { GroupCount => scalar(@{ $data->{Groups} }), InterchangeNo => $data->{InterchangeNo} } );
}

__PACKAGE__->meta->make_immutable;
