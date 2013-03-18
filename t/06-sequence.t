use strict;
use warnings;
use Test::More tests => 9;
use Test::Exception;

use X12::Schema::Element;
use X12::Schema::Segment;
use X12::Schema::SegmentUse;
use X12::Schema::TokenSink;
use X12::Schema::TokenSource;
BEGIN { use_ok('X12::Schema::Sequence') or die }

my $sink = X12::Schema::TokenSink->new( component_sep => '/', element_sep => '*', segment_term => '~' );

my $source;

sub mksource {
    $source = X12::Schema::TokenSource->new(buffer => $_[0]);
    $source->set_delims('/',undef,'*','~','');
}

sub mksegment {
    my $name = shift;
    return X12::Schema::SegmentUse->new(
        name => $name, @_,
        def => X12::Schema::Segment->new( tag => $name, friendly => $name, elements => [
            X12::Schema::Element->new( name => 'X', type => 'AN 1/1' )
        ] )
    );
}

sub outtest {
    my ($sg, $data, $expect, $name) = @_;

    $sink->output('');
    if (ref($expect)) {
        throws_ok { $sg->encode($sink, $data) } $expect, $name;
    } else {
        lives_ok { $sg->encode($sink, $data) } "$name (1)";
        is $sink->output, $expect, "$name (2)";
    }
}


my $seq1 = X12::Schema::Sequence->new(
    name => 'ROOT',
    children => [
        mksegment('AAA'),
        mksegment('BBB', required => 1),
        mksegment('CCC', max_use => 5),
        mksegment('DDD', max_use => undef, required => 1),
    ]
);

outtest $seq1, undef, qr/encode a HASH/, 'HASH required (1)';
outtest $seq1, 22, qr/encode a HASH/, 'HASH required (2)';
outtest $seq1, [], qr/encode a HASH/, 'HASH required (3)';

outtest $seq1, {}, qr/Segment or loop BBB is required/, 'Requirement check, nonrep';
outtest $seq1, { BBB => {X=>1} }, qr/Segment or loop DDD is required/, 'Requirement check, nonrep';
outtest $seq1, { BBB => {X=>1}, DDD => [{X=>2},{X=>3}] }, 'BBB*1~DDD*2~DDD*3~', 'Requirement check, satisfied';

outtest $seq1, { BBB => {X=>1}, DDD => [{X=>2},{X=>3}], EEE => {X=>4} }, qr/Unused children passed to ROOT: EEE/, 'Unused children';

