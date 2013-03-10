use strict;
use warnings;
use Test::More tests => 114;
use Test::Exception;

BEGIN { use_ok 'X12::Schema::Element'; }
use X12::Schema::TokenSink;

my $sink = X12::Schema::TokenSink->new( element_sep => '*', segment_term => "~\n", component_sep => '\\', repeat_sep => '^' );

my $el;

throws_ok { X12::Schema::Element->new(name => 'Foo') } qr/type.*required/;
throws_ok { X12::Schema::Element->new(type => 'N 3/3') } qr/name.*required/;

throws_ok { X12::Schema::Element->new(name => 'Foo', type => 'X 2/3') } qr/type at BUILD must look like/;
throws_ok { X12::Schema::Element->new(name => 'Foo', type => 'ID 2/3') } qr/expand required/;
throws_ok { X12::Schema::Element->new(name => 'Foo', type => 'R3 2/3') } qr/Numeric postfix/;

sub elem_test {
    my $type = shift;
    my $expand = ($type =~ /^ID/) ? shift : undef;

    my ($el, $real);
    lives_ok { $el = X12::Schema::Element->new(name => 'EL', type => $type, $expand ? (expand => $expand) : ()) } "can parse $type" or return;

    while (@_) {
        my ($flag, $in, $out) = splice @_, 0, 3;
        my ($pin, $pout) = ($in, $out);
        s/[^ -~]//g for $pin, $pout;

        if ($flag eq 'encode') {
            if (ref($out)) {
                throws_ok { $el->encode($sink, $in) } qr/$out EL\n/, "encode fails ($type) ($pin) ($out)";
            } else {
                lives_ok { $real = $el->encode($sink, $in) } "encode succeeds ($type) ($pin)";
                is $real, $out, "result is ($pout)";
            }
        }
    }
}

elem_test('R 1/5',
    encode => 0, '0',
    encode => 9, '9',
    encode => 9.5, '9.5',
    encode => 12.444, '12.444',
    encode => 12.4444, '12.444',
    encode => -12.444, '-12.444',
    encode => 0.25, '0.25',
    encode => 99999.2, '99999',
    encode => 99999.6, qr/Value 99999.6 cannot fit in 5 digits for/,
    encode => 9999.96, '10000',
    encode => -9999.96, '-10000',
    encode => -99999.6, qr/Value -99999.6 cannot fit in 5 digits for/,
);

elem_test('R 3/5',
    encode => 0, '000',
    encode => 95, '095',
    encode => 1.2, '01.2',
    encode => -1.2, '-01.2',
    encode => 3999, '3999',
    encode => -100000, qr/Value -100000 cannot fit in 5 digits for/,
);

elem_test('N0 3/5',
    encode => 32.2, '032',
    encode => -995, '-995',
    encode => 99995, '99995',
    encode => -99995, '-99995',
    encode => 99999.9, qr/Value 99999.9 cannot fit in 5 digits for/,
    encode => -99999.9, qr/Value -99999.9 cannot fit in 5 digits for/,
);

elem_test('N2 4/6',
    encode => 0, '0000',
    encode => -2, '-0200',
    encode => 0.02, '0002',
);

elem_test('N 3/5',
    encode => 0, '000',
    encode => -2.4, '-002',
);

elem_test('ID 2/3', { A => 'SingleA', AA => 'DoubleA', AAA => 'TripleA' },
    encode => SingleA => 'A ',
    encode => DoubleA => 'AA',
    encode => TripleA => 'AAA',
    encode => TetraA => qr/Value TetraA not contained in DoubleA, SingleA, TripleA for/,
    encode => A => qr/Value A not contained in DoubleA, SingleA, TripleA for/,
);

elem_test('AN 2/4',
    encode => 'F' => 'F ',
    encode => 'FF' => 'FF',
    encode => 'FFFF' => 'FFFF',
    encode => 'FFFFF' => qr/Value FFFFF does not fit in 4 characters for/,
    encode => 'F^' => qr/Value F\^ after encoding would contain a prohibited delimiter.*/,
);

elem_test('DT 6/6',
    encode => DateTime->new(year => 1995, day => 23, month => 11), '951123',
    encode => DateTime->new(year => 2009, day =>  7, month =>  3), '090307',
    encode => DateTime->new(year => -1, day => 1, month => 1), qr/Value.*is out of range for/,
);

elem_test('DT 6/8',
    encode => DateTime->new(year => 1995, day => 23, month => 11), '19951123',
    encode => DateTime->new(year => 2009, day =>  7, month =>  3), '20090307',
    encode => DateTime->new(year => -1, day => 1, month => 1), qr/Value.*is out of range for/,
);

elem_test('TM 4/4',
    encode => DateTime->new(year => 1970, hour =>  0, minute => 2, second => 3), '0002',
    encode => DateTime->new(year => 1970, hour => 11, minute => 2, second => 3), '1102',
    encode => DateTime->new(year => 1970, hour => 12, minute => 2, second => 3), '1202',
    encode => DateTime->new(year => 1970, hour => 23, minute => 2, second => 3), '2302',
);

elem_test('TM 4/6',
    encode => DateTime->new(year => 1970, hour =>  0, minute => 2, second => 3), '000203',
    encode => DateTime->new(time_zone => 'UTC', year => 1972, month => 12, day => 31, hour => 23, minute => 59, second => 60), '235959',
);

elem_test('TM 4/8',
    encode => DateTime->new(year => 1970, hour =>  0, minute => 2, second => 3, nanosecond => 34e7), '00020334',
);

elem_test('B 0/0',
    encode => join('',map chr, 0..255), join('',map chr, 0..255),
);
